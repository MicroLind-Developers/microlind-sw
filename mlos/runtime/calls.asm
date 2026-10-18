; Extended syscall defaults: serialized privileged core/DP0; U=entry record.
; Each exact parameter size is copied through the recorded application map.
; Blocking changes PCB state; only runtime_finish may switch process context.

; Function: runtime_dispatch. Inputs U=native record. Outputs D/C; clobbers all
; scratch. Stack<=96; parameters/pointers never survive in common scratch.
runtime_dispatch:
    pshs u
    ldb N_A,u
    subb #9
    cmpb #36
    bhi rx_unknown
    ldx #rx_sizes
    ldb b,x
    clra
    ldx N_X,u
    ldy #PARAM_BUFFER
    jsr copy_in
    bcs rx_return
    ldu ,s
    ldb N_A,u
    subb #9
    lslb
    ldx #rx_table
    jsr [b,x]
rx_return:
    puls u,pc
rx_unknown:
    ldd #SYS_ENOSYS
    orcc #1
    bra rx_return
rx_sizes:
    include "runtime_params.inc"
rx_table:
    fdb rx_yield,rx_ticks,rx_sleep,rx_exit,rx_wait,rx_spawn,rx_pid,rx_proc,rx_kill,rx_heap_alloc,rx_heap_free
    fdb channel_create,channel_send,channel_receive,object_close,wait_any,service_listen,service_connect,service_accept,rx_ready
    fdb device_claim,io_submit,io_collect,rx_io_cancel
    fdb tty_standard,tty_getc,tty_control,tty_log,filesystem_register,namespace_cwd,endpoint_peer,module_load,module_bind,filesystem_state,tty_drain,filesystem_publish,tty_wait

; Function: rx_yield. Inputs none. Outputs0/C0 and pending dispatch. Clobbers D.
rx_yield:
    inc SCHED_PENDING
    ldd #0
    andcc #$FE
    rts
; Function: rx_ticks. Inputs params destination word. Outputs BE u32 snapshot.
; Clobbers D,X,Y,U; errors/copy semantics as copy_out; stack<=24.
rx_ticks:
    ldq TICKS
    stq COPY_BUFFER
    ldy #COPY_BUFFER
    ldx PARAM_BUFFER
    ldd #4
    jmp copy_out
; Function: rx_sleep. Inputs params delta u32 ticks<=0x7fffffff. Outputs0/C0;
; sleeps to modular deadline, zero yields. Clobbers D,W,X; stack4, no busy poll.
rx_sleep:
    ldq PARAM_BUFFER
    bita #$80
    bne rx_invalid
    ldx CURRENT_PROC
    addw TICKS+2
    adcb TICKS+1
    adca TICKS
    stq P_WAKE,x
    lda #PS_SLEEP
    sta P_STATE,x
    bra rx_yield
; Function: rx_exit. Inputs exit word. Outputs no application resume; clobbers all.
rx_exit:
    clra
    ldb PARAM_BUFFER+1
    jmp process_exit
; Function: rx_wait. Inputs child PID word. Outputs exit word or blocks; only
; parent may reap; stale identity fails. Clobbers D,X,Y,U; stack<=12.
rx_wait:
    ldd PARAM_BUFFER
    jsr process_lookup
    bcs rx_done
    ldd P_PARENT,u
    cmpd CURRENT_PID
    bne rx_owner
    lda P_STATE,u
    cmpa #PS_ZOMBIE
    bne rx_wait_block
    ldd P_EXIT,u
    clr P_STATE,u
    andcc #$FE
    rts
rx_wait_block:
    ldx CURRENT_PROC
    ldd PARAM_BUFFER
    std P_PENDING,x
    lda #1
    sta P_FLAGS,x
    lda #PS_WAIT
    sta P_STATE,x
    bra rx_yield
; Function: rx_spawn. Inputs name pointer,class byte,argc byte,argv word,flagsword.
; Outputs child PID/C0 or error. Copies bounded name before loader maps change.
; Clobbers all; stack<96; publication/rollback follows process_spawn.
rx_spawn:
    tst LOADER_ACTIVE
    lbne cio_again
    ldd PARAM_BUFFER+6
    cmpd #1
    lbhi rx_invalid
    std LOADER_FLAGS
    pshs d
    jsr arguments_copy
    bcs rx_spawn_error
    ldx PARAM_BUFFER
    ldy #LOADER_NAME
    ldb #48
rx_name:
    pshs b,x,y
    ldd #1
    jsr copy_in
    puls b,x,y
    bcs rx_spawn_error
    tst ,y+
    beq rx_name_done
    leax 1,x
    decb
    bne rx_name
    ldd #SYS_ENAMETOOLONG
    orcc #1
    bra rx_spawn_error
