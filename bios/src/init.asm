; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;
    INCLUDE "../include/memory.inc"
    org $FE00

HOOK_TRAP:
    jmp HANG    

HOOK_FIRQ:
    ; jmp FIRQ_HANDLER

HOOK_IRQ:
    ; jmp IRQ_HANDLER

HOOK_SWI3:
    ; jmp SYS_CALL_HANDLER
    
HOOK_SWI2:
HOOK_SWI:
    ; jmp PM_HANDLER
    
HOOK_NMI:
HOOK_RESET:
    jmp INIT

; -----------------------------------------------------------------
INIT:
    ; ---- CPU RESET ENTRY POINT ----
    ; Start by turning off interrupts
    orcc #$50
    
    ; Disable IRQ handler
    lda #$F0
    sta IRQ_BASE  

    ; Initialize the CPU to native mode
    ldmd #$01
    
    ; Initialize the MMU, must be done first, therefore we use the
    ; next label in X as the return address
    ; This sets up the MMU to use 3 16K banks and one 8k:
    ; 0x0000 - 0x3FFF = bank 0 -> 0x000000 
    ; 0x4000 - 0x7FFF = bank 1 -> 0x004000
    ; 0x8000 - 0xBFFF = bank 2 -> 0x008000
    ; 0xC000 - 0xDFFF = bank 3 -> 0x00C000 (0xE000 - 0xFFFF = ROM)
    lda #$1F
	sta MMU_REG_3
	clra
    sta MMU_REG_0
    inca
    sta MMU_REG_1
    inca
    sta MMU_REG_2

    ; Set up the VALUE of the stack pointer
	lds #$E000

    ; Clear all registers
    jsr CLEAR_REGS

    ; Select the console output backend before rendering any boot messages.
    ; VDC access is bounded, so an absent device cannot trap the BIOS here.
    clr CONFIG_VDC_PRESENT_FLAG
    jsr VDC_DETECT
    bcs _NO_VDC
    jsr VDC_INIT_TEXT
    bcs _NO_VDC
    lda #$01
    sta CONFIG_VDC_PRESENT_FLAG
    bra _CONSOLE_SELECTED

_NO_VDC:
    clr CONFIG_VDC_PRESENT_FLAG

_CONSOLE_SELECTED:
    ; Serial remains available for menu input and as the live fallback if an
    ; initialized VDC later fails. It is not selected for rendering while the
    ; VDC-present flag remains set.
    jsr SERIAL_INIT
    andcc #$FE                    ; SERIAL_START selects port A when C is clear.
    jsr SERIAL_START

	; Initialize the parallel port
	; jsr PARALLEL_INIT

    ; Initialize the led to Blue
    jsr SET_LED_GREEN

    ldx #msg_init
    jsr BIOS_CONSOLE_PRINT_A

    tst CONFIG_VDC_PRESENT_FLAG
    beq _REPORT_SERIAL_CONSOLE
    ldx #msg_vdc_present
    jsr BIOS_CONSOLE_PRINT_A
    bra _END_VDC

_REPORT_SERIAL_CONSOLE:
    ldx #msg_no_vdc
    jsr BIOS_CONSOLE_PRINT_A
_END_VDC:
    
    ; Detect installed 512 KiB RAM chips and store the count in config RAM.
    jsr CONFIG_DETECT_RAM_CHIPS
    ; Print detected RAM chip count
    ldx #msg_mem_detect
    jsr BIOS_CONSOLE_PRINT_A
    lda CONFIG_RAM_CHIP_COUNT
    adda #'0'
    jsr BIOS_CONSOLE_PRINT_CHAR_A
    ldx #msg_line_break
    jsr BIOS_CONSOLE_PRINT_A
    

    ; Initialize the CompactFlash card
    ; if carry clear, CF_OK in A, card is ready for use
    jsr CF_INIT
    ; if carry not clear jump to _NO_CF to skip
    bcs _NO_CF
    lda #$01
    sta CONFIG_CF_PRESENT_FLAG
    ldx #msg_cf_present
    jsr BIOS_CONSOLE_PRINT_A
    jmp _END_CF

_NO_CF:
    clr CONFIG_CF_PRESENT_FLAG
    ldx #msg_no_cf
    jsr BIOS_CONSOLE_PRINT_A
_END_CF:

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
; Dummy subroutine for anything
; -----------------------------------------------------------------
; DUMMY_SUBROUTINE:
;     ; DO NOTHING!
;     rts

msg_init:
    fcc "Initializing microLind..."
    fcb 10,13,0

VDC_FONT_LOADING_MESSAGE:
    fcn "FONT..."

msg_mem_detect:
    fcc "Detected RAM chips: "
    fcb 0
msg_vdc_present:
    fcc " * MOS 8568 VDC detected; BIOS menu output enabled."
    fcb 10,13,0

msg_no_vdc:
    fcc " * No MOS 8568 VDC detected; using serial menu output."
    fcb 10,13,0

msg_cf_present:
    fcc " * CompactFlash card detected and initialized."
    fcb 10,13,0

msg_no_cf:
    fcc " * No CompactFlash card detected or initialization failed."   
    fcb 10,13,0

msg_line_break:
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
