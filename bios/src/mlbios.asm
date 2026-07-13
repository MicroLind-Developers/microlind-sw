; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;

; Jumptable for BIOS functions
; -----------------------------------------------------------------

; Variables
BUFFER equ SERIAL_BUFFER_START
BUFFER_SIZE equ $0F

_START:
    ; Initialize BIOS components
    jsr SERIAL_INIT
    jsr PARALLEL_INIT
    jsr CF_INIT

    ; Print init message
    ldx #msg_init0
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Main menu loop
MAIN_MENU:
    ; Print menu
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
    ldx #msg_text5
    jsr SERIAL_PRINT_A
    ldx #msg_line3
    jsr SERIAL_PRINT_A
    ldx #msg_crlf0
    jsr SERIAL_PRINT_A
    ldx #msg_prompt0
    jsr SERIAL_PRINT_A

    ; Wait for user input
    ldx #BUFFER
    ldy #BUFFER_SIZE
    jsr SERIAL_INPUT_A

    ; Process input
    ldx #BUFFER
    lda ,x
    cmpa #'1'
    beq RAM_TEST
    cmpa #'2'
    beq SERIAL_TEST
    cmpa #'3'
    beq MEMORY_DUMP
    cmpa #'4'
    beq JOYSTICK_TEST
    cmpa #'5'
    beq BOOT_MLOS
    cmpa #'6'
    beq WOZMON
    cmpa #'0'
    beq EXIT_MENU
    bra MAIN_MENU

RAM_TEST:
    jsr RAM_TEST_UTIL
    bra MAIN_MENU

SERIAL_TEST:
    jsr SERIAL_TEST_UTIL
    bra MAIN_MENU

MEMORY_DUMP:
    jsr MEMORY_DUMP_UTIL
    bra MAIN_MENU

JOYSTICK_TEST:
    jsr JOYSTICK_TEST_UTIL
    bra MAIN_MENU

BOOT_MLOS:
    jsr BOOT_MLOS_UTIL
    bra MAIN_MENU

WOZMON:
    jsr WOZMON_UTIL
    bra MAIN_MENU

EXIT_MENU:
    ; Exit to main system
    rts

; -----------------------------------------------------------------
; RAM TEST UTILITY
; -----------------------------------------------------------------
RAM_TEST_UTIL:
    pshs a,b,x,y,u
    ldx #msg_ram_test_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Test memory from $0000 to $1000 (4KB)
    ldx #0x0000
    ldy #0x1000
    lda #$55
    ldb #$AA

RAM_TEST_LOOP:
    ; Write test pattern
    sta ,x
    stb 1,x
    stb 2,x
    sta 3,x
    leax 4,x
    leay -4,y
    bne RAM_TEST_LOOP

    ; Verify test pattern
    ldx #0x0000
    ldy #0x1000

RAM_VERIFY_LOOP:
    ; Read and verify
    lda ,x
    cmpa #$55
    bne RAM_TEST_FAIL
    lda 1,x
    cmpa #$AA
    bne RAM_TEST_FAIL
    lda 2,x
    cmpa #$AA
    bne RAM_TEST_FAIL
    lda 3,x
    cmpa #$55
    bne RAM_TEST_FAIL
    leax 4,x
    leay -4,y
    bne RAM_VERIFY_LOOP

    ; Success
    ldx #msg_ram_test_pass
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

RAM_TEST_FAIL:
    ldx #msg_ram_test_fail
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

; -----------------------------------------------------------------
; SERIAL TEST UTILITY
; -----------------------------------------------------------------
SERIAL_TEST_UTIL:
    pshs a,b,x,y,u
    ldx #msg_serial_test_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Send test message
    ldx #msg_serial_test_msg
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Read response
    ldx #BUFFER
    ldy #BUFFER_SIZE
    jsr SERIAL_INPUT_A

    ; Echo back what was received
    ldx #msg_serial_test_echo
    jsr SERIAL_PRINT_A
    ldx #BUFFER
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    puls a,b,x,y,u,pc

; -----------------------------------------------------------------
; MEMORY DUMP UTILITY
; -----------------------------------------------------------------
MEMORY_DUMP_UTIL:
    pshs a,b,x,y,u
    ldx #msg_memory_dump_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; For simplicity, dump a fixed range (0x0000 to 0x0100)
    ldx #0x0000
    ldy #0x0100

MEMORY_DUMP_LOOP:
    ; Print address
    ldx #msg_memory_dump_addr_prefix
    jsr SERIAL_PRINT_A
    ldx #0x0000
    jsr SERIAL_PRINT_WORD_HEX_A
    jsr SERIAL_PRINT_CRLF_A

    ; Print 16 bytes per line
    ldy #0x10

