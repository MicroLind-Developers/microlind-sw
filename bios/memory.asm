; Output:
; Bank Settings
;     Bank 0: 0x00
;     Bank 1: 0x00
;     Bank 2: 0x00
;     Bank 3: 0x00
; 
;        x0 x2 x3 x4 x5 x6 x7 x8 x9 xA xB xC xD xE xF
; 0x0000 00 F2 AA 10 03 33 B2 B8 AB C3 33 30 00 00 00
; 0x0010 A1 29 93 BF F9 93 37 7A AC DF FF FF FF 00 00
; ---------------------------------------------------


; -----------------------------------------------------------------
; MEMORY_DUMP
; input:            X = start address (0x0000 - 0xFFFF)
;                   Y = end address (0x0001 - 0xFFFF)
; output:           None
; clobbers:         A, B
; -----------------------------------------------------------------
MEMORY_DUMP:
    
    ; Print bank settings
    jsr MEMORY_DUMP_BANK_SETTINGS

    ; Align X to 16 bytes
    exg X,D
    andb #$F0
    exg X,D

    ; Store aligned X in stack
    stx ,--S
    
    ; Print dump header
    ldx #dump_header
    jsr SERIAL_PRINT_A

    ldx ,S++

_LINE_LOOP:
    ; Print memory dump line header
    jsr SERIAL_PRINT_WORD_HEX_A

    ldb #$10
_BYTE_LOOP:
    ; print space between bytes
    lda #' '
    jsr SERIAL_PRINT_CHAR_A

    ; Print memory dump byte
    lda ,X+ 
    jsr SERIAL_PRINT_BYTE_A 

    decb
    bne _BYTE_LOOP

    ; Check if x is carry over
    cmpx #$0000
    beq _DUMP_END

    ; Check if x is greater than or equal end address
    cmpr Y,X
    bhi _DUMP_END

    jsr SERIAL_PRINT_CRLF_A
    bra _LINE_LOOP

_DUMP_END:
    ; Print dump footer
    ldx #dump_footer
    jsr SERIAL_PRINT_A
    rts

; -----------------------------------------------------------------
; MEMORY_DUMP_BANK_SETTINGS
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
MEMORY_DUMP_BANK_SETTINGS:
    pshs X,A
    ldx #bank_header
    jsr SERIAL_PRINT_A
    jsr MMU_GET_REGISTER_0
    jsr SERIAL_PRINT_BYTE_HEX_A
    ldx #bank_1
    jsr SERIAL_PRINT_A
    jsr MMU_GET_REGISTER_1
    jsr SERIAL_PRINT_BYTE_HEX_A
    ldx #bank_2
    jsr SERIAL_PRINT_A
    jsr MMU_GET_REGISTER_2
    jsr SERIAL_PRINT_BYTE_HEX_A
    ldx #bank_3
    jsr SERIAL_PRINT_A
    jsr MMU_GET_REGISTER_3
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A
    puls X,A,PC


dump_header:   fcc "        x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 xA xB xC xD xE xF"
               fcb 13,10,0
dump_footer:   fcb 13,10
               fcc "-------------------------------------------------------"
               fcb 13,10,0
bank_header:   fcc "Bank Settings"
               fcb 13,10
               fcn "    Bank 0: "
bank_1:        fcb 13,10
               fcn "    Bank 1: "
bank_2:        fcb 13,10
               fcn "    Bank 2: "
bank_3:        fcb 13,10
               fcn "    Bank 3: "
               