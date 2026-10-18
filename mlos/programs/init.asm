    include "syscalls.inc"
    org $0400
; Function: init_main. Inputs native argc/argv. Outputs starts diagnostic worker,
; then keeps incrementing private data without yielding. Clobbers process state.
init_main:
    ldx #spawn
    lda #SYS_SPAWN
    swi
    bcs init_fail
    std child
    ldx #banner_args
    lda #SYS_WRITE
    swi
init_count:
    inc $0300
    bne init_count
    inc $0301
    bra init_count
init_fail:
    lda #'X'
    sta $0302
    bra init_fail
spawn:
    fdb worker_name
    fcb 1,0
    fdb 0,0
child: fdb 0
worker_name: fcn "worker.mlx"
banner_args: fdb banner,banner_end-banner
banner: fcc "MLOS CF scheduler"
    fcb 13,10
banner_end:
