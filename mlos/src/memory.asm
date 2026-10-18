; Memory-module defaults: internal privileged kernel calls, serialized with
; IRQ/FIRQ masked. DP arbitrary; common RAM fixed. Never sleeps; CC scratch
; except C=0 success/C=1 failure with D=negative error. No retained pointers.
; Temporary variables belong to this bounded S02 transaction, not future IRQs.

; Function: memory_init — reserve core/common/discard and initial application.
; Inputs: common cleared by ROM. Outputs: tables/PID/map/free count initialized.
; Clobbers: D,X,Y. Preserves: U,V,W. Stack: 2 bytes return. See module defaults.
memory_init:
    ldx #FRAME_TABLE
mi_clear_frames:
    clr ,x+
    cmpx #FRAME_TABLE+FRAME_COUNT*FRAME_RECORD_SIZE
    blo mi_clear_frames
    ldx #HANDLE_TABLE
mi_clear_handles:
    clr ,x+
    cmpx #HANDLE_TABLE+HANDLE_COUNT*HANDLE_RECORD_SIZE
    blo mi_clear_handles
    ldx #FRAME_TABLE
    ldb #3
mi_reserve:
    ldy #$FFFF
    sty F_OWNER,x
    lda #F_RESERVED
    sta F_FLAGS,x
    leax FRAME_RECORD_SIZE,x
    decb
    bne mi_reserve
    ldd #1
    std CURRENT_PID
    std FRAME_TABLE+APP_FRAME*FRAME_RECORD_SIZE+F_OWNER
    lda #F_RESIDENT
    sta FRAME_TABLE+APP_FRAME*FRAME_RECORD_SIZE+F_FLAGS
    lda #APP_FRAME
    sta PROCESS_MAP
    lda #DISCARD_FRAME
    sta PROCESS_MAP+1
    sta PROCESS_MAP+2
    lda #ROLE_RESIDENT
    sta PROCESS_ROLE
    clr PROCESS_ROLE+1
    clr PROCESS_ROLE+2
    lda #FRAME_COUNT-4
    sta FREE_COUNT
    lda #$FF
    sta ALLOC_FAIL_AFTER
    rts

; Function: frame_alloc_many — provisional allocation with complete rollback.
; Inputs: B=count 1..29; CURRENT_PID nonzero. Outputs: ALLOC_LIST, count; C.
; Clobbers: D,X,Y,U. Preserves: V,W. Errors: EINVAL/ENOMEM, tables unchanged.
; Stack: <=5 including frame_address and return; O(32+count). FREE_COUNT changes only at commit.
frame_alloc_many:
    clr ALLOC_COUNT
    tstb
    lbeq mem_invalid
    cmpb #FRAME_COUNT-3
    lbhi mem_invalid
    pshs b
    ldx #FRAME_TABLE+3*FRAME_RECORD_SIZE
    ldy #ALLOC_LIST
    ldu #3
fa_scan:
    tst ALLOC_FAIL_AFTER
    beq fa_rollback
    ldd F_OWNER,x
    bne fa_next
    ldd CURRENT_PID
    std F_OWNER,x
    lda #F_PROVISIONAL
    sta F_FLAGS,x
    tfr u,d
    stb ,y+
    inc ALLOC_COUNT
    lda ALLOC_FAIL_AFTER
    cmpa #$FF
    beq fa_no_injection
    dec ALLOC_FAIL_AFTER
fa_no_injection:
    lda ALLOC_COUNT
    cmpa ,s
    beq fa_commit
fa_next:
    leax FRAME_RECORD_SIZE,x
    leau 1,u
    cmpu #FRAME_COUNT
    blo fa_scan
fa_rollback:
    puls b
    ldy #ALLOC_LIST
    ldb ALLOC_COUNT
    beq fa_failed
fa_undo:
    lda ,y+
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    decb
    bne fa_undo
fa_failed:
    clr ALLOC_COUNT
    ldd #SYS_ENOMEM
    orcc #1
    rts
fa_commit:
    puls b
    lda FREE_COUNT
    suba ALLOC_COUNT
    sta FREE_COUNT
    ldy #ALLOC_LIST
fa_publish:
    lda ,y+
    jsr frame_address
    clr F_FLAGS,x
    decb
    bne fa_publish
    ldd #0
    andcc #$FE
    rts

