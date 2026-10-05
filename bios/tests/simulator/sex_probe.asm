; Expected results: $0300=0073, $0302=FF80. SEX preserves B and extends it into A.
    org $0400
ENTRY:
    orcc #$50
    ldmd #1
    clra
    ldb #$73
    sex
    std $0300
    lda #$12
    ldb #$80
    sex
    std $0302
DONE:
    bra DONE