MEMORY_DUMP_LINE_LOOP:
    ; Print byte in hex
    lda ,x
    jsr SERIAL_PRINT_BYTE_HEX_A
    lda #' '
    jsr SERIAL_PRINT_CHAR_A
    leax 1,x
    leuy -1,y
    bne MEMORY_DUMP_LINE_LOOP

    jsr SERIAL_PRINT_CRLF_A
    leuy -16,y
    bne MEMORY_DUMP_LOOP

    ldx #msg_memory_dump_end
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

; -----------------------------------------------------------------
; JOYSTICK TEST UTILITY
; -----------------------------------------------------------------
JOYSTICK_TEST_UTIL:
    pshs a,b,x,y,u
    ldx #msg_joystick_test_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Test joystick 1
    jsr READ_JOY1
    cmpa #$00
    beq JOYSTICK1_NO_INPUT
    ldx #msg_joystick1_input
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A

JOYSTICK1_NO_INPUT:
    ; Test joystick 2
    jsr READ_JOY2
    cmpa #$00
    beq JOYSTICK2_NO_INPUT
    ldx #msg_joystick2_input
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A

JOYSTICK2_NO_INPUT:
    ldx #msg_joystick_test_end
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

; -----------------------------------------------------------------
; BOOT MLOS UTILITY
; -----------------------------------------------------------------
BOOT_MLOS_UTIL:
    pshs a,b,x,y,u
    ldx #msg_boot_mlos_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Read MLOS from CF sector 0
    ldx #0x0000
    jsr CF_READ_SECTOR_BUFFER
    bcs BOOT_MLOS_FAIL

    ; Load MLOS at $0000 and jump to it
    ; We'll jump to the start of the loaded data
    ldx #STORAGE_BUFFER_START
    jmp [XAML]  ; This would be the entry point of MLOS

BOOT_MLOS_FAIL:
    ldx #msg_boot_mlos_fail
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

; -----------------------------------------------------------------
; WOZMON UTILITY
; -----------------------------------------------------------------
WOZMON_UTIL:
    pshs a,b,x,y,u
    ldx #msg_wozmon_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Jump to WozMon at $E800 (where it's loaded)
    jmp $E800

; -----------------------------------------------------------------
; WOZMON UTILITY
; -----------------------------------------------------------------
WOZMON_UTIL:
    pshs a,b,x,y,u
    ldx #msg_wozmon_start
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ; Jump to WozMon at $E800 (where it's loaded)
    jmp $E800

; String table
; -----------------------------------------------------------------
; 40 col        |                                       |

msg_line0: fcn "╒═══════════════════════════════════════╕"
msg_line1: fcn "│                                       │"
msg_line2: fcn "╞═══════════════════════════════════════╡"
msg_line3: fcn "╘═══════════════════════════════════════╛"
msg_text0: fcn "│    »»» µLind BIOS Utility Menu «««    │"
msg_text1: fcn "│ 1. RAM Test                           │"
msg_text2: fcn "│ 2. Serial Test                        │"
msg_text3: fcn "│ 3. Memory Dump                        │"
msg_text4: fcn "│ 4. Joystick Test                      │"
msg_text5: fcn "│ 5. Boot MLOS from CF                  │"
msg_text6: fcn "│ 6. WozMon                              │"
msg_prompt0: fcn "  Press a number to continue... "

msg_init0: fcn "µLind BIOS Utility Menu"
msg_ram_test_start: fcn "Running RAM Test..."
msg_ram_test_pass: fcn "RAM Test PASSED!"
msg_ram_test_fail: fcn "RAM Test FAILED!"
msg_serial_test_start: fcn "Running Serial Test..."
msg_serial_test_msg: fcn "Hello from BIOS Test!"
msg_serial_test_echo: fcn "Received: "
msg_memory_dump_start: fcn "Memory Dump Utility"
msg_memory_dump_addr_prompt: fcn "Enter memory address (or 0 to exit): "
msg_memory_dump_addr_prefix: fcn "Address: "
msg_memory_dump_end: fcn "Memory dump complete."
msg_joystick_test_start: fcn "Joystick Test"
msg_joystick1_input: fcn "Joystick 1 input: 0x"
msg_joystick2_input: fcn "Joystick 2 input: 0x"
msg_joystick_test_end: fcn "Joystick test complete."
msg_boot_mlos_start: fcn "Booting MLOS from CompactFlash..."
msg_boot_mlos_fail: fcn "Failed to boot MLOS from CF!"
msg_wozmon_start: fcn "Starting WozMon..."
msg_crlf0:       fcb 13,10,0                         ; \r\n
