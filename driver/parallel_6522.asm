; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;   

;    org $FE00
PARALLEL_BASE           EQU $f410

ORB_22                  EQU PARALLEL_BASE
ORA_22                  EQU PARALLEL_BASE+$01
DDRA_22                 EQU PARALLEL_BASE+$02
DDRB_22                 EQU PARALLEL_BASE+$03
ACR_22                  EQU PARALLEL_BASE+$0b
PCR_22                  EQU PARALLEL_BASE+$0c
IFR_22                  EQU PARALLEL_BASE+$0d
IER_22                  EQU PARALLEL_BASE+$0e

TIMER_1_IRQ             EQU $40

; -----------------------------------------------------------------
; PARALLEL INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
PARALLEL_INIT:
        clr DDRA_22
        clr DDRB_22
        lda #$7f
        sta IER_22
        rts

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