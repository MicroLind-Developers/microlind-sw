MLOS_SERVICE equ 1
    include "syscalls.inc"
    include "../../../bios/include/filesystem.inc"
    org $0400
; Function: fs_worker_start. Inputs native argv; owns3 resident frames and private
; MLFS state. Outputs serves requests through named message channels, no return.
; Clobbers all process state; no raw I/O or privilege assumptions in this process.
fs_worker_start:
    clr FW_CACHE_ENABLED
    clr FW_CACHE_NEXT
    jsr fw_cache_clear
    ifndef FW_DEVICE
FW_DEVICE equ 0
    endc
    lda #FW_DEVICE
    sta $0314
    clr $0315
    ldx #$0314
    lda #SYS_DEVICE_CLAIM
    swi
    bcs fs_worker_bad
    std $0310
    ldx #$0800
    ldy #1
    jsr $4000
    bcs fs_worker_bad
    jsr volume_validate
    bcs fs_worker_bad
    ldx #fw_listen_args
    lda #SYS_LISTEN
    swi
    bcs fs_worker_bad
    std fw_listener
    std fw_accept_args
fw_accept:
    ldd fw_listener
    std fw_wait_list
    ldx #fw_wait_args
    lda #SYS_WAIT_ANY
    swi
    ldx #fw_accept_args
    lda #SYS_ACCEPT
    swi
    bcs fw_accept
    ldx #fw_connection+2
    lda #SYS_PEER
    swi
    lbcs fw_disconnect
    std fw_peer
    ldx #fw_state_args
    lda #SYS_FS_STATE
    swi
    lbcs fw_disconnect
    ldd fw_state
    cmpd fw_peer
    lbne fw_disconnect
    ldd fw_connection
    std fw_send_args
    ldd fw_connection+2
    std fw_recv_args
fw_request:
    ldx #fw_recv_args
    lda #SYS_RECEIVE
    swi
    bcc fw_dispatch
    cmpd #SYS_EAGAIN
    bne fs_worker_bad
    ldd fw_connection+2
    std fw_wait_list
    ldx #fw_wait_args
    lda #SYS_WAIT_ANY
    swi
    bra fw_request
fw_dispatch:
    cmpd #0
    beq fw_disconnect
    ; Every request probes actual media on its first read, including hits.
    ; Later reads may reuse sectors owned exclusively by this drive worker.
    clr FW_CACHE_PROBED
    lda #1
    sta FW_CACHE_ENABLED
    ldd fw_packet+14
    cmpd #1
    lbne fw_invalid
    lda fw_packet
    cmpa #10
    lbhi fw_invalid
    lda fw_packet
    cmpa #1
    bhi fw_data_count
    ldd #256
    bra fw_count_ready
fw_data_count:
    ldd fw_packet+6
fw_count_ready:
    std fw_request_struct+FS_REQ_COUNT
    ldd fw_packet+8
    std fw_request_struct+FS_REQ_OFFSET
    ldd fw_packet+10
    std fw_request_struct+FS_REQ_OFFSET+2
    ldd #fw_packet+144
    std fw_request_struct+FS_REQ_BUFFER
    lda fw_packet
    cmpa #8
    bne fw_normal_buffer
    ldd #fw_packet+80
    std fw_request_struct+FS_REQ_BUFFER
fw_normal_buffer:
    lda fw_packet
    cmpa #3
    blo fw_operation
    cmpa #10
    bhs fw_operation
    tst V_READONLY
    bne fw_readonly
    lda #1
    jsr volume_state
    lbcs fs_worker_bad
fw_operation:
    ldx #fw_request_struct
    ldy #fw_function_table
    ldb fw_packet
    lslb
    jsr [b,y]
    std V_SAVED_STATUS
    lda fw_packet
    cmpa #3
    blo fw_after_mutation
    cmpa #10
    bhs fw_after_mutation
    ldd V_SAVED_STATUS
    cmpd #FS_EIO
    beq fw_dirty_error
    cmpd #FS_ENOMOUNT
    beq fw_dirty_error
    cmpd #FS_ECORRUPT
    beq fw_dirty_error
    tst F_MOUNTED
    beq fw_dirty_error
    clra
    jsr volume_state
    bcc fw_after_mutation
    ldd #FS_EIO
    std V_SAVED_STATUS
    bra fw_dirty_error
fw_dirty_error:
    lda #1
    sta V_READONLY
