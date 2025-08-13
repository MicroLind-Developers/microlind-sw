; -----------------------------------------------------------------
; xr88c92 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;
    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC
    IFNDEF MEMORY_INC
        include "../include/memory.inc"
    ENDC

LED_ALL             EQU $07 ; Red, Green, Blue
LED_RED             EQU $04 ; Red
LED_GREEN           EQU $02 ; Green
LED_BLUE            EQU $01 ; Blue
LED_OFF             EQU $00 ; Off

SERIAL_TIMER_IRQ_JUMP_VECTOR    EQU SERIAL_DRIVER_RAM_START      ; 2 byte address for jump vector when timer irq is triggered
SERIAL_RXA_IRQ_JUMP_VECTOR      EQU SERIAL_TIMER_IRQ_JUMP_VECTOR+2  ; 2 byte address for jump vector when RXA irq is triggered
SERIAL_TXA_IRQ_JUMP_VECTOR      EQU SERIAL_RXA_IRQ_JUMP_VECTOR+2    ; 2 byte address for jump vector when TXA irq is triggered
SERIAL_ISR_TEMP                 EQU SERIAL_TXA_IRQ_JUMP_VECTOR+2    ; 1 byte for ISR temp storage


; COMMON REGISTERS (Direct)
; Port A
SERIAL_MRA              EQU SERIAL_BASE+0   ; Mode Register A 0 - 2
SERIAL_SRA              EQU SERIAL_BASE+1   ; Status Register A
SERIAL_RXA              EQU SERIAL_BASE+3   ; Receive Data Register A
SERIAL_TXA              EQU SERIAL_BASE+3   ; Transmit Data Register A
SERIAL_CRA              EQU SERIAL_BASE+2   ; Command Register A
SERIAL_CSRA             EQU SERIAL_BASE+1   ; Clock Select Register A

;Port B
SERIAL_MRB              EQU SERIAL_BASE+8   ; Mode Register B 0 - 2
SERIAL_SRB              EQU SERIAL_BASE+9   ; Status Register B
SERIAL_RXB              EQU SERIAL_BASE+11  ; Receive Data Register B
SERIAL_TXB              EQU SERIAL_BASE+11  ; Transmit Data Register B
SERIAL_CRB              EQU SERIAL_BASE+10  ; Command Register B
SERIAL_CSRB             EQU SERIAL_BASE+9   ; Clock Select Register B

;Common
SERIAL_ACR              EQU SERIAL_BASE+4   ; Auxilliary Control Register
SERIAL_ISR              EQU SERIAL_BASE+5   ; Interrupt Status Register   
SERIAL_IMR              EQU SERIAL_BASE+5   ; Interrupt Mask Register
SERIAL_IPCR             EQU SERIAL_BASE+4   ; Input Port Change Register 
SERIAL_OPCR             EQU SERIAL_BASE+13  ; Output Port Configuration Register
SERIAL_IPR              EQU SERIAL_BASE+13  ; Input Port Register (Bit 0-6)
SERIAL_SPCR             EQU SERIAL_BASE+15  ; Stop Counter/Timer Register
SERIAL_ROPR             EQU SERIAL_BASE+15  ; Reset Output Port Register
SERIAL_SOPR             EQU SERIAL_BASE+14  ; Set Output Port Register
SERIAL_STCR             EQU SERIAL_BASE+14  ; Start Counter/Timer Register
SERIAL_GPR              EQU SERIAL_BASE+12  ; General Purpose Register
SERIAL_CUR              EQU SERIAL_BASE+6   ; Counter/Timer Upper Register
SERIAL_CLR              EQU SERIAL_BASE+7   ; Counter/Timer Lower Register
SERIAL_CTPU             EQU SERIAL_BASE+6   ; Counter/Timer Preset Upper Register
SERIAL_CTPL             EQU SERIAL_BASE+7   ; Counter/Timer Preset Lower Register


; -----------------------------------------------------------------
; SERIAL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_INIT:
        lda #$ba        ;Disable transmiters and recivers, and reset MR pointers to MR0
        sta SERIAL_CRA
        sta SERIAL_CRB
        lda #$20        ;Reset recivers
        sta SERIAL_CRA
        sta SERIAL_CRB
        lda #$30        ;Reset transmiters
        sta SERIAL_CRA
        sta SERIAL_CRB
        lda #$40        ;Reset error status
        sta SERIAL_CRA
        sta SERIAL_CRB
        lda #$01        ;MRA0: Select baud rate table and FIFO triger levels
        sta SERIAL_MRA
        sta SERIAL_MRB
        lda #$93        ;MRA1: Select formating, no parity and 8 data bits, and auto RX RTS control
        sta SERIAL_MRA
        sta SERIAL_MRB
        lda #$17        ;MRA2: Select loopback mode, auto CTS, and 1 stop bit length
        sta SERIAL_MRA
        sta SERIAL_MRB
        lda #$cc        ;Select baud rate 115200
        sta SERIAL_CSRA
        sta SERIAL_CSRB
        lda #$80        ;Select baud rate table, C/T mode, and IPCR interupts
        sta SERIAL_ACR
        clra
        sta SERIAL_IMR         ;Disable all interupts
        sta SERIAL_OPCR        ;Set output ports 2-7 to manual control
        lda SERIAL_SPCR        ;Stop the C/T

