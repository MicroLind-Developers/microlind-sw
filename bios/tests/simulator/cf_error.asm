; TEST_LBA and TEST_SERVICE are supplied by the host runner.
    org $0400
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    ldq #TEST_LBA
    ldx #$1000
    ldy #$1357
    ldu #$2468
    jsr TEST_SERVICE
    tfr cc,b
    std $0302
    stx $0304
    sty $0306
    stu $0308
    stw $030A
    lda #$A5
    sta $0301
DONE:
    bra DONE
