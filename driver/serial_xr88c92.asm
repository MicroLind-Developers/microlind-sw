; -----------------------------------------------------------------
; xr88c92 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;

; Reqires S stack pointer to be initialized

; Register Location
;    org $FF00
SERIAL_BASE         EQU $F420

; COMMON REGISTERS (Direct)
; Port A
MRA              EQU SERIAL_BASE+0   ; Mode Register A 0 - 2
SRA              EQU SERIAL_BASE+1   ; Status Register A
RXA              EQU SERIAL_BASE+3   ; Receive Data Register A
TXA              EQU SERIAL_BASE+3   ; Transmit Data Register A
CRA              EQU SERIAL_BASE+2   ; Command Register A
CSRA             EQU SERIAL_BASE+1   ; Clock Select Register A

;Port B
MRB              EQU SERIAL_BASE+8   ; Mode Register B 0 - 2
SRB              EQU SERIAL_BASE+9   ; Status Register B
RXB              EQU SERIAL_BASE+11  ; Receive Data Register B
TXB              EQU SERIAL_BASE+11  ; Transmit Data Register B
CRB              EQU SERIAL_BASE+10  ; Command Register B
CSRB             EQU SERIAL_BASE+9   ; Clock Select Register B

;Common
ACR              EQU SERIAL_BASE+4   ; Auxilliary Control Register
ISR              EQU SERIAL_BASE+5   ; Interrupt Status Register   
IMR              EQU SERIAL_BASE+5   ; Interrupt Mask Register
IPCR             EQU SERIAL_BASE+4   ; Input Port Change Register 
OPCR             EQU SERIAL_BASE+13  ; Output Port Configuration Register
SPCR             EQU SERIAL_BASE+15  ; Stop Counter/Timer Register
ROPR             EQU SERIAL_BASE+15  ; Reset Output Port Register
SOPR             EQU SERIAL_BASE+14  ; Set Output Port Register
STCR             EQU SERIAL_BASE+14  ; Start Counter/Timer Register
GPR              EQU SERIAL_BASE+12  ; General Purpose Register
CUR              EQU SERIAL_BASE+6   ; Counter/Timer Upper Register
CLR              EQU SERIAL_BASE+7   ; Counter/Timer Lower Register
CTPU             EQU SERIAL_BASE+6   ; Counter/Timer Preset Upper Register
CTPL             EQU SERIAL_BASE+7   ; Counter/Timer Preset Lower Register

; -----------------------------------------------------------------
; SERIAL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_INIT:
        lda #$ba        ;Disable transmiters and recivers, and reset MR pointers to MR0
        sta CRA
        sta CRB
        lda #$20        ;Reset recivers
        sta CRA
        sta CRB
        lda #$30        ;Reset transmiters
        sta CRA
        sta CRB
        lda #$40        ;Reset error status
        sta CRA
        sta CRB
        lda #$01        ;Select baud rate table and FIFO triger levels
        sta MRA
        sta MRB
        lda #$93        ;Select formating and auto RX RTS control
        sta MRA
        sta MRB
        lda #$17        ;Select loopback mode, auto CTS, and stop bit length
        sta MRA
        sta MRB
        lda #$cc        ;Select baud rate
        sta CSRA
        sta CSRB
        lda #$80        ;Select baud rate table, C/T mode, and IPCR interupts
        sta ACR
        clra
        sta IMR         ;Disable all interupts
        sta OPCR        ;Set output ports 2-7 to manual control
        lda SPCR        ;Stop the C/T
        rts

        ; lda #$b0 ;lda with "set MR pointer to MR0" command
        ; sta CRA
        ; sta CRB
        ; lda #$01 ;lda data to be stored in MR0
        ; sta MRA
        ; sta MRB
        ; lda #$13 ;lda data to be stored in MR1
        ; sta MRA
        ; sta MRB
        ; lda #$07 ;lda data to be stored in MR2
        ; sta MRA
        ; sta MRB
        ; lda #$cc ;set the baudrates of the reciver and transmiter
        ; sta CSRA
        ; sta CSRB
        ; lda #$80 ;selects baudrate set 2
        ; sta ACR
        ; clr IMR  ;turn off all interupts
        ; clr OPCR ;turn off automated output port control
        ; lda SPCR ;stop C/T
        ; rts

; -----------------------------------------------------------------
; SERIAL_START
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_START:
        lda #$05
        bcs SER_START1 
        sta CRA
        rts
SER_START1:
        sta CRB
        rts

; -----------------------------------------------------------------
; SERIAL PRINT
; input:            X - Points to /0 terminated string
; output:           None
; clobbers:         X
; -----------------------------------------------------------------
SERIAL_PRINT_A:
        pshs a,b
        bra PTR1

PRT0:
        ldb SRA
        andb #$04
        beq PRT0
        sta TXA
        
PTR1:
        lda ,x+
        bne PRT0
        puls a,b
        rts

; -----------------------------------------------------------------
; SERIAL PRINT CHAR
; input:            A - character to print
; output:           None
; clobbers:         None
; -----------------------------------------------------------------

SERIAL_PRINT_CHAR_A:
        stb ,-s
PRTB0:
        ldb SRA
        andb #$04
        beq PRTB0
        sta TXA
        puls b,pc


; -----------------------------------------------------------------
; Input string from UART (blocking)
; Exit: String in buffer X
; -----------------------------------------------------------------
; SERIAL INPUT (blocking)
; input:            X - Buffer address, Y - Buffer size
; output:           None
; clobbers:         A, B, X, Y, W
; -----------------------------------------------------------------
SERIAL_INPUT_A:
        cmpy #$0000
        beq INP4
        addr x,y
        tfr x,w
