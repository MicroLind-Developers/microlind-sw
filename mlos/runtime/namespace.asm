FS_OWNER equ $C122
FS_FAILED equ $C124
FS_VOLUME_FLAGS equ $C125
FS_VOLUME_GENERATIONS equ $C126
; Function: filesystem_register. Inputs none. Outputs registers the init-launched
; filesystem frontend, or EBUSY/EOWNER/EIO. Clobbers D,X,U; stack<=4.
filesystem_register:
    tst FS_FAILED
    lbne dc_no_device
    ldd FS_OWNER
    lbne mem_busy
    ldu CURRENT_PROC
    ldd P_PARENT,u
    cmpd #1
    lbne rx_owner
    ldd CURRENT_PID
    std FS_OWNER
    std P_SERVICE,u
    ldd #0
    andcc #$FE
    rts
; Function: namespace_cwd. Inputs pid,opbyte(0 get/1 set),reserved0,pathptr,
; volume,generation. Only FS_OWNER may act for another PID or set validated cwd.
; Get copies volume/generation/path68 bytes; set copies64-byte canonical path.
; Clobbers all; stack<=32. Saved cwd/generation survives parent exit and recovery.
namespace_cwd:
    ldd PARAM_BUFFER
    beq nc_self
    cmpd CURRENT_PID
    beq nc_lookup
    pshs d
    ldd CURRENT_PID
    cmpd FS_OWNER
    puls d
    lbne rx_owner
    bra nc_lookup
nc_self:
    ldd CURRENT_PID
nc_lookup:
    jsr process_lookup
    lbcs rx_done
    stu SCHED_SELECTED
    lda PARAM_BUFFER+2
    beq nc_get
    cmpa #2
    beq nc_virtual
    cmpa #1
    lbne rx_invalid
    ldd CURRENT_PID
    cmpd FS_OWNER
    lbne rx_owner
    ldx PARAM_BUFFER+4
    ldy #COPY_BUFFER
    ldd #64
    jsr copy_in
    lbcs rx_done
    ldu SCHED_SELECTED
    ldx #COPY_BUFFER
    leay P_CWD,u
    ldw #64
    tfm x+,y+
    ldd PARAM_BUFFER+6
    std P_CWD_VOLUME,u
    ldd PARAM_BUFFER+8
    std P_CWD_GENERATION,u
    ldd #0
    andcc #$FE
    rts
nc_virtual:
    ldu SCHED_SELECTED
    ldd P_PID,u
    cmpd CURRENT_PID
    lbne rx_owner
    ldx #nc_proc_path
    leay P_CWD,u
    ldw #6
    tfm x+,y+
    ldd #$FFFF
    std P_CWD_VOLUME,u
    ldd #0
    std P_CWD_GENERATION,u
    andcc #$FE
    rts
nc_proc_path: fcn "/proc"
nc_get:
    ldd P_CWD_VOLUME,u
    std COPY_BUFFER
    ldd P_CWD_GENERATION,u
    std COPY_BUFFER+2
    leax P_CWD,u
    ldy #COPY_BUFFER+4
    ldw #64
    tfm x+,y+
    ldx PARAM_BUFFER+4
    ldy #COPY_BUFFER
    ldd #68
    jmp copy_out
; Function: endpoint_peer. Inputs endpoint token. Outputs peer PID/C0.
; Clobbers X,Y,U; typed owner validation prevents trusting client-supplied identity.
endpoint_peer:
    ldd PARAM_BUFFER
    jsr channel_lookup
    lbcs rx_done
    lda H_LIVE,x
    cmpa #OBJ_RX
    beq ep_producer
    ldd C_CONSUMER,y
    andcc #$FE
    rts
ep_producer:
    ldd C_PRODUCER,y
    andcc #$FE
    rts

; Function: filesystem_state. Inputs destination pointer. Outputs copied
; frontend PID,failedbyte,reserved0 without relying on the filesystem process.
; Clobbers all; stack<=24. /proc snapshot provider uses this independent path.
filesystem_state:
    ldx #FS_OWNER
    ldy #COPY_BUFFER
    ldw #8
    tfm x+,y+
    ldx PARAM_BUFFER
    ldy #COPY_BUFFER
    ldd #8
    jmp copy_out

; Function: filesystem_publish. Inputs volume0/1,online0/1,generation. Outputs
; independent read-only /proc mount cache; only FS_OWNER may update. Clobbers
; D,X,CC; stack<=4. Service death clears online flags before withdrawing workers.
filesystem_publish:
    ldd CURRENT_PID
    cmpd FS_OWNER
    lbne rx_owner
    lda PARAM_BUFFER
    cmpa #1
    lbhi rx_invalid
    lda PARAM_BUFFER+1
    cmpa #1
    lbhi rx_invalid
    ldb PARAM_BUFFER
    lslb
    ldx #FS_VOLUME_GENERATIONS
    abx
    ldd PARAM_BUFFER+2
    std ,x
    lda #1
    tst PARAM_BUFFER
    beq fp_bit
    lsla
fp_bit:
    tst PARAM_BUFFER+1
    beq fp_offline
    ora FS_VOLUME_FLAGS
    bra fp_store
fp_offline:
    coma
    anda FS_VOLUME_FLAGS
fp_store:
    sta FS_VOLUME_FLAGS
    ; Bind bootstrap cwd records to the first actual root-volume generation.
    ; Later recovery never updates an old generation or resurrects a stale cwd.
    tst PARAM_BUFFER
    bne fp_done
    tst PARAM_BUFFER+1
    beq fp_done
    ldu #PROC_TABLE
fp_cwd:
    tst P_STATE,u
    beq fp_next
    ldd P_CWD_VOLUME,u
    bne fp_next
    ldd P_CWD_GENERATION,u
    bne fp_next
    ldd PARAM_BUFFER+2
    std P_CWD_GENERATION,u
fp_next:
    leau PROC_SIZE,u
    cmpu #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo fp_cwd
fp_done:
    ldd #0
    andcc #$FE
    rts
