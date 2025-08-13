; -----------------------------------------------------------------
; Expansion board bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;

    include "../include/memory.inc"

EXP_BASE        EQU $F600
EXP_DATA_START  EQU $D800

; --- Expansion Baseboard 1 and Slots ---
EXP_BASE0       EQU $F600    ; Expansion Baseboard 1 start
EXP_SLOT0       EQU $F640    ; Slot 1 (128 bytes, 7 bits)
EXP_SLOT1       EQU $F6C0    ; Slot 2 (32 bytes, 5 bits)
EXP_SLOT2       EQU $F6E0    ; Slot 3 (8 bytes, 3 bits)
EXP_SLOT3       EQU $F6E8    ; Slot 4 (8 bytes, 3 bits)
EXP_SLOT4       EQU $F6F0    ; Slot 5 (8 bytes, 3 bits)
EXP_FREE0       EQU $F6F8    ; 8 bytes free at end of block

; --- Expansion Baseboard 2 and Slots ---
EXP_BASE1       EQU $F700    ; Expansion Baseboard 2 start
EXP_SLOT5       EQU $F740    ; Slot 6 (128 bytes, 7 bits)
EXP_SLOT6       EQU $F7C0    ; Slot 7 (32 bytes, 5 bits)
EXP_SLOT7       EQU $F7E0    ; Slot 8 (8 bytes, 3 bits)
EXP_SLOT8       EQU $F7E8    ; Slot 9 (8 bytes, 3 bits)
EXP_SLOT9       EQU $F7F0    ; Slot 10 (8 bytes, 3 bits)
EXP_FREE1       EQU $F7F8    ; 8 bytes free at end of block

; --- Baseboard registers ---
EXP_BASE0_INFO  EQU EXP_BASE0+0 ; Baseboard 1 register
                                ; Bit0 - Memory socket 1 present
                                ; Bit1 - Memory socket 2 present
                                ; Bit2 - I2C add-on present
                                ; Bit3 - RTC add-on present
                                ; Bit7 - Always 0 (for auto detect purpose)

EXP_BASE1_INFO  EQU EXP_BASE1+0 ; Baseboard 2 register
                                ; Bit0 - Memory socket 1 present
                                ; Bit1 - Memory socket 2 present
                                ; Bit2 - I2C add-on present
                                ; Bit3 - RTC add-on present
                                ; Bit7 - Always 0 (for auto detect purpose)


; --- Expansion Board data structure ---
EXP_BASE0_CONFIG   EQU     EXPANSION_DRIVER_MEMORY_START
                             ; Bit0 - Board 1 present
                             ; Bit1 - Memory socket 1 present
                             ; Bit2 - Memory socket 2 present
                             ; Bit3 - I2C add-on present for board 1
                             ; Bit4 - RTC add-on present for board 1

EXP_BASE1_CONFIG   EQU     EXPANSION_DRIVER_MEMORY_START+1
                             ; Bit0 - Board 2 present
                             ; Bit1 - Memory socket 1 present
                             ; Bit2 - Memory socket 2 present
                             ; Bit3 - I2C add-on present for board 2
                             ; Bit4 - RTC add-on present for board 2

SLOT0_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+2     ; 1 byte: board info
SLOT1_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+3     ; 1 byte: board info
SLOT2_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+4     ; 1 byte: board info
SLOT3_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+5     ; 1 byte: board info
SLOT4_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+6     ; 1 byte: board info


SLOT5_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+7     ; 1 byte: board info
SLOT6_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+8     ; 1 byte: board info
SLOT7_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+9     ; 1 byte: board info
SLOT8_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+10     ; 1 byte: board info
SLOT9_CONFIG       EQU     EXPANSION_DRIVER_MEMORY_START+11     ; 1 byte: board info



; -------------------------------------------------------
; Initialization of the expansion board
; -------------------------------------------------------
; input:            None
; output:           None
; clobbers:         A, X, Y
; -------------------------------------------------------
EXP_INIT:
        
        ; Initialize expansion board 1 and 2
        ldx #EXP_BASE1
        jsr EXP_INIT_BOARD
        ldx #EXP_BASE2
        jsr EXP_INIT_BOARD

        rts


; --- Constants ---

; --- Entry Point ---
check_expansion:
    lda IPR         ; Load IPR register from serial

    ; Check if Expansion Board 1 is present
    bita #$20
    beq _skip_expansions

    lda EXP_BASE0        ; Read board 1 main register
    sta BOARD1_STATUS

    bita #$04             ; Check if I2C add-on installed
    beq _skip_i2c1

    ldx #EXP_BASE0 + I2C_INFO_OFFSET
    ldy #I2C_BOARD1_INFO
    ldb #5
_copy_i2c1:
    lda ,x+
    sta ,y+
    decb
    bne .copy_i2c1

.skip_i2c1:
.skip_board1:

    lda IPR_ADDR          ; Re-load IPR

    ; Check if Expansion Board 2 is present
    bita #$10
    beq .skip_board2

    lda EXP2_BASE        ; Read board 2 main register
    sta BOARD2_STATUS

    bita #$04             ; Check if I2C add-on installed
    beq .skip_i2c2

    ldx #EXP2_BASE + I2C_INFO_OFFSET
    ldy #I2C_BOARD2_INFO
    ldb #5
.copy_i2c2:
    lda ,x+
    sta ,y+
    decb
    bne .copy_i2c2

.skip_i2c2:
_skip_expansions:
    rts

EXPANSION_IRQ_HANDLER:
    rti
