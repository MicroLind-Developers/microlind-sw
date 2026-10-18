; Boot-only UART A progress. Fixed ROM helpers keep presentation outside core.
; IRQ/FIRQ masked, privileged, valid common stack; no allocation or disk access.
; Every helper preserves CC,D,X,Y,U,V,W,DP; output is bounded/best-effort.

; Function: rom_boot_status. Inputs B=BOOT_MSG_*; outputs bounded stage text.
; Clobbers none. Stack<=18 including nested text/putc calls. Invalid ID ignored.
rom_boot_status:
    pshs cc,d,x,y
    cmpb #BOOT_MSG_COUNT
    bhs rbs_done
    clra
    lslb
    ldx #rbs_messages
    ldx d,x
    jsr rom_boot_text
rbs_done:
    puls cc,d,x,y,pc

; Function: rom_boot_image. Inputs X=validated installed filename (<=47 bytes).
; Outputs loading label/name; clobbers none. Stack<=18, no borrowed pointer kept.
rom_boot_image:
    pshs cc,d,x,y
    tfr x,y
    ldx #rbi_prefix
    jsr rom_boot_text
    bcs rbs_done
    tfr y,x
    jsr rom_boot_text
    bcs rbs_done
    ldx #rbi_suffix
    jsr rom_boot_text
    bra rbs_done

; Function: rom_boot_text. Inputs X=NUL string<=96 bytes. Outputs C1 if UART
; unavailable, otherwise C0. Clobbers D,X; no unbounded TX wait or retained state.
rom_boot_text:
    ldb #96
rbt_next:
    lda ,x+
    beq rbt_done
    jsr rom_putc
    bcs rbt_return
    decb
    bne rbt_next
rbt_done:
    andcc #$FE
rbt_return:
    rts

; Function: rom_boot_pulse. Inputs D=low16 ticks; outputs at most one ready TX
; byte per500 ticks while boot active. No polling; wrap-safe signed difference.
; Clobbers none. Stack<=5 incl return; timer caller owns serialization.
rom_boot_pulse:
    pshs cc,d
    tst BOOT_FEEDBACK_ACTIVE
    beq rbp_done
    subd BOOT_FEEDBACK_NEXT
    bmi rbp_done
    ldd 1,s
    addd #BOOT_FEEDBACK_INTERVAL
    std BOOT_FEEDBACK_NEXT
    lda UART_SRA
    bita #4
    beq rbp_done
    lda #'.'
    sta UART_TXA
rbp_done:
    puls cc,d,pc

rbs_messages:
    fdb rbs_clear,rbs_cf,rbs_root,rbs_kernel,rbs_core,rbs_validate,rbs_ready
rbs_clear:
    fcc "MLOS boot"
    fcb 13,10
    fcn "Clearing memory..."
rbs_cf:
    fcb 13,10
    fcn "Checking CF..."
rbs_root:
    fcb 13,10
    fcn "Checking boot filesystem..."
rbs_kernel:
    fcb 13,10
    fcn "Loading kernel..."
rbs_core:
    fcb 13,10
    fcn "Starting kernel..."
rbs_validate:
    fcb 13,10
    fcn "Checking filesystem..."
rbs_ready:
    fcb 13,10
    fcc "Boot complete"
    fcb 13,10,0
rbi_prefix:
    fcb 13,10
    fcn "Loading "
rbi_suffix:
    fcn "..."
