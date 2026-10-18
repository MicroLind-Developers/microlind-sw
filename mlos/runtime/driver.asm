; Driver engine defaults: trusted privileged native core/DP0, masked short steps.
; Eight admitted512-byte requests share one pinned OS frame; device instances
; own separate records. Two CF controllers use the same PIO state machine.

; Function: driver_init. Inputs validated boot geometry. Outputs instances0 CF,
; 1 explicitly configured expansion CF, 2/3 deterministic mock adapters.
; Clobbers all; stack<=16. Request buffer charged as one dynamic OS frame.
driver_init:
    ldd #$FFFE
    std CURRENT_PID
    ldb #1
    jsr frame_alloc_many
    bcs di_fail
    lda ALLOC_LIST
    sta REQUEST_FRAME
    ldd #0
    std CURRENT_PID
    ldx #DEVICE_TABLE
    ldb #DEVICE_COUNT
di_instance:
    lda #$FF
    sta D_ACTIVE,x
    clr D_OWNER,x
    clr D_OWNER+1,x
    leax DEVICE_SIZE,x
    decb
    bne di_instance
    ldd #$F418
    std DEVICE_TABLE+D_BASE
    ldd #$F640
    std DEVICE_TABLE+DEVICE_SIZE+D_BASE
    ldq BOOT_SECTORS
    stq DEVICE_TABLE+D_SECTORS
    lda #1
    sta DEVICE_TABLE+D_ONLINE
    sta DEVICE_TABLE+2*DEVICE_SIZE+D_ONLINE
    sta DEVICE_TABLE+3*DEVICE_SIZE+D_ONLINE
    ldd #4096
    std DEVICE_TABLE+2*DEVICE_SIZE+D_SECTORS+2
    std DEVICE_TABLE+3*DEVICE_SIZE+D_SECTORS+2
    ldd #7
    std DEVICE_TABLE+2*DEVICE_SIZE+D_DELAY
    ldd #19
    std DEVICE_TABLE+3*DEVICE_SIZE+D_DELAY
    andcc #$FE
di_fail:
    rts

; Function: device_lookup. Inputs D=owned device handle. Outputs Y=instance,
; X=handle/C0 or typed error. Clobbers D,U. Stack<=6, constant bounded lookup.
device_lookup:
    jsr handle_lookup
    bcs dl_done
    lda H_LIVE,x
    cmpa #OBJ_DEVICE
    lbne cl_bad
    ldb H_FRAME,x
    lda #DEVICE_SIZE
    mul
    ldy #DEVICE_TABLE
    leay d,y
    andcc #$FE
dl_done:
    rts

; Function: device_claim. Inputs params device byte,reserved0. Outputs opaque
; exclusive device handle/C0, BUSY/ENODEV/ENOMEM/C1. Clobbers all; stack<=32.
; ExpansionCF is a simulator/manual binding, not a qualified physical card.
device_claim:
    tst PARAM_BUFFER+1
    lbne rx_invalid
    ldb PARAM_BUFFER
    cmpb #DEVICE_COUNT
    lbhs rx_invalid
    lda #DEVICE_SIZE
    mul
    ldy #DEVICE_TABLE
    leay d,y
    sty IO_DEVICE
    ldd D_OWNER,y
    lbne mem_busy
    tst D_ONLINE,y
    bne dc_admit
    tst LOADER_ACTIVE
    lbne cio_again
    ldx D_BASE,y
    beq dc_no_device
    lda 7,x
    cmpa #$FF
    beq dc_no_device
    lda #$EC
    sta 7,x
    ldu #1024
dc_identify_wait:
    lda 7,x
    bita #$21
    bne dc_no_device
    bita #8
    bne dc_identify_data
    leau -1,u
    bne dc_identify_wait
    bra dc_no_device
dc_identify_data:
    ldy #BOOT_BUFFER
    ldu #512
dc_identify_byte:
    lda ,x
    sta ,y+
    leau -1,u
    bne dc_identify_byte
    ldy IO_DEVICE
    lda BOOT_BUFFER+123
    ldb BOOT_BUFFER+122
    std D_SECTORS,y
    lda BOOT_BUFFER+121
    ldb BOOT_BUFFER+120
    std D_SECTORS+2,y
    ldq D_SECTORS,y
    bita #$F0
    lbne dc_no_device
    tstd
    bne dc_geometry_ok
    cmpw #1
    lblo dc_no_device
