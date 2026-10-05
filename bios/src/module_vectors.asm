    include "../include/module.inc"
    org BIOS_MODULE_API_BASE
BIOS_MODULE_API:
    fcc "MBR1"
    fdb BIOS_MODULE_API_VERSION,BIOS_MODULE_API_COUNT
    jmp CF_INIT
    jmp CF_READ_SECTOR
    jmp CF_WRITE_SECTOR
    jmp SERIAL_PRINT_A
    jmp SERIAL_PRINT_CHAR_A
    jmp BIOS_SERIAL_TRY_GETC
    jmp READ_JOY1
    jmp VDC_SET_CURSOR
    jmp VDC_WRITE_VRAM_BYTE
    jmp VDC_SET_UPDATE_ADDRESS
    jmp VDC_WRITE_SELECTED
    jmp VDC_WRITE
    jmp VDC_READ
    jmp VDC_CLEAR_SCREEN
    jmp VDC_PRINT
    jmp VDC_SET_FOREGROUND_COLOR
    jmp VDC_SET_BACKGROUND_COLOR
    jmp BIOS_INSTALL_IRQ_HANDLER
    jmp BIOS_LOAD_MODULE
    jmp BIOS_RUN_MODULE

; Nonblocking, unbuffered serial receive. C clear: A = byte; C set: empty.
BIOS_SERIAL_TRY_GETC:
    lda SERIAL_SRA
    bita #$01
    beq BIOS_SERIAL_EMPTY
    lda SERIAL_RXA
    andcc #$FE
    rts
BIOS_SERIAL_EMPTY:
    orcc #$01
    rts

; X = interrupt handler ending in RTI, or zero to restore the default.
; Returns previous handler in X. Preserves caller's CC, including IRQ mask.
; Changes D. Does not enable interrupts or change peripheral configuration.
BIOS_INSTALL_IRQ_HANDLER:
    pshs cc
    orcc #$10
    ldd BIOS_MODULE_IRQ_VECTOR
    cmpx #0
    bne BIOS_INSTALL_IRQ_SET
    ldx #PARALLEL_IRQ_HANDLER
BIOS_INSTALL_IRQ_SET:
    stx BIOS_MODULE_IRQ_VECTOR
    tfr d,x
    puls cc,pc
BIOS_MODULE_API_END:
    ifgt BIOS_MODULE_API_END-$F900
        error "RAM-module ABI overlaps the BIOS font"
    endc
