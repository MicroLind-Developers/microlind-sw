

BUFFER equ $C000
BUFFER_SIZE equ $FF

_START:
    ldx #msg_init0
    jsr SERIAL_PRINT_A

_GET_SERIAL:
    ; Line feed
    ldx #msg_crlf0
    jsr SERIAL_PRINT_A

    ; Get data from serial port
    ldx #BUFFER
    ldy #BUFFER_SIZE
    jsr SERIAL_INPUT_A

    ldx #msg_print0
    jsr SERIAL_PRINT_A

    ldx #BUFFER
    jsr SERIAL_PRINT_A

    ; Line feed
    ldx #msg_crlf0
    jsr SERIAL_PRINT_A

    jmp _GET_SERIAL

FIRQ_ROUTINE:
    rti


msg_init0: fcc "Serial port test utility"
           fcb 13,10,0
msg_print0: fcb 13,10, 27, 72, 27, 50, 74
            fcn "Received data: "
msg_crlf0:  fcb 13,10,0