rx_name_done:
    ldx #LOADER_NAME
    ldb PARAM_BUFFER+2
    lda #1
    sta LOADER_MODE
    jsr process_spawn
    bcs rx_spawn_error
    tst LOADER_ACTIVE
    bne rx_spawn_return
    tst 1,s
    beq rx_spawn_return
    ldu LOADER_PROC
    lda #PS_SUSPENDED
    sta P_STATE,u
    ldd P_PID,u
rx_spawn_return:
    leas 2,s
    andcc #$FE
    rts
rx_spawn_error:
    clr LOADER_MODE
    leas 2,s
    orcc #1
    rts
; Function: rx_pid. Inputs none. Outputs current unique PID/C0; clobbers D,CC.
rx_pid:
    ldd CURRENT_PID
    andcc #$FE
    rts
; Function: rx_proc. Inputs output pointer; outputs eight 8-byte records:
; PID,parent,state,class,owned-frame-count,reserved. Clobbers all; stack<=24.
rx_proc:
    ldx #PROC_TABLE
    ldy #COPY_BUFFER
rx_proc_loop:
    ldd P_PID,x
    std ,y++
    ldd P_PARENT,x
    std ,y++
    lda P_STATE,x
    sta ,y+
    lda P_CLASS,x
    sta ,y+
    ldu P_PID,x
    pshs x
    ldx #FRAME_TABLE+3*FRAME_RECORD_SIZE
    clr SCHED_TEMP+15
rx_proc_frames:
    tfr u,d
    cmpd F_OWNER,x
    bne rx_proc_frame_next
    inc SCHED_TEMP+15
rx_proc_frame_next:
    leax FRAME_RECORD_SIZE,x
    cmpx #FRAME_TABLE+FRAME_COUNT*FRAME_RECORD_SIZE
    blo rx_proc_frames
    puls x
    lda SCHED_TEMP+15
    sta ,y+
    clr ,y+
    leax PROC_SIZE,x
    cmpx #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo rx_proc_loop
    ldx PARAM_BUFFER
    ldy #COPY_BUFFER
    ldd #PROC_COUNT*8
    jmp copy_out
; Function: rx_kill. Inputs own child PID. Outputs0/C0 after bounded cleanup;
; root PID1 protected. Clobbers all. Other sessions/parents return EOWNER.
rx_kill:
    ldd PARAM_BUFFER
    cmpd #1
    beq rx_owner
    jsr process_lookup
    bcs rx_done
    ldd P_PARENT,u
    cmpd CURRENT_PID
    bne rx_owner
    ldd CURRENT_PID
    pshs d
    ldd CURRENT_PROC
    pshs d
    stu CURRENT_PROC
    ldd P_PID,u
    std CURRENT_PID
    ldd #130
    jsr process_exit
    puls d
    std CURRENT_PROC
    puls d
    std CURRENT_PID
    ldd #0
    andcc #$FE
    rts
rx_heap_alloc:
    ldd PARAM_BUFFER
    jmp heap_alloc
rx_heap_free:
    ldd PARAM_BUFFER
    jmp heap_free
rx_unknown_op:
    ldd #SYS_ENOSYS
    orcc #1
rx_done:
    rts
rx_owner:
    ldd #SYS_EOWNER
    orcc #1
    rts
rx_invalid:
    ldd #SYS_EINVAL
    orcc #1
    rts

; Function: object_close / rx_ready. Inputs token parameter. Outputs D/C; typed
; dispatch prevents a channel token from naming a physical bank. Clobbers all.
object_close:
    ldd PARAM_BUFFER
    jsr handle_lookup
    bcs rx_done
    lda H_LIVE,x
    cmpa #OBJ_BANK
    beq oc_bank
    cmpa #OBJ_LISTENER
    beq oc_listener
    cmpa #OBJ_DEVICE
    beq oc_device
    cmpa #OBJ_REQUEST
    beq oc_request
    ldd PARAM_BUFFER
    jmp channel_close
oc_bank:
    ldd PARAM_BUFFER
    jmp bank_free
oc_device:
    ldd PARAM_BUFFER
    jmp device_close
oc_request:
    ldd PARAM_BUFFER
    jmp io_release
oc_listener:
    ldd PARAM_BUFFER
    jmp service_close
rx_ready:
    ldd PARAM_BUFFER
    jmp object_ready

; Function: rx_io_cancel. Inputs copied request token. Outputs0/C/error. Clobbers all.
rx_io_cancel:
    ldd PARAM_BUFFER
    jmp io_cancel
