; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;
    INCLUDE "memory.inc"
    org $FF00

HOOK_TRAP:
    

HOOK_FIRQ:
    ; jmp FIRQ_HANDLER

HOOK_IRQ:
    ; jmp IRQ_HANDLER

HOOK_SWI3:
HOOK_SWI2:
HOOK_SWI:
HOOK_NMI:
HOOK_RESET:
    jmp INIT

INIT:
    ; ---- CPU RESET ENTRY POINT ----
    ; Start by turning off interrupts
    orcc #$50
    
    ; Disable IRQ handler
    lda #$F0
    sta $f404       

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
	sta $f403
	clra
    sta $f400
    inca
    sta $f401
    inca
    sta $f402

    ; Set up the VALUE of the stack pointer
	lds #$E000

    ; Clear all registers
    jsr CLEAR_REGS

	; Initialize the serial port
	jsr SERIAL_INIT
    jsr SERIAL_START

	; Initialize the parallel port
	; jsr PARALLEL_INIT

    ; Initialize the led to Blue
    jsr SET_LED_BLUE

    ; Print the initialization message
    ; This is a message that will be printed to the serial port
    ldx #msg_init
    jsr SERIAL_PRINT_A

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


; ; ------------------------------------------------------------------
; ; Dummy subroutine for anything
; ; ------------------------------------------------------------------
; DUMMY_SUBROUTINE:
;     ; DO NOTHING!
;     rts

msg_init:
    fcc "Initializing µLind..."
    fcb 10,13,0

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

    ; org $FB00
; -----------------------------------------------------------------
; Rest of the code after this point
