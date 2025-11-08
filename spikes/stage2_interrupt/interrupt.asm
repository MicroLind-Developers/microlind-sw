    org $F000

COUNTER equ $C000

_START:
    lda #$0F
    sta COUNTER
    
    lda #$01
    jsr IRQ_SET_FILTER

    ; Set up timer
    ldd #$FFFF
    jsr SERIAL_SET_CT

    lda #$07   ; Set Timer mode to clock/16
    jsr SERIAL_SET_CT_MODE

    jsr SERIAL_ENABLE_CT_IRQ

    ldx #irq_line
    jsr SERIAL_PRINT_A
    jsr IRQ_GET_CURRENT_FILTER
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A

    ldx #irq_active
    jsr SERIAL_PRINT_A
    jsr IRQ_GET_ACTIVE
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A


    ; jsr SERIAL_START_CT

_CWAI_LOOP:
    cwai #$BF   ; Wait for interrupt
    orcc #$50   ; Disable interrupts
    
    ; Things to do after interrupt occurs
    
    bra _CWAI_LOOP

    ;lbra HANG

FIRQ_ROUTINE:
    ; FIRQ handler
    ldx #irq_active
    jsr SERIAL_PRINT_A

    jsr IRQ_GET_ACTIVE
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A

    ; Clear serial irq flag
    jsr SERIAL_STOP_CT

    ; Return from FIRQ
    rti

irq_line:   fcn "IRQ Mask: "
irq_active: fcn "IRQ Active: "