; Function: frame_address — translate validated physical frame to common record.
; Inputs: A=0..31. Outputs: X=record. Clobbers: A,CC. Preserves: B,Y,U,V,W.
; Stack: 2 bytes return; constant cost. Internal precondition, no validation.
frame_address:
    ldx #FRAME_TABLE
    lsla
    lsla
    lsla
    leax a,x                      ; A may exceed 127: use unsigned offset below.
    tsta
    bpl fa_address_done
    leax 256,x
fa_address_done:
    rts

; Function: bank_alloc — create process-scoped generational bank handle.
; Inputs: none. Outputs: D=opaque token, C; Clobbers: X,Y,U. Preserves: V,W.
; Errors: ENOMEM with full rollback if frame or handle admission fails.
; Stack: <=7 including allocator/callees; O(32). Default module context.
bank_alloc:
    ldb #1
    jsr frame_alloc_many
    bcs ba_return
    ldx #HANDLE_TABLE
    ldb #1
ba_slot:
    tst H_LIVE,x
    bne ba_next
    tst H_RETIRED,x
    bne ba_next
    lda H_GEN,x
    cmpa #$FF
    beq ba_retire
    inca
    sta H_GEN,x
    pshs d
    ldd CURRENT_PID
    std H_OWNER,x
    lda ALLOC_LIST
    sta H_FRAME,x
    lda #1
    sta H_LIVE,x
    clr H_REFS,x
    clr H_PINS,x
    puls d
    andcc #$FE
ba_return:
    rts
ba_retire:
    inc H_RETIRED,x
ba_next:
    leax HANDLE_RECORD_SIZE,x
    incb
    cmpb #HANDLE_COUNT
    bls ba_slot
    lda ALLOC_LIST
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    inc FREE_COUNT
    ldd #SYS_ENOMEM
    orcc #1
    rts

; Function: handle_lookup — validate identity, generation, liveness and owner.
; Inputs: D=token. Outputs: X=handle record, D unchanged on success, C.
; Clobbers: Y. Preserves: U,V,W. Errors: EHANDLE/ESTALE/EOWNER; no mutation.
; Stack: 4; O(slot count). Never expose X through public ABI.
handle_lookup:
    std LOOKUP_TOKEN
    tstb
    beq hl_invalid
    cmpb #HANDLE_COUNT
    bhi hl_invalid
    ldx #HANDLE_TABLE-HANDLE_RECORD_SIZE
hl_index:
    leax HANDLE_RECORD_SIZE,x
    decb
    bne hl_index
    lda LOOKUP_TOKEN
    cmpa H_GEN,x
    bne hl_stale
    tst H_LIVE,x
    beq hl_stale
    ldy H_OWNER,x
    cmpy CURRENT_PID
    bne hl_owner
    ldd LOOKUP_TOKEN
    andcc #$FE
    rts
hl_invalid:
    ldd #SYS_EHANDLE
    bra hl_error
hl_stale:
    ldd #SYS_ESTALE
    bra hl_error
hl_owner:
    ldd #SYS_EOWNER
hl_error:
    orcc #1
    rts

; Function: bank_free — revoke resource maps then release an unreferenced frame.
; Inputs: D=handle. Outputs: D=0/C0 or error/C1. Clobbers: X,Y,U. Preserves: V,W.
; Errors: lookup errors/EBUSY for refs,pins,resident; failure changes no map.
; Stack: <=6 including frame_address; bounded 3 windows. Default module context.
bank_free:
    jsr handle_lookup
    bcs bf_return
    ifdef MLOS_RUNTIME
    lda H_LIVE,x
    cmpa #1
    lbne cl_bad
    endc
    tst H_REFS,x
    bne mem_busy
    tst H_PINS,x
    bne mem_busy
    pshs x
    lda H_FRAME,x
    jsr frame_address
    tst F_REFS,x
    bne bf_pop_busy
    tst F_PINS,x
    bne bf_pop_busy
    lda F_FLAGS,x
    bita #F_RESERVED+F_RESIDENT
    bne bf_pop_busy
    puls x
    lda H_FRAME,x
    ldy #PROCESS_MAP
    ldu #PROCESS_ROLE
    ldb #3
bf_unmap:
    cmpa ,y
    bne bf_next
    pshs a
    lda #DISCARD_FRAME
    sta ,y
    clr ,u
    puls a
