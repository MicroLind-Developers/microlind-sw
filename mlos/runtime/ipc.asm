; IPC defaults: native privileged core, IRQ/FIRQ masked, common metadata.
; One16KiB OS-owned frame per channel, explicitly charged to frame admission.
; Message header ring16*u16 occupies32 bytes; admitted capacity counts payload.
; Kernel does copied nonblocking I/O; SDK blocking adapters wait and retry.

; Function: object_alloc. Inputs A=kind,B=object index,CURRENT_PID owner.
; Outputs D=nonwrapping generation/slot token,C0 or ENOMEM/C1. Clobbers X,Y.
; Stack<=6, <=32 probes. No payload allocation or publication beyond this handle.
object_alloc:
    sta OBJ_KIND
    stb OBJ_INDEX
    ldx #HANDLE_TABLE
    ldb #1
oa_scan:
    tst H_LIVE,x
    bne oa_next
    tst H_RETIRED,x
    bne oa_next
    lda H_GEN,x
    cmpa #$FF
    beq oa_retire
    inca
    sta H_GEN,x
    pshs d
    ldd CURRENT_PID
    std H_OWNER,x
    lda OBJ_INDEX
    sta H_FRAME,x
    lda OBJ_KIND
    sta H_LIVE,x
    clr H_REFS,x
    clr H_PINS,x
    puls d
    andcc #$FE
    rts
oa_retire:
    inc H_RETIRED,x
oa_next:
    leax HANDLE_RECORD_SIZE,x
    incb
    cmpb #HANDLE_COUNT
    bls oa_scan
    jmp ps_no_memory

; Function: channel_lookup. Inputs D=endpoint; outputs X=handle,Y=channel,C0
; or typed identity/owner error. Clobbers D,U; stack<=6; physical banks stay opaque.
channel_lookup:
    jsr handle_lookup
    bcs cl_return
    lda H_LIVE,x
    cmpa #OBJ_TX
    beq cl_kind
    cmpa #OBJ_RX
    bne cl_bad
cl_kind:
    ldb H_FRAME,x
    cmpb #CHANNEL_COUNT
    bhs cl_bad
    lda #CHANNEL_SIZE
    mul
    ldy #CHANNEL_TABLE
    leay d,y
    tst C_STATE,y
    beq cl_stale
    ldd LOOKUP_TOKEN
    andcc #$FE
cl_return:
    rts
cl_bad:
    ldd #SYS_EHANDLE
    orcc #1
    rts
cl_stale:
    ldd #SYS_ESTALE
    orcc #1
    rts

; Function: channel_create. Inputs copied params consumerPID,capacity,mode,resv,out.
; Outputs D=TX token; out gets RX token for the designated consumer. All handles,
; frame and output validation admitted before publishing; failure unwinds.
; Clobbers all; stack<=40; capacity1..16352, mode stream0/message1.
channel_create:
    clr IPC_INTERNAL
    bra cc_start
channel_new:
    lda #1
    sta IPC_INTERNAL
cc_start:
    ldd PARAM_BUFFER
    tst IPC_INTERNAL
    beq cc_normal_consumer
    cmpd #$FFFE
    beq cc_known_consumer
cc_normal_consumer:
    jsr process_lookup
    lbcs cc_return
cc_known_consumer:
    std IPC_CONSUMER
    ldd PARAM_BUFFER+2
    lbeq rx_invalid
    cmpd #16352
    lbhi rx_invalid
    lda PARAM_BUFFER+4
    cmpa #1
    lbhi rx_invalid
    tst PARAM_BUFFER+5
    lbne rx_invalid
    tst IPC_INTERNAL
    bne cc_valid_output
    ldx PARAM_BUFFER+6
    ldd #2
    jsr user_range
    lbcs cc_return
cc_valid_output:
    ldy #CHANNEL_TABLE
    clrb
cc_slot:
    tst C_STATE,y
    beq cc_slot_found
    leay CHANNEL_SIZE,y
    incb
    cmpb #CHANNEL_COUNT
    blo cc_slot
    jmp ps_no_memory
