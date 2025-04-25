    org $F000


; MMU Test Application for 6309
; Verifies each of the 3 16KB MMU windows via serial diagnostics

MMU_WINDOW_SIZE     equ $4000
MMU_NUM_WINDOWS     equ $03
TEST_PATTERN_1      equ $A5
TEST_PATTERN_2      equ $5A
MMU_RANGE           equ $19         ; Number of physical pages in available for RAM (bank 31 is applican RAM)
MMU_BANK_START_0    equ $0000       ; Logical start address for MMU bank 0
MMU_BANK_START_1    equ $4000       ; Logical start address for MMU bank 1
MMU_BANK_START_2    equ $8000       ; Logical start address for MMU bank 2

MMU_BANK_0       equ $00
MMU_BANK_1       equ $01
MMU_BANK_2       equ $02

CURRENT_PAGE    equ $C000
START_PAGE      equ $00

_START:
    ; Set stack pointer
    lds #$E000
    ; Set direct page register to $D0
    lda #$D0
    tfr a,dp

    jsr SET_LED_BLUE

    lda #START_PAGE           ; Start with page 0

TEST_LOOP:
    sta CURRENT_PAGE

    ; === Print Diagnostic ===
    ldx #str_testing
    jsr SERIAL_PRINT_A

    lda #MMU_BANK_0
    jsr SERIAL_PRINT_BYTE_HEX_A

    ldx #str_with
    jsr SERIAL_PRINT_A

    lda CURRENT_PAGE
    jsr SERIAL_PRINT_BYTE_HEX_A

    ; Set MMU and write pattern
    lda CURRENT_PAGE
    jsr MMU_SET_REGISTER_0
    jsr MMU_SET_REGISTER_1
    jsr MMU_SET_REGISTER_2
    
    ldb #TEST_PATTERN_1
    ldy #MMU_WINDOW_SIZE

    ldx #MMU_BANK_START_0
_WRITE_LOOP:
    stb ,x+
    leay -1,y
    bne _WRITE_LOOP

_CIB1:
    ldy #MMU_WINDOW_SIZE
    ldb #TEST_PATTERN_1
    ldx #MMU_BANK_START_1
_VB1:
    cmpb ,x+
    bne ERROR_HANDLER
    leay -1,y
    bne _VB1

    ldx #str_ok_in_bank_1
    jsr SERIAL_PRINT_A

_CIB2:
    ldy #MMU_WINDOW_SIZE
    lda #TEST_PATTERN_1
    ldx #MMU_BANK_START_2
_VB2:
    cmpa ,x+
    bne ERROR_HANDLER
    leay -1,y
    bne _VB2

    ldx #str_ok_in_bank_2
    jsr SERIAL_PRINT_A

    lda CURRENT_PAGE
    inca
    cmpa #MMU_RANGE
    blo TEST_LOOP

    ; All banks verified, set LED to green and hang
    jsr SET_LED_GREEN
    ldx #str_done
    jsr SERIAL_PRINT_A
    jsr SERIAL_PRINT_CRLF_A

    ldx #$0000
    ldy #$ffff
    jsr MEMORY_DUMP

    jmp HANG

ERROR_HANDLER:
    ldx #str_fail
    jsr SERIAL_PRINT_A
    jsr SET_LED_RED
    
    ; Print memory dump
    ldx #$0000
    ldy #$BFFF
    jsr MEMORY_DUMP 
    
    jmp HANG


; --- Strings ---

str_testing: fcc "Testing MMU Bank "
             fcb 0
str_with:    fcc " with page "
             fcb 0
str_ok_in_bank_1:      fcc "... BANK 1 OK"
             fcb 0
str_ok_in_bank_2:      fcc "... BANK 2 OK"
             fcb 13,10,0
str_fail:    fcc "... FAIL! ABORTING!"
             fcb 13,10,0
str_crlf:    fcb 13,10,0
str_done:    fcc "Checking 31 banks and MMU reg 0-2: Done! Well done young padawan!"
             fcb 13,10
             fcc "The force is strong with this one! Performing complete memory dump..."
             fcb 13,10,13,10,0