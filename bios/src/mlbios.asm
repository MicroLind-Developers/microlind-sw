; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;

; Jumptable for BIOS functions
; -----------------------------------------------------------------

    org $E000

; Variables
BUFFER equ SERIAL_BUFFER_START
BUFFER_SIZE equ $0F
RAM_TEST_START equ $0000
RAM_TEST_END equ $1000
RAM_TEST_FAIL_ADDR equ BUFFER+16
RAM_TEST_EXPECTED equ BUFFER+18
RAM_TEST_ACTUAL equ BUFFER+19

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
    beq MEMORY_DUMP_MENU
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
    lbra MAIN_MENU

SERIAL_TEST:
    jsr SERIAL_TEST_UTIL
    lbra MAIN_MENU

MEMORY_DUMP_MENU:
    jsr MEMORY_DUMP_UTIL
    lbra MAIN_MENU

JOYSTICK_TEST:
    jsr JOYSTICK_TEST_UTIL
    lbra MAIN_MENU

BOOT_MLOS:
    jsr BOOT_MLOS_UTIL
    lbra MAIN_MENU

WOZMON:
    jsr WOZMON_UTIL
    lbra MAIN_MENU

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

    ; Destructive test over $0000-$0FFF. The address-derived patterns catch
    ; more aliasing faults than a repeating fixed byte pattern.
    ldx #RAM_TEST_START
RAM_TEST_FILL_LOW:
    tfr x,d
    tfr b,a
    eora #$55
    sta ,x+
    cmpx #RAM_TEST_END
    blo RAM_TEST_FILL_LOW

    ldx #RAM_TEST_START
RAM_TEST_VERIFY_LOW:
    tfr x,d
    tfr b,a
    eora #$55
    cmpa ,x
    bne RAM_TEST_STORE_FAIL
    leax 1,x
    cmpx #RAM_TEST_END
    blo RAM_TEST_VERIFY_LOW

    ldx #RAM_TEST_START
RAM_TEST_FILL_XOR:
    tfr x,d
    pshs b
    eora ,s+
    eora #$AA
    sta ,x+
    cmpx #RAM_TEST_END
    blo RAM_TEST_FILL_XOR

    ldx #RAM_TEST_START
RAM_TEST_VERIFY_XOR:
    tfr x,d
    pshs b
    eora ,s+
    eora #$AA
    cmpa ,x
    bne RAM_TEST_STORE_FAIL
    leax 1,x
    cmpx #RAM_TEST_END
    blo RAM_TEST_VERIFY_XOR

    ; Leave the tested area in a known state.
    ldx #RAM_TEST_START
    clra
RAM_TEST_CLEAR:
    sta ,x+
    cmpx #RAM_TEST_END
    blo RAM_TEST_CLEAR

    ; Success
    ldx #msg_ram_test_pass
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    puls a,b,x,y,u,pc

RAM_TEST_STORE_FAIL:
    ldb ,x
    std RAM_TEST_EXPECTED
    stx RAM_TEST_FAIL_ADDR

RAM_TEST_FAIL:
    ldx #msg_ram_test_fail
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A
    ldx #msg_ram_test_fail_addr
    jsr SERIAL_PRINT_A
    ldx RAM_TEST_FAIL_ADDR
    jsr SERIAL_PRINT_WORD_HEX_A
    jsr SERIAL_PRINT_CRLF_A
    ldx #msg_ram_test_expected
    jsr SERIAL_PRINT_A
    lda RAM_TEST_EXPECTED
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A
    ldx #msg_ram_test_actual
    jsr SERIAL_PRINT_A
    lda RAM_TEST_ACTUAL
    jsr SERIAL_PRINT_BYTE_HEX_A
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

    ldx #$0000
    ldy #$0100
    jsr MEMORY_DUMP

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
    ldq #$00000000
    jsr CF_READ_SECTOR_BUFFER
    bcs BOOT_MLOS_FAIL

    ; Jump to the start of the loaded sector.
    jmp STORAGE_BUFFER_START

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