cc_slot_found:
    sty IPC_SLOT
    pshs b
    ldb #1
    jsr frame_alloc_many
    puls b
    lbcs cc_return
    lda #OBJ_TX
    jsr object_alloc
    bcs cc_undo_frame
    std IPC_TX
    ldd CURRENT_PID
    std IPC_PARENT
    ldd IPC_CONSUMER
    std CURRENT_PID
    ldy IPC_SLOT
    tfr y,d
    subd #CHANNEL_TABLE
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    lda #OBJ_RX
    jsr object_alloc
    pshs cc,d
    ldd IPC_PARENT
    std CURRENT_PID
    puls cc,d
    bcs cc_undo_tx
    std IPC_RX
    ldy IPC_SLOT
    lda ALLOC_LIST
    sta C_FRAME,y
    jsr frame_address
    ldd #$FFFE
    std F_OWNER,x                 ; queued data outlives the producing process.
    ldd CURRENT_PID
    std C_PRODUCER,y
    ldd IPC_CONSUMER
    std C_CONSUMER,y
    ldd PARAM_BUFFER+2
    std C_CAPACITY,y
    lda PARAM_BUFFER+4
    sta C_MODE,y
    ldd IPC_TX
    std C_TX,y
    ldd IPC_RX
    std C_RX,y
    ldd #0
    std C_USED,y
    std C_READ,y
    std C_WRITE,y
    clr C_MESSAGES,y
    clr C_MSG_READ,y
    clr C_MSG_WRITE,y
    clr C_FLAGS,y
    clr C_MATE,y
    clr C_LISTENER,y
    clr C_LISTENER+1,y
    lda #1
    sta C_STATE,y
    tst IPC_INTERNAL
    bne cc_no_output
    ldd IPC_RX
    std COPY_BUFFER
    ldx PARAM_BUFFER+6
    ldy #COPY_BUFFER
    ldd #2
    jsr copy_out
    ; Output range was prevalidated; mappings/owner cannot change in transaction.
cc_no_output:
    ldd IPC_TX
    andcc #$FE
cc_return:
    rts
cc_undo_tx:
    ldd IPC_TX
    jsr handle_lookup
    clr H_LIVE,x
cc_undo_frame:
    lda ALLOC_LIST
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
    jmp ps_no_memory

; Function: channel_send / channel_receive. Inputs params endpoint,buffer,count,
; flags(0),required-size pointer(0 optional). Outputs actual count/C0, EAGAIN
; when unavailable, EPIPE closed reader, EMSGSIZE atomic-message rejection.
; Clobbers all; stack<=40; <=512-byte copied operation, no retained user pointer.
channel_send:
    lda #1
    sta IPC_DIRECTION
    bra channel_io
channel_receive:
    clr IPC_DIRECTION
channel_io:
    ldd PARAM_BUFFER
    jsr channel_lookup
    lbcs cio_return
    sty IPC_SLOT
    lda H_LIVE,x
    tst IPC_DIRECTION
    beq cio_rx_kind
    cmpa #OBJ_TX
    lbne cl_bad
    bra cio_kind_ok
cio_rx_kind:
    cmpa #OBJ_RX
    lbne cl_bad
cio_kind_ok:
    ldd PARAM_BUFFER+6
    lbne rx_invalid
    ldd PARAM_BUFFER+4
    cmpd #512
    lbhi cio_size
    std IPC_LENGTH
    beq cio_zero
    ldd PARAM_BUFFER+2
    std IPC_USER
    ldd PARAM_BUFFER+8
    std IPC_REQUIRED
    beq cio_no_required
    tfr d,x
    ldd #2
    jsr user_range
    lbcs cio_return
cio_no_required:
    ldy IPC_SLOT
    tst IPC_DIRECTION
    beq cio_read
    ldd C_CONSUMER,y
    lbeq cio_pipe
    tst C_MODE,y
    beq cio_stream_write
    ldd IPC_LENGTH
    cmpd C_CAPACITY,y
    lbhi cio_size
    lda C_MESSAGES,y
    cmpa #16
    lbhs cio_again
    ldd C_CAPACITY,y
    subd C_USED,y
    cmpd IPC_LENGTH
    lblo cio_again
    bra cio_write_ready
cio_stream_write:
    ldd C_CAPACITY,y
    subd C_USED,y
    beq cio_again
    cmpd IPC_LENGTH
    bhs cio_write_ready
    std IPC_LENGTH
cio_write_ready:
    ldd C_WRITE,y
    std IPC_POS
    bra cio_validate