; ldd DUMMY_SUBROUTINE ;Load the address of the dummy subroutine into D
; std SERIAL_TIMER_IRQ_JUMP_VECTOR ;Initialize the jump vector for the timer interupt
; std SERIAL_RXA_IRQ_JUMP_VECTOR ;Initialize the jump vector for the rxa interupt
; std SERIAL_TXA_IRQ_JUMP_VECTOR ;Initialize the jump vector for the txa interupt
        
        rts

; -----------------------------------------------------------------
; SERIAL_START
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SERIAL_START:
        lda #$05
        bcs SER_START1 
        sta SERIAL_CRA
        rts
SER_START1:
        sta SERIAL_CRB
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
        ldb SERIAL_SRA
        andb #$04
        beq PRT0
        sta SERIAL_TXA
        
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
        ldb SERIAL_SRA
        andb #$04
        beq PRTB0
        sta SERIAL_TXA
        puls b,pc	; Return from subroutine with character in A


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
        lda SERIAL_SRA
        anda #$01
        beq INP0
        lda SERIAL_RXA
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
        ; jmp HANG

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
; info:             230400 is the number of ticks per second in Timer/16 mode
; -----------------------------------------------------------------
SERIAL_SET_CT:
    sta SERIAL_CTPU
    stb SERIAL_CTPL
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
    sta SERIAL_ACR
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
    sta SERIAL_IMR
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
    lda SERIAL_STCR
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
    lda SERIAL_SPCR
    rts


; POWER_LED is controlled by the serial port

; -----------------------------------------------------------------
; SET_LED
; input:            A = LED state, 0 = OFF, 1 = RED, 2 = GREEN, 
;                   3 = RED+GREEN, 4 = BLUE, 5 = RED+BLUE, 6 = GREEN+BLUE,
;                   7 = RED+GREEN+BLUE
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SET_LED:
    jsr SET_LED_OFF
    ; If A is 0, we are done
    cmpa #$00
    beq _DONE

    ; Else set the LED
    sta SERIAL_OPCR

_DONE:
    rts

; -----------------------------------------------------------------
; SET_LED_RED
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_RED:
    jsr SET_LED_OFF
    lda #LED_RED
    sta SERIAL_OPCR
    rts

; -----------------------------------------------------------------
; SET_LED_GREEN
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_GREEN:
    jsr SET_LED_OFF
    lda #LED_GREEN
    sta SERIAL_OPCR
    rts

; -----------------------------------------------------------------
; SET_LED_BLUE
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_BLUE:
    jsr SET_LED_OFF
    lda #LED_BLUE
    sta SERIAL_OPCR
    rts

; -----------------------------------------------------------------
; SET_LED_OFF
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_OFF:
    lda #LED_OFF
    sta SERIAL_OPCR
    rts

; -----------------------------------------------------------------
; Set the serial interrupt service routine jump vector
; -----------------------------------------------------------------
; SET_SERIAL_xxx_IRQ_JUMP_VECTOR
; input:            D = 2 byte address of the interrupt service routine
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
SET_SERIAL_TIMER_IRQ_JUMP_VECTOR:
    ; Set the interrupt vector to the timer interrupt handler
    std SERIAL_TIMER_IRQ_JUMP_VECTOR
    rts

SET_SERIAL_RXA_IRQ_JUMP_VECTOR:
    ; Set the interrupt vector to the serial receive interrupt handler
    std SERIAL_RXA_IRQ_JUMP_VECTOR
    rts

SET_SERIAL_TXA_IRQ_JUMP_VECTOR:
    ; Set the interrupt vector to the serial transmit interrupt handler
    std SERIAL_TXA_IRQ_JUMP_VECTOR
    rts

; -----------------------------------------------------------------
; Serial interrupt handlers
; -----------------------------------------------------------------
; SERIAL_IRQ_HANDLER
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
; SERIAL_IRQ_HANDLER:
;    lda ISR
;    sta SERIAL_ISR_TEMP
;    tsta #$08
;    bne _TIMER_READY

; _RTS_TIMER:
;     lda SERIAL_ISR_TEMP
;     tsta #$02
;     bne _RXA_FULL

; _RTS_RXA:
;     lda SERIAL_ISR_TEMP
;     tsta #$01
;     bne _TXA_EMPTY

; _RTS_TXA:
;     rti

; _TIMER_READY:
;     ; Timer interrupt
;     jsr SERIAL_STOP_CT
;     jsr [SERIAL_TIMER_IRQ_JUMP_VECTOR]
;     bra _RTS_TIMER

; _RXA_FULL:
;     ;TODO: RXA full interrupt handling
;     jsr [SERIAL_RXA_IRQ_JUMP_VECTOR]
;     bra _RTS_RXA

; _TXA_EMPTY:
;     ;TODO: TXA empty interrupt handling
;     jsr [SERIAL_TXA_IRQ_JUMP_VECTOR]
;     bra _RTS_TXA
