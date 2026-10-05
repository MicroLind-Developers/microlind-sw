    org $0400
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    lda #1
    sta $0300
    jsr SERIAL_INIT
    andcc #$FE
    jsr SERIAL_START
    jsr BIOS_MODULE_SERIAL_GETC
    lbcc FAIL
    lda #2
    sta $0300
    ldx #$1234
    lda #$5A
    jsr BIOS_MODULE_VDC_BYTE
    lbcs FAIL
    cmpx #$1234
    lbne FAIL
    jsr BIOS_MODULE_VDC_ADDRESS
    lbcs FAIL
    lda #31
    jsr BIOS_MODULE_VDC_READ
    lbcs FAIL
    cmpb #$5A
    lbne FAIL
    lda #3
    sta $0300
    ldx #PARALLEL_IRQ_HANDLER
    stx BIOS_MODULE_IRQ_VECTOR
    ldx #HANDLER
    lda #$55
    tfr a,cc
    jsr BIOS_MODULE_IRQ_INSTALL
    tfr cc,b
    cmpb #$55
    lbne FAIL
    cmpx #PARALLEL_IRQ_HANDLER
    lbne FAIL
    ldx #0
    lda #$40
    tfr a,cc
    jsr BIOS_MODULE_IRQ_INSTALL
    tfr cc,b
    cmpb #$40
    lbne FAIL
    cmpx #HANDLER
    lbne FAIL
    ldx BIOS_MODULE_IRQ_VECTOR
    cmpx #PARALLEL_IRQ_HANDLER
    lbne FAIL
    orcc #$10
    ldx #HANDLER
    jsr BIOS_MODULE_IRQ_INSTALL
    lda #4
    sta $0300
    jsr PARALLEL_INIT
    clr $F404              ; Accept the VIA's IRQ level.
    lda #$A0
    sta $F42E              ; Enable Timer 2 interrupt.
    lda #200
    sta $F428
    clr $F429              ; Start Timer 2.
    andcc #$EF
    ldy #1000
IRQ_WAIT:
    tst $030E
    bne IRQ_OK
    leay -1,y
    bne IRQ_WAIT
    bra FAIL
IRQ_OK:
    orcc #$10
    lda #$20
    sta $F42E              ; Disable Timer 2 interrupt.
    ldx #0
    jsr BIOS_MODULE_IRQ_INSTALL
    lda #5
    sta $0300
SERIAL_WAIT:
    tst $030F              ; Host injects a byte and releases this checkpoint.
    beq SERIAL_WAIT
    jsr BIOS_MODULE_SERIAL_GETC
    bcs FAIL
    cmpa #'K'
    bne FAIL
    jsr BIOS_MODULE_SERIAL_GETC
    bcc FAIL
    lda #$A5
    sta $0301
DONE:
    bra DONE
FAIL:
    lda #$FF
    sta $0301
    bra DONE
HANDLER:
    lda $F428              ; Acknowledge Timer 2 and return through CPU vector.
    inc $030E
    rti