cio_read:
    tst C_MODE,y
    beq cio_stream_read
    tst C_MESSAGES,y
    beq cio_empty
    lda MMU2
    sta IPC_SAVED_MAP
    lda C_FRAME,y
    sta MMU2
    ldb C_MSG_READ,y
    lslb
    ldx #$8000
    ldd b,x
    pshs d
    lda IPC_SAVED_MAP
    sta MMU2
    puls d
    cmpd IPC_LENGTH
    bhi cio_message_small
    std IPC_LENGTH
    bra cio_read_ready
cio_stream_read:
    ldd C_USED,y
    beq cio_empty
    cmpd IPC_LENGTH
    bhs cio_read_ready
    std IPC_LENGTH
cio_read_ready:
    ldd C_READ,y
    std IPC_POS
cio_validate:
    ldx IPC_USER
    ldd IPC_LENGTH
    jsr user_range
    bcs cio_return
    jsr channel_transfer
    bcs cio_return
    ldy IPC_SLOT
    tst IPC_DIRECTION
    beq cio_commit_read
    ldd C_USED,y
    addd IPC_LENGTH
    std C_USED,y
    ldd IPC_POS
    std C_WRITE,y
    tst C_MODE,y
    beq cio_success
    lda MMU2
    sta IPC_SAVED_MAP
    lda C_FRAME,y
    sta MMU2
    ldb C_MSG_WRITE,y
    lslb
    ldx #$8000
    ; Recompute header address independently of D's low byte.
    ldb C_MSG_WRITE,y
    lslb
    abx
    ldd IPC_LENGTH
    std ,x
    lda IPC_SAVED_MAP
    sta MMU2
    inc C_MSG_WRITE,y
    lda C_MSG_WRITE,y
    anda #15
    sta C_MSG_WRITE,y
    inc C_MESSAGES,y
    bra cio_success
cio_commit_read:
    ldd C_USED,y
    subd IPC_LENGTH
    std C_USED,y
    ldd IPC_POS
    std C_READ,y
    tst C_MODE,y
    beq cio_success
    dec C_MESSAGES,y
    inc C_MSG_READ,y
    lda C_MSG_READ,y
    anda #15
    sta C_MSG_READ,y
cio_success:
    lda #1
    sta IPC_WAKE_PENDING
    lda C_FLAGS,y
    cmpa #2
    bne cio_reclaim
    lda #1
    sta T_OUTPUT_PENDING
cio_reclaim:
    jsr channel_reclaim
    ldd IPC_LENGTH
    andcc #$FE
cio_return:
    rts
cio_empty:
    ldd C_PRODUCER,y
    bne cio_again
    ldd #0                       ; EOF after draining, no timeout.
    andcc #$FE
    rts
cio_message_small:
    std IPC_REMAIN
    ldx IPC_REQUIRED
    beq cio_size
    std COPY_BUFFER
    ldy #COPY_BUFFER
    ldd #2
    jsr copy_out
cio_size:
    ldd #SYS_EMSGSIZE
    orcc #1
    rts
cio_zero:
    ldd #0
    andcc #$FE
    rts
cio_again:
    ldd #SYS_EAGAIN
    orcc #1
    rts
cio_pipe:
    ldd #SYS_EPIPE
    orcc #1
    rts

; Function: channel_transfer. Inputs validated user range, IPC metadata/direction.
; Outputs advances local ring position only, C0; caller commits counts atomically.
; Clobbers all; restores MMU2; <=2*256-byte user copies and at most4 contiguous ring spans (TFM), split at wrap.
channel_transfer:
    lda MMU2
    sta IPC_SAVED_MAP
    ldd IPC_LENGTH
    std IPC_REMAIN
    beq ct_done
ct_chunk:
    ldd IPC_REMAIN
    cmpd #256
    bls ct_size
    ldd #256
ct_size:
    std IPC_CHUNK
    tst IPC_DIRECTION
    beq ct_read_ring
    ldx IPC_USER
    ldy #COPY_BUFFER
    jsr copy_in
ct_read_ring:
    ldy IPC_SLOT
    lda C_FRAME,y
    sta MMU2
    ldd IPC_POS
    ldx IPC_SLOT
    tst C_MODE,x
    beq ct_ring_base
    addd #32