dc_geometry_ok:
    lda #1
    sta D_ONLINE,y
dc_admit:
    tst BOOT_FEEDBACK_ACTIVE
    beq dc_feedback_done
    tst PARAM_BUFFER             ; only the boot CF worker's raw-device claim
    bne dc_feedback_done
    ldb #BOOT_MSG_VALIDATE
    jsr ROM_BOOT_STATUS
dc_feedback_done:
    ldb PARAM_BUFFER
    lda #OBJ_DEVICE
    jsr object_alloc
    bcs dl_done
    pshs d
    ldy IO_DEVICE
    ldd CURRENT_PID
    std D_OWNER,y
    puls d
    andcc #$FE
    rts
dc_no_device:
    ldd #SYS_ENODEV
    orcc #1
    rts

; Function: request_lookup. Inputs D=request token. Outputs Y=record,X=handle/C0
; or typed error. Clobbers D,U. Stack<=6; no caller pointers retained.
request_lookup:
    jsr handle_lookup
    bcs rl_done
    lda H_LIVE,x
    cmpa #OBJ_REQUEST
    lbne cl_bad
    ldb H_FRAME,x
    lda #32
    mul
    ldy #REQUEST_TABLE
    leay d,y
    andcc #$FE
rl_done:
    rts

; Function: io_submit. Inputs params devtoken,op byte(0 read/1 write),flags0,
; LBAu32,source pointer,u16count512. Outputs request token/C0 or admission error.
; Copies accepted writes into OS-owned backing before publication. Stack<=48.
io_submit:
    ldd PARAM_BUFFER
    jsr device_lookup
    lbcs ios_return
    sty IO_DEVICE
    tst D_ONLINE,y
    lbeq dc_no_device
    lda PARAM_BUFFER+2
    cmpa #1
    lbhi rx_invalid
    tst PARAM_BUFFER+3
    lbne rx_invalid
    ldd PARAM_BUFFER+10
    cmpd #512
    lbne rx_invalid
    ldq PARAM_BUFFER+4
    cmpd D_SECTORS,y
    lbhi rx_invalid
    blo ios_bounds
    cmpw D_SECTORS+2,y
    lbhs rx_invalid
ios_bounds:
    ldy #REQUEST_TABLE
    clrb
ios_slot:
    tst R_STATE,y
    beq ios_admit
    leay REQUEST_SIZE,y
    incb
    cmpb #REQUEST_COUNT
    blo ios_slot
    jmp ps_no_memory
ios_admit:
    sty IO_CURRENT
    stb IO_INDEX
    lda #OBJ_REQUEST
    jsr object_alloc
    bcs ios_return
    ldy IO_CURRENT
    std R_TOKEN,y
    std IPC_TOKEN
    ldd CURRENT_PID
    std R_OWNER,y
    ldd PARAM_BUFFER
    std R_DEV_TOKEN,y
    jsr handle_lookup
    inc H_REFS,x
    lda H_FRAME,x
    ldy IO_CURRENT
    sta R_DEVICE,y
    lda PARAM_BUFFER+2
    sta R_OP,y
    clr R_CANCEL,y
    ldq PARAM_BUFFER+4
    stq R_LBA,y
    ldd #0
    std R_DONE,y
    std R_RESULT,y
    lda IO_INDEX
    lsla
    clrb
    std R_DATA,y
    ldq TICKS
    addw #1000
    adcb #0
    adca #0
    stq R_DEADLINE,y
    lda REQUEST_FRAME
    jsr frame_address
    inc F_PINS,x
    ; Request-handle pin prevents teardown before in-flight PIO has settled.
    ldd IPC_TOKEN
    jsr handle_lookup
    inc H_PINS,x
    ldy IO_CURRENT
    tst R_OP,y
    beq ios_zero_read
    ldx PARAM_BUFFER+8
    ldd #512
    jsr user_range
    bcs ios_abort
    clr SCHED_TEMP+6
ios_copy_chunk:
    ldx PARAM_BUFFER+8
    tst SCHED_TEMP+6
    beq ios_user_pointer
    leax 256,x
ios_user_pointer:
    ldy #COPY_BUFFER
    ldd #256
    jsr copy_in
    lda MMU2
    sta IO_MAP
    lda REQUEST_FRAME
    sta MMU2
    ldy IO_CURRENT
    ldd R_DATA,y
    addd #$8000
    tst SCHED_TEMP+6
    beq ios_buffer_pointer
    addd #256
