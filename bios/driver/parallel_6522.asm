; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;   
    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC
    IFNDEF MEMORY_INC
        include "../include/memory.inc"
    ENDC

PARALLEL_ORB            EQU PARALLEL_BASE+0
PARALLEL_IRB            EQU PARALLEL_BASE+0
PARALLEL_ORA            EQU PARALLEL_BASE+1
PARALLEL_IRA            EQU PARALLEL_BASE+1
PARALLEL_DDRB           EQU PARALLEL_BASE+2
PARALLEL_DDRA           EQU PARALLEL_BASE+3
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
TIMER_2_IRQ             EQU $20

; The VIA is clocked from the 2 MHz system clock.  Timer 1 toggles PB7 on
; every timeout, so its reload value is VIA_CLOCK_HZ / (2 * frequency_hz).
PARALLEL_VIA_CLOCK_HZ           EQU 2000000
PARALLEL_TIMER_TICKS_PER_MS     EQU PARALLEL_VIA_CLOCK_HZ/1000
PARALLEL_BEEP_T1_ACR_BITS       EQU $C0    ; T1 free-run + PB7 timer output
PARALLEL_BEEP_PB7               EQU $80

SPI_TFR_READY           EQU $0000 ; Hold the SPI transfer ready flag
MAX_TFR_RETRIES         EQU $FF


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
        rts


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
; PARALLEL_BEEP (blocking)
; Drive the PC speaker connected to VIA PB7 for a requested time.
;
; input:            X = duration in milliseconds
;                   D = frequency in hertz
; output:           None
; clobbers:         A, B, D, W, X, Y, CC
;
; Timer 1 is put in free-running mode with its PB7 output enabled. Timer 2
; is used as a polled 1 ms one-shot, so the duration does not depend on an
; instruction-counted delay loop.  The routine is blocking and temporarily
; owns both VIA timers. It restores ACR, ORB, DDRB, and Timer 1/2 interrupt
; enables before returning.
;
; The valid frequency range is 16 Hz through 32767 Hz. Values below 16 Hz
; are clamped to 16 Hz; values above 32767 Hz are clamped to 32767 Hz. A zero
; duration or frequency is a no-op.
; -----------------------------------------------------------------
PARALLEL_BEEP:
        cmpx    #$0000
        lbeq    _PARALLEL_BEEP_DONE
        tstd
        lbeq    _PARALLEL_BEEP_DONE

        tfr     x,y                     ; retain duration for the ms loop
        pshs    d                       ; [4,s] frequency (after saved state)
        lda     PARALLEL_ACR
        pshs    a                       ; [3,s]
        lda     PARALLEL_DDRB
        pshs    a                       ; [2,s]
        lda     PARALLEL_ORB
        pshs    a                       ; [1,s]
        lda     PARALLEL_IER
        pshs    a                       ; [0,s]

        ; DIVQ is signed. Keep both its divisor and quotient positive while
        ; still covering the full 16-bit timer reload range.
        ldd     4,s
        cmpd    #16
        bhs     _PARALLEL_BEEP_MIN_OK
        ldd     #16
        std     4,s
_PARALLEL_BEEP_MIN_OK:
        cmpd    #$7FFF
        bls     _PARALLEL_BEEP_MAX_OK
        ldd     #$7FFF
        std     4,s
_PARALLEL_BEEP_MAX_OK:
        cmpd    #31
        bhs     _PARALLEL_BEEP_DIVIDE_FULL

        ; For 16..30 Hz, halve the dividend and double the quotient. This
        ; avoids DIVQ's signed 16-bit quotient overflow at low frequencies.
        ldq     #PARALLEL_VIA_CLOCK_HZ/4
        divq    4,s
        tfr     w,d
        lsld
        bra     _PARALLEL_BEEP_PERIOD_READY

_PARALLEL_BEEP_DIVIDE_FULL:
        ldq     #PARALLEL_VIA_CLOCK_HZ/2
        divq    4,s
        tfr     w,d

_PARALLEL_BEEP_PERIOD_READY:
        tfr     d,w                     ; preserve reload while configuring VIA
        ; Keep any existing non-Timer-1 ACR configuration (for example SPI).
        lda     PARALLEL_ACR
        anda    #$3F
        ora     #PARALLEL_BEEP_T1_ACR_BITS
        sta     PARALLEL_ACR
        lda     PARALLEL_DDRB
        ora     #PARALLEL_BEEP_PB7
        sta     PARALLEL_DDRB

        ; Do not let the timer flags invoke the IRQ handler while polling.
        lda     #TIMER_1_IRQ
        sta     PARALLEL_IER
        lda     #TIMER_2_IRQ
        sta     PARALLEL_IER
        lda     #TIMER_1_IRQ+TIMER_2_IRQ
        sta     PARALLEL_IFR

        ; Writing T1CH starts Timer 1. PB7 then toggles every half-period.
        tfr     w,d
        stb     PARALLEL_T1CL
        sta     PARALLEL_T1CH

_PARALLEL_BEEP_MS_LOOP:
        ldd     #PARALLEL_TIMER_TICKS_PER_MS
        stb     PARALLEL_T2CL
        sta     PARALLEL_T2CH
_PARALLEL_BEEP_WAIT_MS:
        lda     PARALLEL_IFR
        bita    #TIMER_2_IRQ
        beq     _PARALLEL_BEEP_WAIT_MS
        lda     #TIMER_2_IRQ
        sta     PARALLEL_IFR
        leay    -1,y
        bne     _PARALLEL_BEEP_MS_LOOP

        ; Stop the PB7 timer output before restoring the port state.
        lda     #TIMER_1_IRQ+TIMER_2_IRQ
        sta     PARALLEL_IFR
        lda     3,s
        sta     PARALLEL_ACR
        lda     1,s
        sta     PARALLEL_ORB
        lda     2,s
        sta     PARALLEL_DDRB

        ; Restore only the two IER bits this routine temporarily cleared.
        lda     0,s
        bita    #TIMER_1_IRQ
        beq     _PARALLEL_BEEP_T2_IER
        lda     #$80+TIMER_1_IRQ
        sta     PARALLEL_IER
_PARALLEL_BEEP_T2_IER:
        lda     0,s
        bita    #TIMER_2_IRQ
        beq     _PARALLEL_BEEP_RESTORE_DONE
        lda     #$80+TIMER_2_IRQ
        sta     PARALLEL_IER
_PARALLEL_BEEP_RESTORE_DONE:
        leas    6,s
_PARALLEL_BEEP_DONE:
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

        LDE #MAX_TFR_RETRIES
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
