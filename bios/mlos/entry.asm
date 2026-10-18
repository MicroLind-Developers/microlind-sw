; Entry-module defaults: fixed ROM; native MD=1 (FIRQ full-frame bit=0).
; Every full frame is CC,A,B,E,F,DP,X,Y,U,PC =14 bytes. V is software-saved.
; IRQ/FIRQ masked throughout map/record transactions. Common RAM fixed bank1.
; Records are a depth-indexed bounded LIFO, each owning its pre-entry maps/S/V.

ENTRY_V_TEMP equ $C010
ENTRY_S_TEMP equ $C012

; Function: rom_swi — enter core from application or a known ROM SWI bridge.
; Inputs: native hardware frame at S. Outputs: RTI with D/C result for calls;
; bridge results preserve the interrupted native frame; maps/S/V/DP restored.
; Clobbers: core scratch only. Application preserves B only as part of D result;
; preserves E,F,DP,X,Y,U,V,MD and CC except C. Stack: 14 hardware + common chain.
; Errors: depth overflow/emergency stop; no dynamic allocation or blocking.
rom_swi:
    orcc #$50
    sts ENTRY_S_TEMP
    tfr v,d
    std ENTRY_V_TEMP
    lda ENTRY_DEPTH
    cmpa #ENTRY_MAX
    lbhs rom_depth_panic
    ldb #ENTRY_SIZE
    mul
    ldu #ENTRY_BASE
    leau d,u
    inc ENTRY_DEPTH
    ldx ENTRY_S_TEMP
    stx R_S,u
    ldd ENTRY_V_TEMP
    std R_V,u
    lda MMU0
    sta R_MAP,u
    lda MMU1
    sta R_MAP+1,u
    lda MMU2
    sta R_MAP+2,u
    ; Native E/F already reside in the hardware frame. W is scratch until RTI.
    pshs u
    ldw #N_SIZE
rs_copy:
    tfm x+,u+
    puls u
    clr R_REASON,u
    clr R_PRIV,u                   ; ordinary app call: lock on return.
    ldd N_PC,u
    cmpd #rom_irq_cont
    beq rs_irq
    cmpd #rom_trap_cont
    beq rs_trap
    cmpd #rom_nested_cont
    beq rs_nested
    lda R_MAP,u
    cmpa #CORE_FRAME
    beq rs_bad_nested
    lda ENTRY_DEPTH
    cmpa #1
    bne rs_bad_nested              ; accidental kernel SWI is not an app call.
    bra rs_outer
rs_irq:
    lda #REASON_IRQ
    bra rs_bridge
rs_trap:
    lda #REASON_TRAP
rs_bridge:
    sta R_REASON,u
    ldx R_S,u
    lda N_SIZE,x                   ; pre-SWI captured gate bit on bridge stack.
    anda #GATE_BIT
    sta R_PRIV,u
    bra rs_choose_stack
rs_nested:
    lda #REASON_NESTED
    sta R_REASON,u
    lda #GATE_BIT
    sta R_PRIV,u
rs_choose_stack:
    tst R_PRIV,u
    bne rs_kernel_stack
    lda ENTRY_DEPTH
    cmpa #1
    bhi rs_kernel_stack
rs_outer:
    lds #KERNEL_STACK              ; before replacing application window0.
rs_kernel_stack:
    clra
    tfr a,dp
    sta MMU0
    lda R_REASON,u
    beq rs_call
    cmpa #REASON_IRQ
    beq rs_irq_service
    cmpa #REASON_NESTED
    beq rom_return
    ifdef MLOS_RUNTIME
    jsr >CORE_TRAP
    bra rom_return
    else
    ; S04 will terminate the application; S01/S02 preserve a bounded stop.
    inc TRAP_COUNT+1
    lda #$31
    jmp rom_panic
    endc
rs_call:
    jsr CORE_DISPATCH
    ifdef MLOS_RUNTIME
    jsr >$000C
    endc
    bra rom_return
rs_irq_service:
    ldd IRQ_COUNT
    addd #1
    std IRQ_COUNT
    ifdef MLOS_RUNTIME
    tst R_PRIV,u
    bne rs_runtime_tick
    ; Flatten the IRQ+bridge into the original application native frame before
    ; scheduling: no retained ROM bridge continuation on another process stack.
    ldx R_S,u
    leax N_SIZE+2,x
    stx R_S,u
    lda R_MAP,u
    sta MMU0
    pshs u
    ldw #N_SIZE
rs_irq_flatten:
    tfm x+,u+
    puls u
    clra
    sta MMU0
    clr R_REASON,u
rs_runtime_tick:
    jsr >CORE_IRQ
    endc
    bra rom_return