fw_after_mutation:
    ldd V_SAVED_STATUS
    std fw_packet+2
    ldd fw_request_struct+FS_REQ_DONE
    std fw_packet+4
    ldq fw_request_struct+FS_REQ_OFFSET
    stq fw_packet+8
fw_send_response:
    ldx #fw_send_args
    lda #SYS_SEND
    swi
    bcc fw_request
    cmpd #SYS_EAGAIN
    bne fw_disconnect
    ldd fw_connection
    std fw_wait_list
    ldx #fw_wait_args
    lda #SYS_WAIT_ANY
    swi
    bra fw_send_response
fw_readonly:
    ldd #-15
    std fw_packet+2
    bra fw_send_response
fw_invalid:
    ldd #FS_EINVAL
    std fw_packet+2
    bra fw_send_response
fw_disconnect:
    ldx #fw_connection
    lda #SYS_CLOSE
    swi
    ldx #fw_connection+2
    lda #SYS_CLOSE
    swi
    bra fw_accept
fs_worker_bad:
    ldx #fw_exit_code
    lda #SYS_EXIT
    swi
    bra fs_worker_bad

; Function: fw_stat/read/list/write/create/unlink/mkdir/rmdir/rename/truncate.
; Inputs copied fixed request packet; outputs D=MLFS status, actual count in
; request structure. Clobbers D,W,CC. Preserves X,Y,U per shared MLFS ABI.
fw_function_table:
    fdb FS_API_STAT,FS_API_LIST,FS_API_READ,FS_API_WRITE,FS_API_CREATE
    fdb FS_API_UNLINK,FS_API_MKDIR,FS_API_RMDIR,FS_API_RENAME,fw_truncate,fw_stats
fw_truncate:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    ; Resolve and verify before publishing zero size; retain allocated capacity.
    jsr F_REQUEST_CHECK
    bcs fw_truncate_return
    jsr F_LOOKUP
    bcs fw_truncate_return
    lda FS_DENTRY+1
    bita #1
    bne fw_truncate_dir
    ldq #0
    stq FS_DENTRY+2
    jsr M_STORE_ENTRY
fw_truncate_return:
    puls x,y,u,pc
fw_truncate_dir:
    ldd #-7
    orcc #1
    bra fw_truncate_return
fw_stats:
    pshs x
    ldx #fw_packet+144
    jsr FS_API_STATS
    bcs fw_stats_done
    ldd #8
    std fw_request_struct+FS_REQ_DONE
    ldd #0
    andcc #$FE
fw_stats_done:
    puls x,pc

fw_exit_code: fdb 127
fw_name: fcc "fs"
    fcb '0'+FW_DEVICE,0
fw_peer: fdb 0
fw_state_args: fdb fw_state
fw_listener: fdb 0
fw_listen_args: fdb fw_name
fw_connection: fdb 0,0
fw_accept_args: fdb 0,fw_connection
fw_wait_list: fdb 0
fw_wait_args: fdb fw_wait_list
    fcb 1,0
    fdb 0,0
; Packet op,flags,result,count,reserved,offset32,path64,path2/data overlap? fixed.
fw_packet: zmb 400
FW_PREFIX_END equ *
    ifgt FW_PREFIX_END-$0800
    error "Worker prefix overlaps descriptor"
    endc
    org $0800
    fcc "MBR1"
    fdb 1,6
    jmp fw_cf_init
    jmp fw_cf_read
    jmp fw_cf_write
    jmp fw_puts
    jmp fw_putc
    jmp fw_getc
; Function: fw_cf_init. Inputs none; outputs0/C0; preserves all except D/CC.
fw_cf_init:
    ldd #0
    andcc #$FE
    rts
; Function: fw_cf_read/write. Inputs Q=LBA28,X=512-byte worker buffer. Outputs
; A=0/C0 or error/C1; preserves W,Y,U; copied asynchronous request then wait/collect.
; Stack<=32 plus native frames; waits suspend only this drive worker.
fw_cf_read:
    pshs y,u
    pshsw
    stq $0318
    stx $031C
    clr $0316
    tst FW_CACHE_ENABLED
    beq fw_io
    jsr fw_cache_read
    bcc fw_success
    bra fw_io
fw_cf_write:
    pshs y,u
    pshsw
    stq $0318
    stx $031C
    lda #1
    sta $0316
    jsr fw_cache_clear
fw_io:
    ldd $0310
    std $0314
    clr $0317
    ldd #512
    std $031E
fw_submit:
    ldx #$0314
    lda #SYS_IO_SUBMIT
    swi
    bcc fw_submitted
    cmpd #SYS_ENOMEM
    bne fw_io_error
    lda #SYS_YIELD
    swi
    bra fw_submit
