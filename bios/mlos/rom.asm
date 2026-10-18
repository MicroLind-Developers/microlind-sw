; Standalone S00-S02 ROM harness. Not the S03 MLFS bootloader.
    include "layout.inc"
    include "syscalls.inc"
    include "hardware.inc"
    org $E000
    include "entry.asm"
    include "uart.asm"

; Function: rom_reset — deterministic stackless MMU setup, native mode, bootstrap.
; Inputs: qualified reset has unlocked gate. Outputs: executes core; no return.
; Clobbers: all. Context: reset, IRQ/FIRQ masked. No RAM use until MMU3=1.
; Side effects: copies embedded development images; no CF reads/writes.
rom_reset:
    orcc #$50
    ldmd #1
    lda #COMMON_FRAME
    sta MMU3
    lda #CORE_FRAME
    sta MMU0
    lda #DISCARD_FRAME
    sta MMU1
    sta MMU2
    lds #KERNEL_STACK
    ldx #$C000
rr_clear:
    clr ,x+
    cmpx #COMMON_USED_END
    blo rr_clear
    ldx #core_payload
    ldy #0
rr_core:
    lda ,x+
    sta ,y+
    cmpx #core_payload_end
    blo rr_core
    lda #APP_FRAME
    sta MMU1
    ldx #app_payload
    ldy #$4000+APP_START
rr_app:
    lda ,x+
    sta ,y+
    cmpx #app_payload_end
    blo rr_app
    lda #DISCARD_FRAME
    sta MMU1
    clra
    tfr a,dp
    lda #$F0
    sta IRQ_CONTROL
    jsr rom_uart_init
    jmp CORE_START

; Function: rom_start_app — final development bootstrap, no return.
; Inputs: kernel initialized saved application maps. Outputs: app S/maps/locked.
; Clobbers: all application registers initialized deterministically. No stack use.
rom_start_app:
    ldd #0
    tfr a,dp
    tfr d,x
    tfr d,y
    tfr d,u
    tfr d,v
    ldw #0
    lda PROCESS_MAP
    sta MMU0
    lda PROCESS_MAP+1
    sta MMU1
    lda PROCESS_MAP+2
    sta MMU2
    lds #APP_STACK
    sta GATE
    clra
    clrb
    andcc #$AF                     ; IRQ enabled; FIRQ remains masked/unused.
    jmp APP_START

core_payload:
    includebin "core.raw"
core_payload_end:
app_payload:
    includebin "app.raw"
app_payload_end:
ROM_LOWER_END equ *
    ifgt ROM_LOWER_END-$F400
    error "MLOS lower ROM overlaps I/O overlay"
    endc

; Fixed ROM ABI for the development core. Kernel may call only these slots.
    org $F800
    jmp rom_start_app              ; ROM_START_APP
    jmp rom_panic                  ; ROM_PANIC
    jmp rom_putc                   ; ROM_PUTC
    jmp rom_nested_test            ; ROM_NESTED_TEST
    jmp >CORE_DISPATCH          ; ROM_CORE_CALL (bank0 only)
    jmp rom_timer_enable           ; ROM_TIMER_ENABLE
    org $FFF0
    fdb rom_trap,rom_unsupported,rom_unsupported,rom_firq
    fdb rom_irq,rom_swi,rom_nmi,rom_reset
