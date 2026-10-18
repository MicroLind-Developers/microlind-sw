; Wait defaults: serialized privileged core; check/arm/block are one transaction.
; Readiness is level-triggered; producer drain has no deadline or reclamation timer.

; Function: object_ready. Inputs D=owned channel/listener token. Outputs1/0,C0
; or typed error. Clobbers X,Y,U; stack<=12, bounded metadata probes.
object_ready:
    pshs d
    jsr handle_lookup
    bcs or_error
    lda H_LIVE,x
    cmpa #OBJ_LISTENER
    beq or_listener
    cmpa #OBJ_REQUEST
    beq or_request
    puls d
    jmp channel_ready
or_request:
    puls d
    jmp io_ready
or_listener:
    ldb H_FRAME,x
    lda #32
    mul
    ldy #CHANNEL_TABLE
    leay d,y
    ldd #0
    tst C_MESSAGES,y
    beq or_done
    incb
or_done:
    leas 2,s
    andcc #$FE
    rts
or_error:
    leas 2,s
    rts

; Function: wait_any. Inputs params list pointer,count1..8,reserved0,absolute
; deadline u32(0 infinite). Outputs readiness mask or blocks, ETIMEDOUT/C1.
; Clobbers all; copies identities before arming, no borrowed list/payload retained.
wait_any:
    lda PARAM_BUFFER+2
    beq wa_invalid
    cmpa #8
    bhi wa_invalid
    tst PARAM_BUFFER+3
    bne wa_invalid
    ldu CURRENT_PROC
    sta P_WAIT_COUNT,u
    clrb
    tfr a,b
    lslb
    clra
    ldx PARAM_BUFFER
    leay P_WAIT_HANDLES,u
    jsr copy_in
    bcs wa_return
    ldu CURRENT_PROC
    ldq PARAM_BUFFER+4
    stq P_WAKE,u
    jsr wait_check
    bcs wa_return
    tstd
    bne wa_return
    jsr wait_expired
    bcs wa_timeout
    ldu CURRENT_PROC
    lda #2
    sta P_FLAGS,u
    lda #PS_WAIT
    sta P_STATE,u
    jmp rx_yield
wa_return:
    rts
wa_invalid:
    jmp rx_invalid
wa_timeout:
    ldd #SYS_ETIMEDOUT
    orcc #1
    rts

; Function: wait_check. Inputs U=PCB. Outputs D=ready bitmap,C0 or identity error.
; Clobbers X,Y,U; CURRENT_PID temporarily changed to waiter's owner then restored.
; Stack<=24; <=8 identities. Serialized with close/publication/wake transitions.
wait_check:
    stu WAIT_PROC
    ldd CURRENT_PID
    std WAIT_OWNER
    ldd P_PID,u
    std CURRENT_PID
    clr WAIT_MASK
    clr WAIT_INDEX
    lda #1
    sta WAIT_BIT
wc_next:
    ldu WAIT_PROC
    ldb WAIT_INDEX
    lslb
    leax P_WAIT_HANDLES,u
    ldd b,x
    jsr object_ready
    bcs wc_finish
    tstd
    beq wc_no_bit
    lda WAIT_MASK
    ora WAIT_BIT
    sta WAIT_MASK
wc_no_bit:
    lsl WAIT_BIT
    inc WAIT_INDEX
    ldu WAIT_PROC
    lda WAIT_INDEX
    cmpa P_WAIT_COUNT,u
    blo wc_next
    clra
    ldb WAIT_MASK
    andcc #$FE
wc_finish:
    pshs cc,d
    ldd WAIT_OWNER
    std CURRENT_PID
    ldu WAIT_PROC
    puls cc,d
    rts

; Function: wait_expired. Inputs U=PCB,TICKS. Outputs C1 expired/C0 infinite/future.
; Clobbers D,W; <=2 stack; modular deadlines must be within2^31 ticks.
wait_expired:
    ldq P_WAKE,u
    tstd
    bne we_check
    cmpw #0
    bne we_check
    andcc #$FE
    rts
we_check:
    ldq TICKS
    subw P_WAKE+2,u
    sbcb P_WAKE+1,u
    sbca P_WAKE,u
    bita #$80
    beq we_expired
    andcc #$FE
    rts
we_expired:
    orcc #1
    rts

; Function: ipc_wake. Inputs waiting PCBs. Outputs ready/wait result atomically.
; Clobbers all; stack<=32; <=8*8 probes. Called outside payload/map transactions.
IPC_WAKE_PENDING equ $C5BD       ; readiness changed since last outer wake pass
ipc_wake:
    lda IPC_WAKE_PENDING
    clr IPC_WAKE_PENDING
    pshs a
    ldu #PROC_TABLE
iw_scan:
    lda P_STATE,u
    cmpa #PS_WAIT
    bne iw_next
    lda P_FLAGS,u
    cmpa #2
    bne iw_next
    pshs u
    tst 2,s
    beq iw_deadline
    jsr wait_check
    bcs iw_ready_error
    tstd
    bne iw_ready
iw_deadline:
    jsr wait_expired
    bcc iw_restore
    ldd #SYS_ETIMEDOUT
    orcc #1
iw_ready_error:
    pshs d
    lda P_CONTEXT+N_CC,u
    ora #1
    sta P_CONTEXT+N_CC,u
    puls d
    bra iw_store
iw_ready:
    pshs d
    lda P_CONTEXT+N_CC,u
    anda #$FE
    sta P_CONTEXT+N_CC,u
    puls d
iw_store:
    std P_CONTEXT+N_A,u
    lda #PS_READY
    sta P_STATE,u
iw_restore:
    puls u
iw_next:
    leau PROC_SIZE,u
    cmpu #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo iw_scan
    leas 1,s
    rts