ios_buffer_pointer:
    tfr d,y
    ldx #COPY_BUFFER
    ldw #256
    tfm x+,y+
    lda IO_MAP
    sta MMU2
    inc SCHED_TEMP+6
    lda SCHED_TEMP+6
    cmpa #2
    blo ios_copy_chunk
    bra ios_publish
ios_zero_read:
    lda MMU2
    pshs a
    lda REQUEST_FRAME
    sta MMU2
    ldd R_DATA,y
    addd #$8000
    tfr d,y
    clr COPY_BUFFER
    ldx #COPY_BUFFER
    ldw #512
    tfm x,y+
    puls a
    sta MMU2
IO_PENDING equ $C5BA             ; published requests not yet COMPLETE, <=8
ios_publish:
    inc IO_PENDING
    ldy IO_CURRENT
    lda #RQ_QUEUED
    sta R_STATE,y
    ldd R_TOKEN,y
    andcc #$FE
ios_return:
    rts
ios_abort:
    pshs d
    ldy IO_CURRENT
    lda #RQ_COMPLETE
    sta R_STATE,y
    ldd R_TOKEN,y
    jsr io_release
    puls d
    orcc #1
    rts

; Function: io_ready / io_cancel. Inputs D=request token. Outputs readiness or0/C0.
; Cancellation never promises undoing accepted write bytes; PIO drains before reuse.
io_ready:
    jsr request_lookup
    bcs rl_done
    ldd #0
    lda R_STATE,y
    cmpa #RQ_COMPLETE
    bne ior_not_ready
    ldd #1
    andcc #$FE
    rts
ior_not_ready:
    ldd #0
    andcc #$FE
    rts
io_cancel:
    jsr request_lookup
    bcs rl_done
    lda #1
    sta R_CANCEL,y
    ldd #0
    andcc #$FE
    rts

; Function: io_collect. Inputs params request,destination pointer. Outputs512/C0
; or final error/C1; pending returns EAGAIN without consuming. Read result is
; revalidated/copied on collection; invalid destination retains the completion.
; Clobbers all; stack<=48. Collected/cancelled identities never silently resurrect.
io_collect:
    ldd PARAM_BUFFER
    jsr request_lookup
    bcs ioc_return
    sty IO_CURRENT
    lda R_STATE,y
    cmpa #RQ_COMPLETE
    lbne cio_again
    ldd R_RESULT,y
    bne ioc_error
    tst R_OP,y
    bne ioc_success
    ldx PARAM_BUFFER+2
    ldd #512
    jsr user_range
    bcs ioc_return
    clr SCHED_TEMP+6
ioc_copy:
    lda MMU2
    sta IO_MAP
    lda REQUEST_FRAME
    sta MMU2
    ldy IO_CURRENT
    ldd R_DATA,y
    addd #$8000
    tst SCHED_TEMP+6
    beq ioc_buffer
    addd #256
ioc_buffer:
    tfr d,x
    ldy #COPY_BUFFER
    ldw #256
    tfm x+,y+
    lda IO_MAP
    sta MMU2
    ldx PARAM_BUFFER+2
    tst SCHED_TEMP+6
    beq ioc_dest
    leax 256,x
ioc_dest:
    ldy #COPY_BUFFER
    ldd #256
    jsr copy_out
    inc SCHED_TEMP+6
    lda SCHED_TEMP+6
    cmpa #2
    blo ioc_copy
ioc_success:
    ldd PARAM_BUFFER
    jsr io_release
    ldd #512
    andcc #$FE
ioc_return:
    rts
ioc_error:
    pshs d
    ldd PARAM_BUFFER
    jsr io_release
    puls d
    orcc #1
    rts

; Function: io_release. Inputs D=completed request token. Outputs0/C0 or error.
; Clobbers all; <=16 stack; drops device reference and pool pin only after completion.
io_release:
    jsr request_lookup
    bcs ioc_return
    lda R_STATE,y
    cmpa #RQ_COMPLETE
    lbne mem_busy
    clr H_LIVE,x
    clr H_PINS,x
    ldd R_DEV_TOKEN,y
    clr R_STATE,y
    jsr handle_lookup
    bcs iorel_pool
    dec H_REFS,x
