; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;

; Setup the default stack pointer to $1000
STACK EQU $1000

    org $FF00
HOOK_TRAP:
    jmp HANG
HOOK_SWI3:
HOOK_SWI2:
HOOK_SWI:
HOOK_FIRQ:
HOOK_IRQ:
HOOK_NMI:
HOOK_RESET:

INIT:
    ; ---- CPU RESET ENTRY POINT ----
    ; Start by turning off interrupts
    orcc #$50       ;Turn off interupts

    ; Initialize the CPU to native mode
    ldmd #$01
    
    ; Initialize the MMU, must be done first, therefore we use the
    ; next label in X as the return address
    ; This sets up the MMU to use 3 16K banks and one 8k:
    ; 0x0000 - 0x3FFF = bank 0 -> 0x000000 
    ; 0x4000 - 0x7FFF = bank 1 -> 0x004000
    ; 0x8000 - 0xBFFF = bank 2 -> 0x008000
    ; 0xC000 - 0xDFFF = bank 3 -> 0x00C000 (0xE000 - 0xFFFF = ROM)
    lda #$19
	sta MMU_REG_3
	clra
    sta MMU_REG_0
    inca
    sta MMU_REG_1
    inca
    sta MMU_REG_2

    ; Set up the stack
	lds #STACK

    jsr CLEAR_REGS

	; Initialize the serial port
	jsr SERIAL_INIT
    jsr SERIAL_START

    jsr MEMORY_DUMP_BANK_SETTINGS

	; Initialize the parallel port
	jsr PARALLEL_INIT

	; Initialize the IRQ
	jsr IRQ_INIT

    ; Initialize the led to off
    jsr SET_LED_GREEN

    lbra _START	

; -----------------------------------------------------------------
; Infinite loop, used for debugging
; input:            None
; output:           None
; -----------------------------------------------------------------
HANG:
    bra HANG

; -----------------------------------------------------------------
; Clear registers
; input:            None
; output:           None
; clobbers:         A, B, E, F, D, W, X, Y, U, V, Q, DP, CC
; -----------------------------------------------------------------
CLEAR_REGS:
    ldq     #$00000000
    tfr     a,dp
    tfr     d,x
    tfr     d,y
    tfr     d,u
    tfr     d,v
    rts

; -----------------------------------------------------------------
; Vector table for the CPU
; -----------------------------------------------------------------
    org $FFF0

V_TRAP: fdb HOOK_TRAP
V_SWI3: fdb HOOK_SWI3
V_SWI2: fdb HOOK_SWI2
V_FIRQ: fdb HOOK_FIRQ
V_IRQ: fdb HOOK_IRQ
V_SWI: fdb HOOK_SWI
V_NMI: fdb HOOK_NMI
V_RESET: fdb HOOK_RESET

    org $FB00
; -----------------------------------------------------------------
; Rest of the code after this point