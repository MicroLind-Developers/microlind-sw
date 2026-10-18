    include "syscalls.inc"
    org $0400
; Function: worker_main. Inputs native argc/argv. Outputs private sentinel/counter
; at the same logical addresses as init; deliberately does not yield.
worker_main:
    lda #$57
    sta $0302
worker_count:
    inc $0300
    bne worker_count
    inc $0301
    bra worker_count