iorel_pool:
    lda REQUEST_FRAME
    jsr frame_address
    dec F_PINS,x
    ldd #0
    andcc #$FE
    rts

; Function: driver_progress. Inputs request/instance tables. Outputs at most MLOS_IO_QUOTA
; PIO bytes per controller and bounded phase transitions; clobbers all; stack<=32.
; Called only at outer safe points, allowing unrelated processes/drives to run.
driver_progress:
    tst IO_PENDING
    beq dp_idle
    clr SCHED_TEMP+7
dp_device:
    ldb SCHED_TEMP+7
    lda #DEVICE_SIZE
    mul
    ldy #DEVICE_TABLE
    leay d,y
    sty IO_DEVICE
    lda D_ACTIVE,y
    cmpa #$FF
    bne dp_existing
    ldx #REQUEST_TABLE
    clrb
dp_queue:
    lda R_STATE,x
    cmpa #RQ_QUEUED
    bne dp_queue_next
    lda R_DEVICE,x
    cmpa SCHED_TEMP+7
    beq dp_choose
dp_queue_next:
    leax REQUEST_SIZE,x
    incb
    cmpb #REQUEST_COUNT
    blo dp_queue
    bra dp_next
dp_choose:
    stb D_ACTIVE,y
    stx IO_CURRENT
dp_start:
    tst R_CANCEL,x
    bne dp_cancelled
    tst D_ONLINE,y
    beq dp_failed
    ldd D_BASE,y
    beq dp_mock_start
    tfr d,y
    lda 7,y
    cmpa #$FF
    beq dp_failed
    bita #$80
    bne dp_timeout
    lda #1
    sta 2,y
    ldx IO_CURRENT
    lda R_LBA+3,x
    sta 3,y
    lda R_LBA+2,x
    sta 4,y
    lda R_LBA+1,x
    sta 5,y
    lda R_LBA,x
    ora #$E0
    sta 6,y
    lda R_OP,x
    beq dp_issue_read
    lda #$30
    bra dp_command
dp_issue_read:
    lda #$20
dp_command:
    sta 7,y
    lda #RQ_DRQ
    sta R_STATE,x
    bra dp_next
dp_mock_start:
    ldq TICKS
    ldy IO_DEVICE
    addw D_DELAY,y
    adcb #0
    adca #0
    stq R_DEADLINE,x
    lda #RQ_FINISH
    sta R_STATE,x
    bra dp_next
dp_existing:
    ldb #REQUEST_SIZE
    mul
    ldx #REQUEST_TABLE
    leax d,x
    stx IO_CURRENT
    lda R_STATE,x
    cmpa #RQ_QUEUED
    beq dp_retry_start
    ldy IO_DEVICE
    ldd D_BASE,y
    beq dp_mock
    tfr d,y
    lda 7,y
    cmpa #$FF
    beq dp_failed
    bita #$80
    bne dp_timeout
    bita #$21
    bne dp_failed
    ldx IO_CURRENT
    lda R_STATE,x
    cmpa #RQ_DRQ
    bne dp_data_or_finish
    lda 7,y
    bita #8
    beq dp_timeout
    lda #RQ_DATA
    sta R_STATE,x
    bra dp_next
dp_data_or_finish:
    cmpa #RQ_FINISH
    beq dp_complete
    lda MMU2
    sta IO_MAP
    lda REQUEST_FRAME
    sta MMU2
    ldd R_DATA,x
    addd R_DONE,x
    addd #$8000
    tfr d,u
    ; Native TFM keeps the CF data register fixed. A128-byte chunk takes
    ; fewer CPU cycles than the previous64-byte per-byte dispatch loop.
    ldw #MLOS_IO_QUOTA
    tst R_OP,x
    beq dp_read_bytes
    tfm u+,y
    bra dp_bytes_done
dp_read_bytes:
    tfm y,u+
dp_bytes_done:
    lda IO_MAP
    sta MMU2
    ldd R_DONE,x
    addd #MLOS_IO_QUOTA
    std R_DONE,x
    cmpd #512
    blo dp_next
    lda #RQ_FINISH
    sta R_STATE,x
    bra dp_next
dp_retry_start:
    ldy IO_DEVICE
    bra dp_start
dp_timeout:
    ldq TICKS
    subw R_DEADLINE+2,x
    sbcb R_DEADLINE+1,x
    sbca R_DEADLINE,x
    bita #$80
    bne dp_next
    ldy IO_DEVICE
    lda #1
    sta D_QUARANTINE,y
    bra dp_failed
dp_mock:
    ldy IO_DEVICE
    tst D_MODULE,y
    beq dp_builtin_mock
    ldb #2
    jsr module_callback
    bcc dp_complete
    cmpd #SYS_EAGAIN
    beq dp_next
    bra dp_failed
dp_builtin_mock:
    ldq TICKS
    subw R_DEADLINE+2,x
    sbcb R_DEADLINE+1,x
    sbca R_DEADLINE,x
    bita #$80
    bne dp_next
    bra dp_complete
dp_failed:
    ldy IO_DEVICE
    clr D_ONLINE,y
    ldd #SYS_EIO
    bra dp_finish
dp_cancelled:
    ldd #SYS_ECANCELLED
    bra dp_finish
dp_complete:
    tst R_CANCEL,x
    bne dp_cancelled
    ldd #0
dp_finish:
    pshs d
    lda #1
    sta IPC_WAKE_PENDING
    puls d
    dec IO_PENDING
    ldx IO_CURRENT
    std R_RESULT,x
    lda #RQ_COMPLETE
    sta R_STATE,x
    ldd CURRENT_PID
    pshs d
    ldd R_OWNER,x
    std CURRENT_PID
    ldd R_TOKEN,x
    jsr handle_lookup
    bcs dp_finished_handle
    clr H_PINS,x
dp_finished_handle:
    puls d
    std CURRENT_PID
    ldy IO_DEVICE
    lda #$FF
    sta D_ACTIVE,y
dp_next:
    inc SCHED_TEMP+7
    lda SCHED_TEMP+7
    cmpa #DEVICE_COUNT
    blo dp_device
dp_idle:
    rts

; Function: device_close. Inputs D=device token. Outputs0/C0 or BUSY/C1 until
; requests/callbacks quiesce. Clobbers X,Y,U; stack<=8. Does not unload modules.
device_close:
    jsr device_lookup
    bcs dl_done
    tst H_REFS,x
    lbne mem_busy
    tst H_PINS,x
    lbne mem_busy
    tst D_QUARANTINE,y
    lbne dclose_quarantine
    tst D_MODULE,y
    beq dclose_release
    pshs x,y
    ldx #0
    ldb #4
    jsr module_callback
    puls x,y
    bcs dclose_quarantine
dclose_release:
    clr H_LIVE,x
    ldd #0
    std D_OWNER,y
    ldd D_BASE,y
    beq dclose_ready
    clr D_ONLINE,y
dclose_ready:
    ldd #0
    andcc #$FE
    rts
dclose_quarantine:
    clr H_LIVE,x
    clr D_ONLINE,y
    ldd #$FFFD
    std D_OWNER,y
    ldd #SYS_EIO
    orcc #1
    rts

; Function: driver_release_owner. Inputs dying CURRENT_PID. Outputs cancels its
; requests; completed ones drop buffers/references. Clobbers all; stack<=24.
; In-flight records remain pinned, preventing process/frame/device reuse.
driver_release_owner:
    ldy #REQUEST_TABLE
dro_scan:
    tst R_STATE,y
    beq dro_next
    ldd R_OWNER,y
    cmpd CURRENT_PID
    bne dro_next
    lda #1
    sta R_CANCEL,y
    lda R_STATE,y
    cmpa #RQ_COMPLETE
    bne dro_next
    ldd R_TOKEN,y
    pshs y
    jsr io_release
    puls y
dro_next:
    leay REQUEST_SIZE,y
    cmpy #REQUEST_TABLE+REQUEST_COUNT*REQUEST_SIZE
    blo dro_scan
    ldy #HANDLE_TABLE
dro_devices:
    ldd H_OWNER,y
    cmpd CURRENT_PID
    bne dro_device_next
    lda H_LIVE,y
    cmpa #OBJ_DEVICE
    bne dro_device_next
    tst H_REFS,y
    bne dro_device_next
    tfr y,d
    subd #HANDLE_TABLE
    lsrd
    lsrd
    lsrd
    incb
    lda H_GEN,y
    pshs y
    jsr device_close
    puls y
dro_device_next:
    leay HANDLE_RECORD_SIZE,y
    cmpy #HANDLE_TABLE+HANDLE_COUNT*HANDLE_RECORD_SIZE
    blo dro_devices
    rts
