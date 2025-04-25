; -----------------------------------------------------------------
; PS/2 Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;   
    org $FE20
PS2_BASE           EQU $f406

PS2_KBD             EQU PS2_BASE+0
PS2_MOUSE           EQU PS2_BASE+1

; -----------------------------------------------------------------
; PS/2 INIT
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
PS2_INIT:
        rts

; -----------------------------------------------------------------
; KBD READ
; input:            None
; output:           A = KBD data
; clobbers:         A
; -----------------------------------------------------------------
PS2_READ_KBD:
        lda PS2_KBD
        rts

; -----------------------------------------------------------------
; MOUSE READ
; input:            None
; output:           A = MOUSE data
; clobbers:         A
; -----------------------------------------------------------------
PS2_READ_MOUSE:
        lda PS2_MOUSE
        rts