bf_next:
    leay 1,y
    leau 1,u
    decb
    bne bf_unmap
    ; MMU1/2 may be scratch mappings: always synchronize before frame reuse.
    ldb PROCESS_MAP+1
    stb MMU1
    ldb PROCESS_MAP+2
    stb MMU2
    clr H_LIVE,x
    clr H_OWNER,x
    clr H_OWNER+1,x
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    inc FREE_COUNT
    ldd #0
    andcc #$FE
bf_return:
    rts
bf_pop_busy:
    puls x
mem_busy:
    ldd #SYS_EBUSY
    orcc #1
    rts
mem_invalid:
    ldd #SYS_EINVAL
    orcc #1
    rts

; Function: bank_map — map a resource into an eligible vacant/resource window.
; Inputs: D=token, B is part of token; PARAM_BUFFER+MLOS_MAP_WINDOW=window 0..2.
; Outputs: D=0/C0, or error/C1. Clobbers: X,Y,U. Preserves: V,W.
; Errors: invalid identity/window, EBUSY resident; no partial map changes.
; Stack: 4; O(32). A resident window cannot be replaced, including window0.
bank_map:
    jsr handle_lookup
    bcs bm_return
    ifdef MLOS_RUNTIME
    lda H_LIVE,x
    cmpa #1
    lbne cl_bad
    endc
    ldb PARAM_BUFFER+MLOS_MAP_WINDOW
    cmpb #3
    bhs mem_invalid
    ifdef MLOS_RUNTIME
    pshs b
    lda #1
bm_resource_bit:
    tstb
    beq bm_resource_check
    lsla
    decb
    bra bm_resource_bit
bm_resource_check:
    ldu CURRENT_PROC
    bita P_RESOURCES,u
    puls b
    lbeq mem_busy
    endc
    ldy #PROCESS_ROLE
    lda b,y
    cmpa #ROLE_RESIDENT
    beq mem_busy
    lda #ROLE_RESOURCE
    sta b,y
    lda H_FRAME,x
    ldy #PROCESS_MAP
    sta b,y
    ldy #MMU0
    sta b,y
    ldd #0
    andcc #$FE
bm_return:
    rts

; Function: bank_unmap — park a resource window before releasing its mapping.
; Inputs: PARAM_BUFFER=window. Outputs: D=0/C0 or EINVAL/EBUSY/C1.
; Clobbers: X,Y. Preserves: U,V,W. Stack: 2. No allocation/free of handle.
bank_unmap:
    ldb PARAM_BUFFER
    cmpb #3
    bhs mem_invalid
    ldx #PROCESS_ROLE
    lda b,x
    cmpa #ROLE_RESIDENT
    beq mem_busy
    clr b,x
    lda #DISCARD_FRAME
    ldx #PROCESS_MAP
    sta b,x
    ldx #MMU0
    sta b,x
    ldd #0
    andcc #$FE
    rts

; Function: handle_ref / handle_pin — acquire bounded lifetime protection.
; Inputs: D=handle. Outputs: C, D=token on success, X=record.
; Clobbers: Y. Preserves: U,V,W. Errors: lookup/EOVERFLOW, no partial count.
; Stack: 4. References protect identity; pins additionally protect frame reuse.
handle_ref:
    jsr handle_lookup
    bcs hr_return
    lda H_REFS,x
    cmpa #$FF
    beq hr_overflow
    inc H_REFS,x
    ldd LOOKUP_TOKEN
    andcc #$FE
hr_return:
    rts
handle_pin:
    jsr handle_lookup
    bcs hr_return
    lda H_PINS,x
    cmpa #$FF
    beq hr_overflow
    inc H_PINS,x
    ldd LOOKUP_TOKEN
    andcc #$FE
    rts
hr_overflow:
    ldd #SYS_EOVERFLOW
    orcc #1
    rts

; Function: handle_unref / handle_unpin — release a held lifetime protection.
; Inputs: D=handle with matching positive count. Outputs: C; D=token/error.
; Clobbers: X,Y. Preserves: U,V,W. Errors: lookup/EINVAL on underflow.
; Stack: 4; constant count mutation; see memory-module defaults.
handle_unref:
    jsr handle_lookup
    bcs hr_return
    tst H_REFS,x
    beq mem_invalid
    dec H_REFS,x
    ldd LOOKUP_TOKEN
    andcc #$FE
    rts
handle_unpin:
    jsr handle_lookup
    bcs hr_return
    tst H_PINS,x
    beq mem_invalid
    dec H_PINS,x
    ldd LOOKUP_TOKEN
    andcc #$FE
    rts