rs_bad_nested:
    lda #$32
    jmp rom_panic

; Function: rom_return — restore complete frame/maps from the current LIFO record.
; Inputs: U=record, privileged core/common stack. Outputs: native RTI.
; Stack: no calls after mapping restoration. Restores map0 before frame writes;
; only outer application resumes relock. Nested bridge preserves captured mode.
rom_return:
    orcc #$50                      ; protect maps/depth/relock as one transaction.
    ldd R_V,u
    tfr d,v
    lda R_MAP+1,u
    sta MMU1
    lda R_MAP+2,u
    sta MMU2
    ; A public bank syscall changes the recorded application map. On outer call
    ; use latest process maps; nested bridge restores exact interrupted maps.
    tst R_REASON,u
    bne rt_original
    lda PROCESS_MAP+1
    sta MMU1
    lda PROCESS_MAP+2
    sta MMU2
    lda PROCESS_MAP
    bra rt_map0
rt_original:
    lda R_MAP,u
rt_map0:
    sta MMU0
    ldx R_S,u
    pshs u
    ldw #N_SIZE
rt_copy:
    tfm u+,x+
    puls u
    lds R_S,u
    dec ENTRY_DEPTH
    tst R_PRIV,u
    bne rt_rti
    sta GATE
rt_rti:
    rti

; Function: rom_irq — read-ack timer, bridge only an indicated IRQ source.
; Inputs: full native IRQ frame. Outputs: original frame/privilege restored.
; Clobbers: none on RTI. Stack: 2 wrapper +14 SWI + common entry chain.
; Reads are permitted while locked. Pending non-timer sources are not enabled
; by this harness. An unknown enabled source goes to bounded diagnostics.
rom_irq:
    pshs a
    lda GATE
    anda #GATE_BIT
    pshs a
    lda UART_ISR
    bita #8
    beq ri_unknown
    lda UART_STOP                  ; timer mode: read acknowledges, keeps running.
    swi
rom_irq_cont:
    leas 1,s
    puls a
    rti
ri_unknown:
    ; Enter through SWI before any emergency UART writes.
    jmp rom_trap_bridge

; Function: rom_trap / rom_unsupported — trap/SWI2/SWI3 diagnostic stop.
; Inputs: native full frame (SWI variants do not unlock). Outputs: no resume.
; Clobbers: emergency state only. Stack: hardware frame then bridge.
rom_trap:
rom_unsupported:
    pshs a
    lda GATE
    pshs a
rom_trap_bridge:
    swi
rom_trap_cont:
    lda #$33
    jmp rom_panic

; Function: rom_nested_test — explicit privileged SWI continuation protocol.
; Inputs: privileged core stack. Outputs: preserves D/maps/permission.
; Clobbers: CC. Stack: 2 return +14 hardware +2 return copy bookkeeping.
; A mapping write after RTI proves the inner bridge has not relocked the gate.
rom_nested_test:
    swi
rom_nested_cont:
    pshs a
    lda #DISCARD_FRAME
    sta MMU2
    puls a
    rts

; Function: rom_firq — safe unused FIRQ default with MD full-FIRQ bit=0.
; Inputs: short hardware frame. Outputs: RTI unchanged; no device acknowledgement.
; Clobbers: none. Stack: hardware3 only. FIRQ remains disabled in S00-S02.
rom_firq:
    rti

; Function: rom_nmi — reserved unexpected-NMI stop; no resume/cleanup.
; Inputs: gate unlocked by qualified NMI. Outputs: best-effort saved S/reason.
; Clobbers: emergency registers. Repeated NMI stops without recursive diagnostics.
; Stack: CPU already stacked before ROM; then dedicated 510-byte emergency area.
rom_nmi:
    tst NMI_GUARD
    bne rom_nmi_repeat
    inc NMI_GUARD
    sts ENTRY_S_TEMP
    lda #$34
    bra rom_panic
rom_nmi_repeat:
    lds #EMERGENCY_STACK
    bra rom_halt
rom_depth_panic:
    lda #$35

; Function: rom_panic — bounded emergency serial marker then halt for reset.
; Inputs: A=reason, gate already unlocked. Outputs: PANIC_REASON, no return.
; Clobbers: D,X. Preserves: none promised. Stack: <=8 emergency bytes + CPU frame.
; Never uses core services/CF/allocator. UART timeout ends output, still halts.
rom_panic:
    orcc #$50
    sta PANIC_REASON
    ifdef MLOS_RUNTIME
    lda #POWER_LED_ALL
    sta UART_LED_RESET
    lda #POWER_LED_RED
    sta UART_LED_SET
    endc
    lds #EMERGENCY_STACK
    lda #'!'
    jsr rom_putc
rom_halt:
    bra rom_halt
