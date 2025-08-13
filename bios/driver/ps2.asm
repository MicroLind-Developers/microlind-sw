; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;   
    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC

PS2_KBD             EQU PS2_BASE+0 ; Keypress / Kbd command
PS2_MOUSE           EQU PS2_BASE+1 ; Mouse

; -----------------------------------------------------------------
; PS/2 INIT
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
PS2_INIT:
    ; TODO: Initialize PS/2 controller
    ; TODO: Set up interrupt handler
    ; TODO: Set up keyboard buffer
    ; TODO: Set up mouse buffer
    rts

; -----------------------------------------------------------------
; PS2_GET_KEYPRESS
; input:            None
; output:           A = KBD data
; clobbers:         A
; -----------------------------------------------------------------
PS2_GET_KEYPRESS:
    ; TODO: Check if there is a keypress in the buffer
    ; TODO: If there is, return it
    ; TODO: If there is not, return 0
    lda #$00
    rts

; -----------------------------------------------------------------
; PS2_GET_MOUSE_DATA
; input:            None
; output:           A = MOUSE data
; clobbers:         A
; -----------------------------------------------------------------
PS2_GET_MOUSE_DATA:
    ; TODO: Check if there is a mouse data in the buffer
    ; TODO: If there is, return it
    ; TODO: If there is not, return 0
    lda #$00
    rts

; -----------------------------------------------------------------
; KBD_ISR
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
PS2_KBD_ISR:
    lda PS2_KBD
    jsr PS2_STORE_KEYPRESS_TO_BUFFER
    ; TODO: Check if ps2 controller dropped irq, ie. the buffer is empty so no more reads are needed
    bne PS2_KBD_ISR

    rti


; -----------------------------------------------------------------
; PS2_STORE_KEYPRESS_TO_BUFFER
; input:            A = KBD data
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
PS2_STORE_KEYPRESS_TO_BUFFER:
    ; TODO: Store the keypress in the buffer
    rts