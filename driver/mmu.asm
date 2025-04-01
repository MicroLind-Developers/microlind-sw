; -----------------------------------------------------------------
; MMU Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;
;    org $FE10

MMU_BASE            EQU $f400

MMU_REG_0           EQU MMU_BASE+0
MMU_REG_1           EQU MMU_BASE+1
MMU_REG_2           EQU MMU_BASE+2
MMU_REG_3           EQU MMU_BASE+3

; -----------------------------------------------------------------
; MMU INIT - Must be called before any other function calls, will
;            preserve one nesting level, scary!
; input:            None
; output:           None
; clobbers:         A, W, STACK
; -----------------------------------------------------------------
MMU_INIT:
	pulsw 			; Store return address to W
	clra
	sta MMU_REG_3
	inca
    sta MMU_REG_0
    inca
    sta MMU_REG_1
    inca
    sta MMU_REG_2
    tfr W,PC		; Instead of rts, jump to return address stored in W

; -----------------------------------------------------------------
; SET MMU REGISTER
; input:            X = Register number (0-3)
;                   A = Address to set
; output:           None
; clobbers:         A, X
; -----------------------------------------------------------------
MMU_SET_REGISTER:
    sta x,MMU_REG_0
    rts

; -----------------------------------------------------------------
; GET MMU REGISTER
; input:            X = Register number (0-3)
; output:           A = Address in register
; clobbers:         A, X
; -----------------------------------------------------------------
MMU_GET_REGISTER:
    lda x,MMU_REG_0
    rts