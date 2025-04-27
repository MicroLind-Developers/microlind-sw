; -----------------------------------------------------------------
; 65c52 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;

; Register Location
    org $FF00
SERIAL_BASE         EQU $f400

; COMMON REGISTERS (Offset)
; Port A
; TDR1                EQU $03   ; Transmit Data Register
; RDR1                EQU $03   ; Receive Data Register
; IER1                EQU $00   ; Interupt Enable Register
; ISR1                EQU $00   ; Interupt Status Register
; CR1                 EQU $01   ; Control Register (Bit 7 EQU low)
; FR1                 EQU $01   ; Format Register (Bit 7 EQU high)
; CSR1                EQU $01   ; Control Status Register
; CDR1                EQU $02   ; Compare Data Register (Bit 6 EQU low)
; ACR1                EQU $02   ; Auxilliary Control Register (Bit 6 EQU high)

; ;Port B
; TDR2                EQU $07   ; Transmit Data Register
; RDR2                EQU $07   ; Receive Data Register
; IER2                EQU $04   ; Interupt Enable Register
; ISR2                EQU $04   ; Interupt Status Register
; CR2                 EQU $05   ; Control Register (Bit 7 EQU low)
; FR2                 EQU $05   ; Format Register (Bit 7 EQU high)
; CSR2                EQU $05   ; Control Status Register
; CDR2                EQU $06   ; Compare Data Register (Bit 6 EQU low)
; ACR2                EQU $06   ; Auxilliary Control Register (Bit 6 EQU high)

; COMMON REGISTERS (Direct)
; Port A
TDR1              EQU SERIAL_BASE+3   ; Transmit Data Register
RDR1              EQU SERIAL_BASE+3   ; Receive Data Register
IER1              EQU SERIAL_BASE+0   ; Interupt Enable Register
ISR1              EQU SERIAL_BASE+0   ; Interupt Status Register
CR1               EQU SERIAL_BASE+1   ; Control Register (Bit 7 EQU low)
FR1               EQU SERIAL_BASE+1   ; Format Register (Bit 7 EQU high)
CSR1              EQU SERIAL_BASE+1   ; Control Status Register
CDR1              EQU SERIAL_BASE+2   ; Compare Data Register (Bit 6 EQU low)
ACR1              EQU SERIAL_BASE+2   ; Auxilliary Control Register (Bit 6 EQU high)

;Port B
TDR2              EQU SERIAL_BASE+7   ; Transmit Data Register
RDR2              EQU SERIAL_BASE+7   ; Receive Data Register
IER2              EQU SERIAL_BASE+4   ; Interupt Enable Register
ISR2              EQU SERIAL_BASE+4   ; Interupt Status Register
CR2               EQU SERIAL_BASE+5   ; Control Register (Bit 7 EQU low)
FR2               EQU SERIAL_BASE+5   ; Format Register (Bit 7 EQU high)
CSR2              EQU SERIAL_BASE+5   ; Control Status Register
CDR2              EQU SERIAL_BASE+6   ; Compare Data Register (Bit 6 EQU low)
ACR2              EQU SERIAL_BASE+6   ; Auxilliary Control Register (Bit 6 EQU high)

; -----------------------------------------------------------------
; SERIAL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------

SERIAL_INIT:
        jsr SERIAL_INIT_A
        jsr SERIAL_INIT_B
        rts

SERIAL_INIT_A:
        lda #$c1                ; Set interrupt on Transmit Data Empty, Receive Data Full
        sta IER1
        lda #$0e                ; CDR, Set 38400 Baud, 1 stop bit, no echo
        sta CR1
        lda #$f0                ; 8 bits, No parity, DTR & RTS low 
        sta CR1
        rts

SERIAL_INIT_B:
        lda #$c1                ; Set interrupt on Transmit Data Empty, Receive Data Full
        sta IER2
        lda #$0c                ; CDR, Set 9600 Baud, 1 stop bit, no echo
        sta CR2
        lda #$f0                ; 8 bits, No parity, DTR & RTS low 
        sta CR2
        rts

SERIAL_INTERRUPT:
        lda ISR1
        anda #$01
        beq SERIAL_INTERRUPT
        lda RDR1
        sta TDR1
        rts

; -----------------------------------------------------------------
; SERIAL PRINT
; input:            X - Points to /0 terminated string
; output:           None
; clobbers:         A, B, X
; -----------------------------------------------------------------
prt0:   ldb ISR1
        andb #$40
        beq prt0
        sta TDR1
SERIAL_PRINT_A:  
        lda ,x+
        bne prt0
        rts

;---------------------------------------------------------------------
; Input char from UART (blocking)
; Exit: character in A
; -----------------------------------------------------------------
; SERIAL INPUT (blocking)
; input:            None
; output:           A - Character
; clobbers:         A, B
; -----------------------------------------------------------------
    
SERIAL_INPUT_A:
        lda ISR1                ; Get status            
        anda #$01               ; Check if receiver is full
        beq SERIAL_INPUT_A      ; if not...
        lda RDR1                ; Get charactir in A
        rts