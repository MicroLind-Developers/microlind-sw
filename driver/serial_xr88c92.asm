; -----------------------------------------------------------------
; xr88c92 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;

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
        lda #$b0 ;lda with "set MR pointer to MR0" command
        sta CRA
        sta CRB
        lda #$01 ;lda data to be stoard in MR0
        sta MRA
        sta MRB
        lda #$13 ;lda data to be stoard in MR1
        sta MRA
        sta MRB
        lda #$07 ;lda data to be stoard in MR2
        sta MRA
        sta MRB
        lda #$cc ;set the baudrates of the reciver and transmiter
        sta CSRA
        sta CSRB
        lda #$80 ;selects baudrate set 2
        sta ACR
        clr IMR  ;turn of all interupts
        clr OPCR ;turn of automated output port control
        lda SPCR ;stop C/T
        rts

; -----------------------------------------------------------------
; SERIAL PRINT
; input:            X - Points to /0 terminated string
; output:           None
; clobbers:         A, B, X
; -----------------------------------------------------------------
PRT0:
        ldb SRA
        andb #$04
        beq PRT0
        sta TXA
        
SERIAL_PRINT_A:
        lda ,x+
        bne PRT0
        rts

; -----------------------------------------------------------------
; Input string from UART (blocking)
; Exit: String in buffer X
; -----------------------------------------------------------------
; SERIAL INPUT (blocking)
; input:            X - Buffer address, Y - Buffer size
; output:           None
; clobbers:         A, B, X, Y, W
; -----------------------------------------------------------------
SER_INPUT:
        cmpy #$0000
        beq INP4
        addr x,y
        tfr x,w
INP3:
        tfr w,x
        lda #$0d
        jsr SER_ECHO
        lda #'>'
        bra INP2
INP4:
        ldx err_buferSize0
        jmp ERR
INP1:
        leax -1,x
        cmpr w,x
        bmi INP3
INP2:
        jsr SER_ECHO
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
        jsr SER_ECHO
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

err_buferSize0: fcn '?illegal buffer size exception'

; -----------------------------------------------------------------
; Print byte as hex to UART
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            A - Byte to print
; output:           None
; clobbers:         A, B
; -----------------------------------------------------------------
SERIAL_PRBYTE:
        pshu a
        lsra
        lsra
        lsra
        lsra
        jsr PRB0
        pulu a
PRB0:
        anda #$0f
        ora #'0'
        cmpa #$3a
        bcs SER_ECHO
        adda #$07

; -----------------------------------------------------------------
; Print a character to UART
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            A - character to print
; output:           None
; clobbers:         B
; -----------------------------------------------------------------
SER_ECHO:
        ldb SRA
        andb #$04
        beq SER_ECHO
        sta TXA
        rts

; -----------------------------------------------------------------
; Trap handler
; -----------------------------------------------------------------
; SERIAL_PRBYTE
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
; Its a 
TRAP:
        bitmd #$80
        bne TRP0
        bitmd #$40
        bne TRP1
        lda #'G'
        jsr SER_ECHO
        bra HANG
TRP0:
        lda #'D'
        jsr SER_ECHO
        bra HANG
TRP1:
        lda #'I'
        jsr SER_ECHO

