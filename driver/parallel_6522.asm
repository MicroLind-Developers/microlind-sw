; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;   

;    org $FE00
PARALLEL_BASE           EQU $F410

ORB_22                  EQU PARALLEL_BASE
ORA_22                  EQU PARALLEL_BASE+1
DDRA_22                 EQU PARALLEL_BASE+2
DDRB_22                 EQU PARALLEL_BASE+3
ACR_22                  EQU PARALLEL_BASE+11
PCR_22                  EQU PARALLEL_BASE+12
IFR_22                  EQU PARALLEL_BASE+13
IER_22                  EQU PARALLEL_BASE+14

TIMER_1_IRQ             EQU $40

; -----------------------------------------------------------------
; PARALLEL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_INIT:
        ; Set all pins to input (DDR = 0)
        clr   DDRA_22      ; DDRA
        clr   DDRB_22      ; DDRB

        ; Clear Output Registers
        ; clr   ORA_22      ; ORA
        ; clr   ORB_22      ; ORB

        ; Set ACR to 0 — disables timers, shift reg, etc.
        clr   ACR_22     ; ACR

        ; Set PCR to 0 — makes CA1/CA2 and CB1/CB2 all input, no latching
        clr   PCR_22     ; PCR

        ; Clear interrupts (write with bit 7 = 0 to disable specific sources)
        lda   #$7F
        sta   IER_22     ; IER — disable all


; -----------------------------------------------------------------
; ENABLE INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_ENABLE_TIMER_INTERRUPT:
        lda IER_22
        ora #TIMER_1_IRQ        ; Enable timer 1 interrupt      
        sta IER_22
        rts

; -----------------------------------------------------------------
; DISABLE INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_DISABLE_TIMER_INTERRUPT:
        lda IER_22
        ldb #TIMER_1_IRQ
        eorr b,a                ; Disable timer 1 interrupt
        sta IER_22
        rts

; -----------------------------------------------------------------
; RESET INTERRUPT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_RESET_INTERRUPT:
        lda #TIMER_1_IRQ        ; Reset timer 1 interrupt
        sta IFR_22
        rts

; -----------------------------------------------------------------
; GET PORT A
; input:            None
; output:           A = Port A
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_GET_PORT_A:
        lda ORA_22
        rts


; -----------------------------------------------------------------
; GET JoyPort A
; input:            None
; output:           A = Port A, bit 0 = Up, bit 1 = Down, 
;                   bit 2 = Left, bit 3 = Right, bit 4 = Button
; clobbers:         A
; -----------------------------------------------------------------
READ_JOY1:
        lda   ORA_22
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
        lda   ORB_22
        eora  #$FF
        anda   #%00011111
        rts