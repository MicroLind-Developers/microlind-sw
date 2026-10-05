; Resides above both module regions, so application loads cannot replace this probe.
    org $C000
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    lda #$12
    tfr a,dp
    ldx #NAME
    ldy #$ABCD
    ldb #TEST_KIND
    jsr TEST_SERVICE
    tfr cc,b
    std $0300
    stx $0302
    sts $0304
    sty $0306
    tfr dp,a
    sta $0308
    lda #$A5
    sta $030F
DONE:
    bra DONE
NAME:
    fcn "/biosfs.mlp"