fw_submitted:
    std $0320
fw_io_wait:
    ldx #fw_io_wait_args
    lda #SYS_WAIT_ANY
    swi
    ldd $0320
    std $0322
    ldd $031C
    std $0324
    ldx #$0322
    lda #SYS_IO_COLLECT
    swi
    bcc fw_io_ok
    cmpd #SYS_EAGAIN
    beq fw_io_wait
fw_io_error:
    jsr fw_cache_clear
    pulsw
    puls y,u
    lda #1
    orcc #1
    rts
fw_io_ok:
    tst $0316
    bne fw_success
    tst FW_CACHE_ENABLED
    beq fw_success
    jsr fw_cache_store
fw_success:
    pulsw
    puls y,u
    clra
    andcc #$FE
    rts
fw_io_wait_args: fdb $0320
    fcb 1,0
    fdb 0,0
FW_CACHE_NEXT equ $0352
FW_CACHE_SLOT equ $0354
FW_CACHE_ENABLED equ $0356
FW_CACHE_PROBED equ $0357
FW_CACHE_RECORDS equ $0360       ; 16*(LBA32,valid,padding3), ends at$03E0
FW_CACHE_DATA equ $1000          ; reuse validation bitmap only after validation
; Function: fw_cache_clear. Invalidates16 read-through sectors before any write,
; on error and at worker start. Preserves D,Y,W; stack<=8; no media side effects.
fw_cache_clear:
    pshs d,y
    ldy #FW_CACHE_RECORDS
    ldb #16
fw_cache_invalidate:
    clr 4,y
    leay 8,y
    decb
    bne fw_cache_invalidate
    puls d,y,pc
; Function: fw_cache_read. Inputs saved LBA/destination at0318/031C. Outputs
; C0 hit copied, C1 miss with private victim selected. Clobbers all; stack<=4.
; The first read of every RPC always reaches media. Only this drive's worker
; owns raw access; writes invalidate all entries, recovery starts a new worker.
fw_cache_read:
    ldy #FW_CACHE_RECORDS
fw_cache_find:
    tst 4,y
    beq fw_cache_next
    ldq $0318
    cmpd ,y
    bne fw_cache_next
    cmpw 2,y
    bne fw_cache_next
    sty FW_CACHE_SLOT
    tst FW_CACHE_PROBED
    beq fw_cache_miss
    jsr fw_cache_address
    ldx $031C
    ldw #512
    tfm y+,x+
    andcc #$FE
    rts
fw_cache_next:
    leay 8,y
    cmpy #FW_CACHE_RECORDS+128
    blo fw_cache_find
    ldb FW_CACHE_NEXT
    incb
    andb #15
    stb FW_CACHE_NEXT
    lslb
    lslb
    lslb
    ldy #FW_CACHE_RECORDS
    leay b,y
    sty FW_CACHE_SLOT
fw_cache_miss:
    clr 4,y
    lda #1
    sta FW_CACHE_PROBED
    orcc #1
    rts
; Function: fw_cache_store. Publish a fully collected512-byte sector only.
; Inputs selected slot,saved LBA/destination. Clobbers all; stack<=4, no waits.
fw_cache_store:
    jsr fw_cache_address
    ldx $031C
    ldw #512
    tfm x+,y+
    ldy FW_CACHE_SLOT
    ldq $0318
    stq ,y
    lda #1
    sta 4,y
    rts
; Function: fw_cache_address. Outputs Y=selected512-byte buffer. Clobbers D,Y;
; stack2; slots are trusted private metadata and cannot escape the8KiB overlay.
fw_cache_address:
    ldd FW_CACHE_SLOT
    subd #FW_CACHE_RECORDS
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    addd #FW_CACHE_DATA
    tfr d,y
    rts

fw_state: zmb 8
fw_recv_args: fdb 0,fw_packet,400,0,0
fw_send_args: fdb 0,fw_packet,400,0,0
fw_request_struct:
    fdb fw_packet+16,fw_packet+144,256
    fdb 0,0
    fdb 0

; Function: fw_putc/puts/getc. Unused console imports retained for ABI validation.
; Inputs per legacy descriptor. Outputs none; clobbers D/CC; no raw I/O.
fw_puts:
fw_putc:
fw_getc:
    rts
F_ROOT_PATH: fcn "/"
    include "../../../mlfs/target/filesystem.asm"

    org $6000
    include "services/mlfs/validate.asm"
