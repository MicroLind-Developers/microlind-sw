; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;   
    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC

PARALLEL_ORB            EQU PARALLEL_BASE+0
PARALLEL_IRB            EQU PARALLEL_BASE+0
PARALLEL_ORA            EQU PARALLEL_BASE+1
PARALLEL_IRA            EQU PARALLEL_BASE+1
PARALLEL_DDRA           EQU PARALLEL_BASE+2
PARALLEL_DDRB           EQU PARALLEL_BASE+3
PARALLEL_T1CL           EQU PARALLEL_BASE+4
PARALLEL_T1CH           EQU PARALLEL_BASE+5
PARALLEL_T1LL           EQU PARALLEL_BASE+6
PARALLEL_T1LH           EQU PARALLEL_BASE+7
PARALLEL_T2CL           EQU PARALLEL_BASE+8
PARALLEL_T2CH           EQU PARALLEL_BASE+9
PARALLEL_SR             EQU PARALLEL_BASE+10
PARALLEL_ACR            EQU PARALLEL_BASE+11
PARALLEL_PCR            EQU PARALLEL_BASE+12
PARALLEL_IFR            EQU PARALLEL_BASE+13
PARALLEL_IER            EQU PARALLEL_BASE+14

TIMER_1_IRQ             EQU $40

SPI_TFR_READY           EQU $0000 ; Hold the SPI transfer ready flag


; -----------------------------------------------------------------
; PARALLEL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_INIT:
        ; Set all pins to input (DDR = 0)
        clr   PARALLEL_DDRA      ; DDRA
        clr   PARALLEL_DDRB      ; DDRB

        ; Clear Output Registers
        ; clr   ORA_22      ; ORA
        ; clr   ORB_22      ; ORB

        ; Set ACR to 0 — disables timers, shift reg, etc.
        clr   PARALLEL_ACR     ; ACR

        ; Set PCR to 0 — makes CA1/CA2 and CB1/CB2 all input, no latching
        clr   PARALLEL_PCR     ; PCR

        ; Clear interrupts (write with bit 7 = 0 to disable specific sources)
        lda   #$7F
        sta   PARALLEL_IER     ; IER — disable all


; -----------------------------------------------------------------
; ENABLE INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_ENABLE_TIMER_INTERRUPT:
        lda PARALLEL_IER
        ora #TIMER_1_IRQ        ; Enable timer 1 interrupt      
        sta PARALLEL_IER
        rts

; -----------------------------------------------------------------
; DISABLE INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_DISABLE_TIMER_INTERRUPT:
        lda PARALLEL_IER
        ldb #TIMER_1_IRQ
        eorr b,a                ; Disable timer 1 interrupt
        sta PARALLEL_IER
        rts


; -----------------------------------------------------------------
; ENABLE SPI OUTPUT
; This enables the shift register to output data to the CB2 pin
; at 1/2 of E clock speed
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_ENABLE_SPI_OUTPUT:
        lda PARALLEL_ACR
        ora #%00011100
        sta PARALLEL_ACR
        rts

; -----------------------------------------------------------------
; DISABLE SPI OUTPUT
; This disables the shift register from outputting data to the CB2 pin
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_DISABLE_SPI_OUTPUT:
        lda PARALLEL_ACR
        anda #%11100011
        sta PARALLEL_ACR
        rts

; -----------------------------------------------------------------
; ENABLE SPI INPUT
; This enables the shift register to input data from the CB2 pin
; using CB1 as the clock output
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_ENABLE_SPI_INPUT:
        lda PARALLEL_ACR
        ora #%00001100
        sta PARALLEL_ACR
        rts

; -----------------------------------------------------------------
; DISABLE SPI INPUT
; This disables the shift register from inputting data from the CB2 pin
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_DISABLE_SPI_INPUT:
        lda PARALLEL_ACR
        anda #%11110011
        sta PARALLEL_ACR
        rts

; -----------------------------------------------------------------
; RESET INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_RESET_INTERRUPT:
        lda #TIMER_1_IRQ        ; Reset timer 1 interrupt
        sta PARALLEL_IFR
        rts

; -----------------------------------------------------------------
; GET PORT A
; input:            None
; output:           A = Port A
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_GET_PORT_A:
        lda PARALLEL_ORA
        rts


; -----------------------------------------------------------------
; GET JoyPort A
; input:            None
; output:           A = Port A, bit 0 = Up, bit 1 = Down, 
;                   bit 2 = Left, bit 3 = Right, bit 4 = Button
; clobbers:         A
; -----------------------------------------------------------------
READ_JOY1:
        lda   PARALLEL_ORA
        eora  #$FF
        anda   #%00011111
        rts

; -----------------------------------------------------------------
; GET JoyPort B
; input:            None
; output:           A = Port B, bit 0 = Up, bit 1 = Down, 
;                   bit 2 = Left, bit 3 = Right, bit 4 = Button 
; clobbers:         A
; -----------------------------------------------------------------
READ_JOY2:
        lda   PARALLEL_ORB
        eora  #$FF
        anda   #%00011111
        rts

; -----------------------------------------------------------------
; START_SPI_DATA_STREAM (Blocking)
; input:            X = Data address to send from
;                   A = Data length to send
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
PARALLEL_START_SPI_DATA_STREAM:
        PSHS A,B,X        
        TFR A,B
        ; TODO: Add a ....

        ; Check if the SPI transfer is ready
        LDA SPI_TFR_READY
        BNE _SPI_TFR_RETRY

        LDE MAX_TFR_RETRIES+1
_SPI_TFR_RETRY:
        TFR E,B
        DECB
        BEQ _SPI_TFR_FAILED

_SEND_SPI_DATA_STREAM:
        ; Check if the SPI transfer is ready
        LDA SPI_TFR_READY
        BNE _SEND_SPI_DATA_STREAM

        LDA ,X+
        STA PARALLEL_SR
        DECB
        BNE _SEND_SPI_DATA_STREAM

_SPI_TFR_FAILED:
        LDB #$00

        PULS X,B,A,PC


PARALLEL_IRQ_HANDLER:
        ; TODO: Handle IRQ here

        ; Check if the IRQ is for the SPI transfer
        ; LDA #$01
        ; STA SPI_TFR_READY

        rti