INP3:
        tfr w,x
        lda #$0d
        jsr SERIAL_PRINT_CHAR_A
        lda #'>'
        bra INP2
INP4:
        ldx err_bufferSize0
        jmp ERR
INP1:
        leax -1,x
        cmpr w,x
        bmi INP3
INP2:
        jsr SERIAL_PRINT_CHAR_A
INP0:
        lda SRA
        anda #$01
        beq INP0
        lda RXA
        cmpr y,x
        beq INP3
        cmpa #$7f
        beq INP1
        sta ,x+
        jsr SERIAL_PRINT_CHAR_A
        cmpa #$1b
        beq INP3
        cmpa #$0d
        bne INP0
        lda #$00
        sta ,x
        rts

ERR:
        jsr SERIAL_PRINT_A
        jmp HANG

err_bufferSize0: fcn '?illegal buffer size exception'

; -----------------------------------------------------------------
; Print byte as hex to UART
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            A - Byte to print
; output:           None
; clobbers:         A, B
; -----------------------------------------------------------------
SERIAL_PRINT_BYTE_A:
        pshs a
        lsra
        lsra
        lsra
        lsra
        jsr PRB0
        puls a
PRB0:
        anda #$0f
        ora #'0'
        cmpa #$3a
        lbcs SERIAL_PRINT_CHAR_A
        adda #$07
        lbra SERIAL_PRINT_CHAR_A

; -----------------------------------------------------------------
; Trap handler
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
; Its a 
; TRAP:
;         bitmd #$80
;         bne TRP0
;         bitmd #$40
;         bne TRP1
;         lda #'G'
;         jsr SERIAL_ECHO_A
;         bra HANG
; TRP0:
;         lda #'D'
;         jsr SERIAL_ECHO_A
;         bra HANG
; TRP1:
;         lda #'I'
;         jsr SERIAL_ECHO_A



; SER_RESET:


; -----------------------------------------------------------------
; Convert nibble to ASCII
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            A - Nibble to convert
; output:           A - ASCII character
; clobbers:         A
; -----------------------------------------------------------------
NIBBLE_TO_ASCII:
    cmpa  #$0A
    blo   .num
    adda  #$37    ; A=10..15 → 'A'..'F'
    rts
.num:
    adda  #$30    ; A=0..9 → '0'..'9'
    rts


; -----------------------------------------------------------------
; Print byte as 0x prepended hex to UART
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            A - Byte to print
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SERIAL_PRINT_BYTE_HEX_A:
    sta ,-s       ; Save original byte (A), scratch reg

    ; Send '0'
    lda   #'0'
    jsr   SERIAL_PRINT_CHAR_A

    ; Send 'x'
    lda   #'x'
    jsr   SERIAL_PRINT_CHAR_A

    ; High nibble
    lda   ,s+      ; Load original byte (A) back
    jsr   SERIAL_PRINT_BYTE_A
    
    rts

; -----------------------------------------------------------------
; Print word as 0x prepended hex to UART
; -----------------------------------------------------------------
; SERIAL_PRINT_WORD_HEX_A
; input:            X - Word to print
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SERIAL_PRINT_WORD_HEX_A:
    pshs a,b 

    ; Send '0'
    lda   #'0'
    jsr   SERIAL_PRINT_CHAR_A

    ; Send 'x'
    lda   #'x'
    jsr   SERIAL_PRINT_CHAR_A

    tfr X,D
    jsr SERIAL_PRINT_BYTE_A

    tfr B,A
    jsr SERIAL_PRINT_BYTE_A

    ; Send ' '
    lda   #' '
    jsr   SERIAL_PRINT_CHAR_A

    ; Restore original register A and B (And set return address)
    puls a,b,pc


; -----------------------------------------------------------------
; Print a CRLF to UART
; -----------------------------------------------------------------
; SERIAL_PRINT_CRLF_A
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_PRINT_CRLF_A:
    lda #$0d
    jsr SERIAL_PRINT_CHAR_A
    lda #$0a
    jsr SERIAL_PRINT_CHAR_A
    rts


; -----------------------------------------------------------------
; Set C/T register to D
; -----------------------------------------------------------------
; SERIAL_SET_CT
; input:            D - Counter/Timer value
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SERIAL_SET_CT:
    sta CTPU
    stb CTPL
    rts


; -----------------------------------------------------------------
; Set C/T mode in ACR, 111 = Timer/16, 110 = Timer 011 = Counter/16
;  Other modes are not usable
; -----------------------------------------------------------------
; SERIAL_SET_CT_MODE
; input:            A - C/T mode 
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SERIAL_SET_CT_MODE:
    ora #$08        ; Set Baudrate table 2
    lsla
    lsla
    lsla
    lsla
    sta ACR
    rts


; -----------------------------------------------------------------
; Enable C/T IRQ in IMR
; -----------------------------------------------------------------
; SERIAL_ENABLE_CT_IRQ
; input:            None 
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_ENABLE_CT_IRQ:
    lda #$08
    sta IMR
    rts

; -----------------------------------------------------------------
; Start C/T 
; -----------------------------------------------------------------
; SERIAL_START_CT
; input:            None 
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_START_CT:
    lda STCR
    rts

; -----------------------------------------------------------------
; Stop C/T 
; -----------------------------------------------------------------
; SERIAL_STOP_CT
; input:            None 
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_STOP_CT:
    lda SPCR
    rts
