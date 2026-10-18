; Named service defaults: core/DP0/privileged, IRQ/FIRQ masked. Names1..6 bytes,
; max4 pending clients per listener, message channels512 bytes by default.
; Every connect admits2 payload frames and4 endpoint handles transactionally.

; Function: service_copy_name. Inputs X=application string. Outputs SERVICE_NAME,
; C0 or EFAULT/ENAMETOOLONG/C1. Clobbers all; stack<=32; <=7 one-byte copies.
service_copy_name:
    ldy #SERVICE_NAME
    ldb #7
sn_copy:
    pshs b,x,y
    ldd #1
    jsr copy_in
    puls b,x,y
    bcs sn_return
    tst ,y+
    beq sn_good
    leax 1,x
    decb
    bne sn_copy
    ldd #SYS_ENAMETOOLONG
    orcc #1
sn_return:
    rts
sn_good:
    tst SERVICE_NAME
    lbeq rx_invalid
    andcc #$FE
    rts

; Function: service_find. Inputs SERVICE_NAME. Outputs Y=listener/C0 or ENOENT/C1.
; Clobbers D,X,U. Stack<=4; <=16*7 bytes, no allocation.
service_find:
    ldy #CHANNEL_TABLE
sf_slot:
    tst C_STATE,y
    beq sf_next
    lda C_MODE,y
    cmpa #2
    bne sf_next
    ldx #SERVICE_NAME
    leau C_NAME,y
    ldb #7
sf_name:
    lda ,x+
    cmpa ,u+
    bne sf_next
    tsta
    beq sf_found
    decb
    bne sf_name
sf_next:
    leay CHANNEL_SIZE,y
    cmpy #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo sf_slot
    ldd #SYS_ENOENT
    orcc #1
    rts
sf_found:
    andcc #$FE
    rts

; Function: service_listen. Inputs params nameptr. Outputs listener token/C0;
; EEXIST/ENOMEM/C1 with no listener publication. Clobbers all; stack<=32.
service_listen:
    ldx PARAM_BUFFER
    jsr service_copy_name
    bcs sl_return
    jsr service_find
    bcs sl_new
    ldd #SYS_EEXIST
    orcc #1
    rts
sl_new:
    ldy #CHANNEL_TABLE
    clrb
sl_slot:
    tst C_STATE,y
    beq sl_admit
    leay CHANNEL_SIZE,y
    incb
    cmpb #CHANNEL_COUNT
    blo sl_slot
    jmp ps_no_memory
sl_admit:
    sty SERVICE_LISTENER
    lda #OBJ_LISTENER
    jsr object_alloc
    bcs sl_return
    std SERVICE_TOKEN
    ldy SERVICE_LISTENER
    std C_TX,y
    ldd CURRENT_PID
    std C_PRODUCER,y
    lda #2
    sta C_MODE,y
    sta C_FRAME,y
    clr C_MESSAGES,y
    leay C_NAME,y
    ldx #SERVICE_NAME
    ldw #7
    tfm x+,y+
    ldy SERVICE_LISTENER
    lda #1
    sta C_STATE,y
    ldd SERVICE_TOKEN
    andcc #$FE
sl_return:
    rts

; Function: service_connect. Inputs params nameptr,outptr(4 bytes),capacity word,
; mode byte,reserved0. Outputs0/C0 and client TX/RX. No auto-reconnect semantics.
; Clobbers all; stack<=48; fully rolls back if either channel/handle admission fails.
service_connect:
    ldd PARAM_BUFFER+6
    lbne rx_invalid
    ldx PARAM_BUFFER+2
    stx SERVICE_OUTPUT
    ldd #4
    jsr user_range
    lbcs scn_return
    ldd PARAM_BUFFER+4
    std SERVICE_CAPACITY
    ldx PARAM_BUFFER
    jsr service_copy_name
    lbcs scn_return
    jsr service_find
    lbcs scn_return
    lda C_MESSAGES,y
    cmpa #4
    lbhs cio_again
    sty SERVICE_LISTENER
    ldd C_TX,y
    std SERVICE_TOKEN
    ldd C_PRODUCER,y
    std SERVICE_OWNER
    ldd CURRENT_PID
    std SERVICE_CLIENT
    ldd SERVICE_OWNER
    std PARAM_BUFFER
    ldd SERVICE_CAPACITY
    bne scn_capacity
    ldd #512
scn_capacity:
    std PARAM_BUFFER+2
    lda #1
    sta PARAM_BUFFER+4
    clr PARAM_BUFFER+5
    jsr channel_new
    lbcs scn_return
    std SERVICE_CLIENT_TX
    ldd IPC_RX
    std SERVICE_SERVER_RX
    ldd IPC_SLOT
    std SERVICE_FIRST
    ldd SERVICE_OWNER
    std CURRENT_PID
    ldd SERVICE_CLIENT
    std PARAM_BUFFER
    jsr channel_new
    pshs cc,d
    ldd SERVICE_CLIENT
    std CURRENT_PID
    puls cc,d
    bcs scn_rollback
    std SERVICE_SERVER_TX
    ldd IPC_RX
    std SERVICE_CLIENT_RX
    ldd IPC_SLOT
    std SERVICE_SECOND
    ldy SERVICE_FIRST
    lda #1
    sta C_FLAGS,y
    ldd SERVICE_TOKEN
    std C_LISTENER,y
    ldd SERVICE_SECOND
    subd #CHANNEL_TABLE
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    stb C_MATE,y
    ldy SERVICE_LISTENER
    inc C_MESSAGES,y
    lda #1
    sta IPC_WAKE_PENDING
    ldd SERVICE_CLIENT_TX
    std COPY_BUFFER
    ldd SERVICE_CLIENT_RX
    std COPY_BUFFER+2
    ldx SERVICE_OUTPUT
    ldy #COPY_BUFFER
    ldd #4
    jsr copy_out
    ldd #0
    andcc #$FE
