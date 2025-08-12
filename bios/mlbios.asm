; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;

; Jumptable for BIOS functions
; -----------------------------------------------------------------


; Variables
BUFFER equ SERIAL_BUFFER_START
BUFFER_SIZE equ $0F

_START:

    ; Print init message
    ldx #msg_init0
    jsr SERIAL_PRINT_A

    ; Wait for user input
    ldx #BUFFER
    ldy #BUFFER_SIZE
    jsr SERIAL_INPUT_A

    ; Check for choice


_PRINT_MENU:
    ldx #msg_line0
    jsr SERIAL_PRINT_A
    ldx #msg_text0
    jsr SERIAL_PRINT_A
    ldx #msg_line2
    jsr SERIAL_PRINT_A
    ldx #msg_text1
    jsr SERIAL_PRINT_A
    ldx #msg_text2
    jsr SERIAL_PRINT_A
    ldx #msg_text3
    jsr SERIAL_PRINT_A
    ldx #msg_text4
    jsr SERIAL_PRINT_A
    ldx #msg_line3
    jsr SERIAL_PRINT_A
    ldx msg_crlf0
    jsr SERIAL_PRINT_A
    ldx #msg_text5
    jsr SERIAL_PRINT_A


; String table
; -----------------------------------------------------------------
; 40 col        |                                       |
msg_line0: fcn "╒═══════════════════════════════════════╕"
msg_line1: fcn "│                                       │"
msg_line2: fcn "╞═══════════════════════════════════════╡"
msg_line3: fcn "╘═══════════════════════════════════════╛"
msg_text0: fcn "│    »»» µLind BIOS Utility Menu «««    │"
msg_text1: fcn "│ 1. Ram test utility                   │"
msg_text2: fcn "│ 2. Serial port test utility           │"
msg_text3: fcn "│ 3. Memory dump utility                │"
msg_text4: fcn "│ 4. Joystic ports test utility         │" 
msg_text5: fcn "  Press a number to continue... "

msg_init0: fcn "µLind BIOS Utility Menu"

msg_setcolor0:   fcb 28,91,48,59,51,54,59,52,48,109  ; \x1b[0;36;40m Cyan on Black
msg_resetcolor0: fcb 28,91,48,59,51,57,59,52,57,109  ; \x1b[0;39;49m Reset colors
msg_crlf0:       fcb 13,10,0                         ; \r\n 
msg_indicator0:  fcc "│╱─╲"
msg_back:        fcb 28,91,49,68                     ; \x1b[1D 1 char back
msg_homeclear:   fcb 28,91,72,28,91,50,74            ; \x1b[H \x1b[2J home & clear