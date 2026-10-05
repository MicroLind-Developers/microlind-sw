; A partition table must return from the legacy boot service, never execute.
    org $0400
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    jsr SERIAL_INIT
    andcc #$FE
    jsr SERIAL_START
    jsr BOOT_MLOS_UTIL
    lda #$A5
    sta $0301
DONE:
    bra DONE
