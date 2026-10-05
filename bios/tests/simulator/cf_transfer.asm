; Execute the real ROM services. $0300 is the current stage, $0301 the result.
    org $0400
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    lda #1
    sta $0300
    jsr BIOS_MODULE_CF_INIT
    lbcs FAIL
    lda #2
    sta $0300
    lda #$A5
    sta $0FFF
    sta $1200
    ldq #1
    ldx #$1000
    ldy #$1357
    ldu #$2468
    jsr BIOS_MODULE_CF_READ
    lbcs FAIL
    tsta
    lbne FAIL
    cmpx #$1200
    lbne FAIL
    cmpy #$1357
    lbne FAIL
    cmpu #$2468
    lbne FAIL
    cmpw #1
    lbne FAIL
    lda $0FFF
    cmpa #$A5
    lbne FAIL
    lda $1200
    cmpa #$A5
    lbne FAIL
    ldx #$1000
    ldy #512
    clrb
CHECK:
    cmpb ,x+
    lbne FAIL
    incb
    leay -1,y
    bne CHECK
    lda #3
    sta $0300
    ldx #$1000
    ldy #512
CHANGE:
    lda ,x
    eora #$5A
    sta ,x+
    leay -1,y
    bne CHANGE
    ldq #2
    ldx #$1000
    ldy #$1357
    ldu #$2468
    jsr BIOS_MODULE_CF_WRITE
    lbcs FAIL
    tsta
    lbne FAIL
    cmpx #$1200
    lbne FAIL
    cmpy #$1357
    lbne FAIL
    cmpu #$2468
    lbne FAIL
    cmpw #2
    lbne FAIL
    lda #4
    sta $0300
    ldq #2
    ldx #$1400
    jsr BIOS_MODULE_CF_READ
    bcs FAIL
    ldx #$1000
    ldy #$1400
    ldu #512
COMPARE:
    lda ,x+
    cmpa ,y+
    bne FAIL
    leau -1,u
    bne COMPARE
    lda #$A5
    sta $0301
DONE:
    bra DONE
FAIL:
    lda #$FF
    sta $0301
    bra DONE
