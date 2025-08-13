; -----------------------------------------------------------------
; MMU Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;

    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC

MMU_REG_0           EQU MMU_BASE+0
MMU_REG_1           EQU MMU_BASE+1
MMU_REG_2           EQU MMU_BASE+2
MMU_REG_3           EQU MMU_BASE+3

; -----------------------------------------------------------------
; MMU INIT - Must be called before any other function calls, return 
; address in X
; input:            X
; output:           None
; clobbers:         A, X
; -----------------------------------------------------------------
MMU_INIT:
	clra
	sta MMU_REG_3
	inca
    sta MMU_REG_0
    inca
    sta MMU_REG_1
    inca
    sta MMU_REG_2
    jmp ,X

; -----------------------------------------------------------------
; SET MMU REGISTER
; input:            X = Register number (0-3)
;                   A = Address to set
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
MMU_SET_REGISTER:
    sta MMU_REG_0,X
    rts

; Helper for individual registers
MMU_SET_REGISTER_0:
    sta MMU_REG_0
    rts

MMU_SET_REGISTER_1:
    sta MMU_REG_1
    rts

MMU_SET_REGISTER_2:
    sta MMU_REG_2
    rts

MMU_SET_REGISTER_3:
    sta MMU_REG_3
    rts

; -----------------------------------------------------------------
; GET MMU REGISTER
; input:            X = Register number (0-3)
; output:           A = Address in register
; clobbers:         A
; -----------------------------------------------------------------
MMU_GET_REGISTER:
    lda MMU_REG_0,X
    rts

MMU_GET_REGISTER_0:
    lda MMU_REG_0
    rts

MMU_GET_REGISTER_1:
    lda MMU_REG_1
    rts

MMU_GET_REGISTER_2:
    lda MMU_REG_2
    rts

MMU_GET_REGISTER_3:
    lda MMU_REG_3
    rts