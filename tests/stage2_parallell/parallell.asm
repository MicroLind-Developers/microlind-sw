    org $F000


_START:
        ldx #JOY_INIT_LABEL
        jsr SERIAL_PRINT_A

LOOP:
        ; --- JOY1 ---
        
        ldx   #JOY1_LABEL
        jsr   SERIAL_PRINT_A
        jsr   READ_JOY1
        jsr   SERIAL_PRINT_BYTE_HEX_A

        ldx   #JOY2_LABEL
        jsr   SERIAL_PRINT_A
        jsr   READ_JOY2
        jsr   SERIAL_PRINT_BYTE_HEX_A
        jsr   SERIAL_PRINT_CRLF_A

        ldx  #JOY_LINE_CLR
        jsr  SERIAL_PRINT_A

        JMP   LOOP

JOY_INIT_LABEL: fcc "Parallel port test utility"
                fcb 13,10,0
JOY1_LABEL      fcc " JOY1: "
                fcb 0
JOY2_LABEL      fcc " JOY2: "
                fcb 0
JOY_LINE_CLR:   fcb 13,10,0
