; Development-only target verification, linked into core for S00-S02.
; Function: core_selftest — injected rollback, exhaustion and lifetime tests.
; Inputs: freshly initialized memory. Outputs: C0 pass/C1 fail; TEST_STEP phase.
; Clobbers: all. Stack: kernel only, <64 bytes. Never executes application code.
core_selftest:
    lda #1
    sta TEST_STEP
    ldb #3
    lda #2
    sta ALLOC_FAIL_AFTER
    jsr frame_alloc_many
    bcc cs_bad
    cmpd #SYS_ENOMEM
    bne cs_bad
    lda FREE_COUNT
    cmpa #28
    bne cs_bad
    ldx #FRAME_TABLE+4*FRAME_RECORD_SIZE
cs_rollback_records:
    ldd F_OWNER,x
    bne cs_bad
    tst F_FLAGS,x
    bne cs_bad
    leax FRAME_RECORD_SIZE,x
    cmpx #FRAME_TABLE+FRAME_COUNT*FRAME_RECORD_SIZE
    blo cs_rollback_records
    lda #$FF
    sta ALLOC_FAIL_AFTER
    ldb #29
    jsr frame_alloc_many            ; actual exhaustion after 28 provisional frames.
    bcc cs_bad
    lda FREE_COUNT
    cmpa #28
    bne cs_bad

    lda #2
    sta TEST_STEP
    jsr bank_alloc
    bcs cs_bad
    std TEMP_HANDLE
    jsr handle_ref
    bcs cs_bad
    ldd TEMP_HANDLE
    jsr bank_free
    bcc cs_bad
    cmpd #SYS_EBUSY
    bne cs_bad
    ldd TEMP_HANDLE
    jsr handle_unref
    bcs cs_bad
    ldd TEMP_HANDLE
    jsr handle_pin
    bcs cs_bad
    ldd TEMP_HANDLE
    jsr bank_free
    bcc cs_bad
    ldd TEMP_HANDLE
    jsr handle_unpin
    bcs cs_bad
    ldd #2
    std CURRENT_PID
    ldd TEMP_HANDLE
    jsr handle_lookup
    bcc cs_bad
    cmpd #SYS_EOWNER
    bne cs_bad
    ldd #1
    std CURRENT_PID
    ldd TEMP_HANDLE
    jsr bank_free
    bcs cs_bad
    ldd TEMP_HANDLE
    jsr handle_lookup
    bcc cs_bad
    cmpd #SYS_ESTALE
    bne cs_bad
    jsr bank_alloc
    bcs cs_bad
    cmpd TEMP_HANDLE
    beq cs_bad
    jsr bank_free
    bcs cs_bad

    ; Exhaust generation255 and prove retirement rather than wrap/revival.
    lda #$FE
    sta HANDLE_TABLE+H_GEN
    jsr bank_alloc
    bcs cs_bad
    cmpa #$FF
    bne cs_bad
    jsr bank_free
    bcs cs_bad
    jsr bank_alloc
    bcs cs_bad
    cmpb #1
    beq cs_bad
    jsr bank_free
    bcs cs_bad
    tst HANDLE_TABLE+H_RETIRED
    beq cs_bad

    lda #3
    sta TEST_STEP
    ldd #$0100
    jsr handle_lookup
    bcc cs_bad
    ldd #$0121
    jsr handle_lookup
    bcc cs_bad
    lda FREE_COUNT
    cmpa #28
    bne cs_bad
    ; Prove whole-frame reservations and vacant parking, not merely counts.
    ldd FRAME_TABLE+F_OWNER
    cmpd #$FFFF
    bne cs_bad
    ldd FRAME_TABLE+FRAME_RECORD_SIZE+F_OWNER
    cmpd #$FFFF
    bne cs_bad
    ldd FRAME_TABLE+2*FRAME_RECORD_SIZE+F_OWNER
    cmpd #$FFFF
    bne cs_bad
    lda PROCESS_MAP+1
    cmpa #DISCARD_FRAME
    bne cs_bad
    lda PROCESS_MAP+2
    cmpa #DISCARD_FRAME
    bne cs_bad
    andcc #$FE
    rts
cs_bad:
    orcc #1
    rts
