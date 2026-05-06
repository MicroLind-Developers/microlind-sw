; -----------------------------------------------------------------
; MLOS kernel skeleton
; -----------------------------------------------------------------

    IFNDEF MLOS_INC
        include "../include/mlos.inc"
    ENDC

    org MLOS_ORIGIN

MLOS_START:
    orcc #$50
    lds #MLOS_STACK_TOP

    jsr MEM_MANAGER_INIT
    jsr BIOS_SET_LED_GREEN

    ldx #msg_banner
    jsr BIOS_SERIAL_PRINT
    jsr BIOS_SERIAL_CRLF

MLOS_HALT:
    bra MLOS_HALT

msg_banner:
    fcn "MLOS kernel skeleton"
