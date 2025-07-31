    org $F000

_START:
    ldx #$F000
    ldy #$FFFF
    jsr MEMORY_DUMP

    jmp HANG