; String table
; -----------------------------------------------------------------
; 40 col        |                                       |

; msg_line0: fcn "╒═══════════════════════════════════════╕"
; msg_line1: fcn "│                                       │"
; msg_line2: fcn "╞═══════════════════════════════════════╡"
; msg_line3: fcn "╘═══════════════════════════════════════╛"
; msg_text0: fcn "│    »»» µLind BIOS Utility Menu «««    │"
; msg_text1: fcn "│ 1. RAM Test                           │"
; msg_text2: fcn "│ 2. Serial Test                        │"
; msg_text3: fcn "│ 3. Memory Dump                        │"
; msg_text4: fcn "│ 4. Joystick Test                      │"
; msg_text5: fcn "│ 5. Boot MLOS from CF                  │"
; msg_text6: fcn "│ 6. WozMon                             │"
; msg_prompt0: fcn "  Press a number to continue... "

msg_line0: fcc "+---------------------------------------+"
           fcb 10,13,0
msg_line1: fcc "*                                       *"
           fcb 10,13,0
msg_line2: fcc "+---------------------------------------+"
           fcb 10,13,0
msg_line3: fcc "+---------------------------------------+"
           fcb 10,13,0
msg_text0: fcc "*  --- microLind BIOS Utility Menu ---  *"
           fcb 10,13,0
msg_text1: fcc "* 1. RAM Test                           *"
           fcb 10,13,0
msg_text2: fcc "* 2. Serial Test                        *"
           fcb 10,13,0
msg_text3: fcc "* 3. Memory Dump                        *"
           fcb 10,13,0
msg_text4: fcc "* 4. Joystick Test                      *"
           fcb 10,13,0
msg_text5: fcc "* 5. Boot MLOS from CF                  *"
           fcb 10,13,0
msg_text6: fcc "* 6. WozMon                             *"
           fcb 10,13,0
msg_prompt0: fcc "  Press a number to continue... "
           fcb 10,13,0

msg_init0: fcc "microLind BIOS Utility Menu"
           fcb 10,13,0
msg_ram_test_start: fcc "Running RAM Test..."
           fcb 10,13,0
msg_ram_test_pass: fcc "RAM Test PASSED!"
           fcb 10,13,0
msg_ram_test_fail: fcc "RAM Test FAILED!"
           fcb 10,13,0
msg_ram_test_fail_addr: fcc "Address: "
           fcb 0
msg_ram_test_expected: fcc "Expected: "
           fcb 0
msg_ram_test_actual: fcc "Actual: "
           fcb 0
msg_serial_test_start: fcc "Running Serial Test..."
           fcb 10,13,0
msg_serial_test_msg: fcc "Hello from BIOS Test!"
           fcb 10,13,0
msg_serial_test_echo: fcc "Received: "
           fcb 10,13,0
msg_memory_dump_start: fcc "Memory Dump Utility"
           fcb 10,13,0
msg_memory_dump_addr_prompt: fcc "Enter memory address (or 0 to exit): "
           fcb 10,13,0
msg_memory_dump_addr_prefix: fcc "Address: "
           fcb 10,13,0
msg_memory_dump_end: fcc "Memory dump complete."
           fcb 10,13,0
msg_joystick_test_start: fcc "Joystick Test"
           fcb 10,13,0
msg_joystick1_input: fcc "Joystick 1 input: 0x"
           fcb 10,13,0
msg_joystick2_input: fcc "Joystick 2 input: 0x"
           fcb 10,13,0
msg_joystick_test_end: fcc "Joystick test complete."
           fcb 10,13,0
msg_boot_mlos_start: fcc "Booting MLOS from CompactFlash..."
           fcb 10,13,0
msg_boot_mlos_fail: fcc "Failed to boot MLOS from CF!"
           fcb 10,13,0
msg_wozmon_start: fcc "Starting WozMon..."
           fcb 10,13,0
msg_crlf0:       fcb 13,10,0                         ; \r\n
