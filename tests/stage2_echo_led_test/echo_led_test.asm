    org $FFF0

V_TRAP: fdb HOOK_TRAP
V_SWI3: fdb HOOK_SWI3
V_SWI2: fdb HOOK_SWI2
V_FIRQ: fdb HOOK_FIRQ
V_IRQ: fdb HOOK_IRQ
V_SWI: fdb HOOK_SWI
V_NMI: fdb HOOK_NMI
V_RESET: fdb HOOK_RESET

    org $FF00

HOOK_TRAP:
HOOK_FIRQ:
HOOK_IRQ:
HOOK_SWI3:
HOOK_SWI2:
HOOK_SWI:
HOOK_NMI:
HOOK_RESET:

INIT:
    ; Initialize the CPU to native mode
    ldmd #$01

    ; Start by turning off interrupts
    orcc #$50
    
    ; Initialize the MMU, must be done first, therefore we use the
    lda #$19
	sta $f403
	clra
    sta $f400
    inca
    sta $f401
    inca
    sta $f402

    ; Set up the stack
	lds #$E000

    ; Set LED to BLUE
    lda #$01
    sta $F405

    ; Init serial and start it
    jsr SERIAL_INIT
    jsr SERIAL_START

loop:
    ldx #msg_init
    jsr SERIAL_PRINT_A
    bra loop

HANG:
    bra HANG


msg_init:
    fcc "Initializing µLind..."
    fcb 10,13,0

    org $F000