scn_return:
    rts
scn_rollback:
    ldd SERVICE_CLIENT_TX
    jsr channel_close
    ldd SERVICE_OWNER
    std CURRENT_PID
    ldd SERVICE_SERVER_RX
    jsr channel_close
    ldd SERVICE_CLIENT
    std CURRENT_PID
    jmp ps_no_memory

; Function: service_accept. Inputs listener token,outptr. Outputs server TX/RX
; and0/C0 or EAGAIN; clobbers all. Stack<=24; no new allocation at acceptance.
service_accept:
    ldx PARAM_BUFFER+2
    stx SERVICE_OUTPUT
    ldd #4
    jsr user_range
    bcs sa_return
    ldd PARAM_BUFFER
    std SERVICE_TOKEN
    jsr handle_lookup
    bcs sa_return
    lda H_LIVE,x
    cmpa #OBJ_LISTENER
    lbne cl_bad
    ldb H_FRAME,x
    lda #32
    mul
    ldy #CHANNEL_TABLE
    leay d,y
    sty SERVICE_LISTENER
    ldy #CHANNEL_TABLE
sa_scan:
    lda C_FLAGS,y
    cmpa #1
    bne sa_next
    ldd C_LISTENER,y
    cmpd SERVICE_TOKEN
    bne sa_next
    ldd C_RX,y
    std COPY_BUFFER+2
    ldb C_MATE,y
    clr C_FLAGS,y
    lda #32
    mul
    ldx #CHANNEL_TABLE
    leax d,x
    ldd C_TX,x
    std COPY_BUFFER
    ldy SERVICE_LISTENER
    dec C_MESSAGES,y
    ldx SERVICE_OUTPUT
    ldy #COPY_BUFFER
    ldd #4
    jsr copy_out
    ldd #0
    andcc #$FE
sa_return:
    rts
sa_next:
    leay CHANNEL_SIZE,y
    cmpy #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo sa_scan
    jmp cio_again

; Function: service_close. Inputs listener token. Outputs0/C0; clobbers all.
; Withdraw name first, close unaccepted server endpoints; accepted pairs persist
; independently. Fresh listeners receive fresh tokens; stale connections never rebind.
service_close:
    std SERVICE_TOKEN
    jsr handle_lookup
    bcs sa_return
    lda H_LIVE,x
    cmpa #OBJ_LISTENER
    lbne cl_bad
    clr H_LIVE,x
    ldb H_FRAME,x
    lda #32
    mul
    ldy #CHANNEL_TABLE
    leay d,y
    clr C_STATE,y
    ldy #CHANNEL_TABLE
sclose_pending:
    lda C_FLAGS,y
    cmpa #1
    bne sclose_next
    ldd C_LISTENER,y
    cmpd SERVICE_TOKEN
    bne sclose_next
    clr C_FLAGS,y
    ldb C_MATE,y
    pshs b,y
    ldd C_RX,y
    jsr channel_close
    puls b,y
    pshs y
    lda #32
    mul
    ldy #CHANNEL_TABLE
    leay d,y
    ldd C_TX,y
    jsr channel_close
    puls y
sclose_next:
    leay CHANNEL_SIZE,y
    cmpy #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo sclose_pending
    ldd #0
    andcc #$FE
    rts

; Function: ipc_release_owner. Inputs dying CURRENT_PID. Outputs withdraws all
; its channel/listener endpoints, retaining unread producer data for live peers.
; Clobbers all; stack<=48; <=32 handles, no wait or recursive process cleanup.
ipc_release_owner:
    ldy #HANDLE_TABLE
    ldb #1
iro_loop:
    ldd H_OWNER,y
    cmpd CURRENT_PID
    bne iro_next
    lda H_LIVE,y
    cmpa #OBJ_LISTENER
    bhi iro_next
    cmpa #OBJ_TX
    blo iro_next
    tst H_REFS,y
    bne iro_next
    tst H_PINS,y
    bne iro_next
    tfr y,d
    subd #HANDLE_TABLE
    lsrd
    lsrd
    lsrd
    incb
    lda H_GEN,y
    pshs y
    ldb H_LIVE,y
    cmpb #OBJ_LISTENER
    bne iro_endpoint
    tfr y,d
    subd #HANDLE_TABLE
    lsrd
    lsrd
    lsrd
    incb
    lda H_GEN,y
    jsr service_close
    bra iro_restore
iro_endpoint:
    tfr y,d
    subd #HANDLE_TABLE
    lsrd
    lsrd
    lsrd
    incb
    lda H_GEN,y
    jsr channel_close
iro_restore:
    puls y
iro_next:
    leay HANDLE_RECORD_SIZE,y
    cmpy #HANDLE_TABLE+HANDLE_COUNT*HANDLE_RECORD_SIZE
    blo iro_loop
    rts