ct_ring_base:
    addd #$8000
    tfr d,y
    ldx #COPY_BUFFER
    ldu IPC_SLOT
    ldd C_CAPACITY,u
    subd IPC_POS
    cmpd IPC_CHUNK
    bls ct_span
    ldd IPC_CHUNK
ct_span:
    ; Save the first span length; W and pointers advance across each TFM.
    pshs d
    tfr d,w
    tst IPC_DIRECTION
    beq ct_read_span
    tfm x+,y+
    bra ct_wrap
ct_read_span:
    tfm y+,x+
ct_wrap:
    ldd IPC_POS
    addd ,s
    cmpd C_CAPACITY,u
    blo ct_position
    ldd #0
ct_position:
    std IPC_POS
    ldd IPC_CHUNK
    subd ,s++
    beq ct_copied
    pshs d
    tfr d,w
    ldy #$8000
    tst C_MODE,u
    beq ct_wrap_base
    leay 32,y
ct_wrap_base:
    tst IPC_DIRECTION
    beq ct_read_wrap
    tfm x+,y+
    bra ct_wrap_done
ct_read_wrap:
    tfm y+,x+
ct_wrap_done:
    puls d
    std IPC_POS
ct_copied:
    tst IPC_DIRECTION
    bne ct_advance
    ldx IPC_USER
    ldy #COPY_BUFFER
    ldd IPC_CHUNK
    jsr copy_out
ct_advance:
    ldd IPC_USER
    addd IPC_CHUNK
    std IPC_USER
    ldd IPC_REMAIN
    subd IPC_CHUNK
    std IPC_REMAIN
    bne ct_chunk
ct_done:
    lda IPC_SAVED_MAP
    sta MMU2
    ldd #0
    andcc #$FE
    rts

; Function: channel_close. Inputs D=endpoint token; outputs0/C0 or error.
; Clobbers all; stack<=16. Producer death retains unread data indefinitely;
; consumer close discards unread payload and wakes writer with EPIPE readiness.
channel_close:
    jsr channel_lookup
    bcs cclose_return
    lda #1
    sta T_OUTPUT_PENDING
    sta IPC_WAKE_PENDING
    tst H_REFS,x
    lbne mem_busy
    tst H_PINS,x
    lbne mem_busy
    lda H_LIVE,x
    clr H_LIVE,x
    cmpa #OBJ_TX
    bne cclose_consumer
    ldd #0
    std C_PRODUCER,y
    lda #2
    sta C_STATE,y
    bra cclose_check
cclose_consumer:
    ldd #0
    std C_CONSUMER,y
    std C_USED,y
    clr C_MESSAGES,y
    lda #3
    sta C_STATE,y
channel_reclaim:
cclose_check:
    ldd C_CONSUMER,y
    beq cclose_release
    ldd C_USED,y
    bne cclose_keep
    tst C_MESSAGES,y
    bne cclose_keep
    ldd C_PRODUCER,y
    bne cclose_keep
cclose_release:
    lda C_FRAME,y
    cmpa #3
    blo cclose_final
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
    lda #2
    sta C_FRAME,y
cclose_final:
    ldd C_CONSUMER,y
    bne cclose_keep
    ldd C_PRODUCER,y
    bne cclose_keep
    clr C_STATE,y
cclose_keep:
    ldd #0
    andcc #$FE
cclose_return:
    rts

; Function: channel_ready. Inputs D=owned endpoint. Outputs D=1/0,C0 or error.
; Clobbers X,Y,U. Stack<=8; level-triggered readiness includes peer closure.
channel_ready:
    jsr channel_lookup
    bcs cclose_return
    lda H_LIVE,x
    cmpa #OBJ_TX
    beq cr_write
    tst C_MODE,y
    beq cr_stream
    tst C_MESSAGES,y
    bne cr_yes
    bra cr_peer
cr_stream:
    ldd C_USED,y
    bne cr_yes
cr_peer:
    ldd C_PRODUCER,y
    beq cr_yes
    bra cr_no
cr_write:
    ldd C_CONSUMER,y
    beq cr_yes
    tst C_MODE,y
    beq cr_space
    lda C_MESSAGES,y
    cmpa #16
    bhs cr_no
cr_space:
    ldd C_USED,y
    cmpd C_CAPACITY,y
    blo cr_yes
cr_no:
    ldd #0
    andcc #$FE
    rts
cr_yes:
    ldd #1
    andcc #$FE
    rts
