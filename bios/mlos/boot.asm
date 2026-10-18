MLOS_RUNTIME equ 1
    include "layout.inc"
    include "syscalls.inc"
    include "hardware.inc"
    include "images.inc"
    org $E000
    include "entry.asm"
    include "uart.asm"
    include "storage.asm"
    include "loader.asm"
    include "boot_feedback.asm"

; Function: rom_reset. Inputs qualified reset/native-capable CPU. Outputs:
; validated CF kernel entry with X=BOOT_INFO; never executes an invalid image.
; Clobbers all; stackless first mappings, bounded ROM diagnostic on error.
rom_reset:
    orcc #$50
    ; Stackless, before RAM clearing or storage: make power visible immediately.
    clra
    sta UART_OPCR
    lda #POWER_LED_ALL
    sta UART_LED_RESET
    lda #POWER_LED_GREEN
    sta UART_LED_SET
    ldmd #1
    lda #1
    sta MMU3
    clra
    sta MMU0
    lda #2
    sta MMU1
    sta MMU2
    lds #KERNEL_STACK
    lda #$F0
    sta IRQ_CONTROL
    jsr rom_uart_init
    ldb #BOOT_MSG_CLEAR
    jsr rom_boot_status
    ldx #$C000
rboot_clear:
    clr ,x+
    cmpx #$E000
    blo rboot_clear
    clra
    tfr a,dp
    ; UART is already live. Restore shadows erased with common RAM; hardware
    ; ACR/IMR still hold these values. All earlier calls returned before clear.
    lda #$80
    sta UART_ACR_SHADOW
    clr UART_IMR_SHADOW
    ldb #BOOT_MSG_CF
    jsr rom_boot_status
    lda #1
    sta BOOT_STATUS
    jsr boot_identify
    bcs rboot_error
    lda #2
    sta BOOT_STATUS
    ldb #BOOT_MSG_ROOT
    jsr rom_boot_status
    jsr boot_open_root
    bcs rboot_error
    lda #3
    sta BOOT_STATUS
    ldb #BOOT_MSG_KERNEL
    jsr rom_boot_status
    jsr boot_kernel
    bcs rboot_error
    stx BOOT_DEST
    ldd #$4249
    std BOOT_INFO
    ldd #$3031
    std BOOT_INFO+2
    lda #32
    sta BOOT_INFO+4
    lda #9
    sta BOOT_INFO+5
    ldd #1
    std BOOT_INFO+6
    clr BOOT_STATUS
    ldx #BOOT_INFO
    jmp [BOOT_DEST]
rboot_error:
    lda #POWER_LED_ALL
    sta UART_LED_RESET
    lda #POWER_LED_RED
    sta UART_LED_SET
    lda #13
    jsr rom_putc
    lda #10
    jsr rom_putc
    lda #'B'
    jsr rom_putc
    lda BOOT_STATUS
    adda #'0'
    jsr rom_putc
    lda #13
    jsr rom_putc
    lda #10
    jsr rom_putc
    bra rom_halt
; Function: rom_start_app. Inputs U=canonical common frame; outputs native RTI.
; Clobbers scratch only; caller must have prepared PROCESS_MAP/S/V/context.
rom_start_app:
    ldu #ENTRY_BASE
    lda #1
    sta ENTRY_DEPTH
    jmp rom_return
ROM_LOWER_END equ *
    ifgt ROM_LOWER_END-$F400
    error "Production ROM overlaps I/O"
    endc
    org $F800
    jmp rom_start_app
    jmp rom_panic
    jmp rom_putc
    jmp rom_nested_test
    jmp >CORE_DISPATCH
    jmp rom_timer_enable
    jmp boot_find
    jmp boot_read
    jmp boot_write
    jmp boot_read
    jmp rom_return
    jmp rom_boot_status
    jmp rom_boot_pulse
    jmp rom_boot_image
    org $FFF0
    fdb rom_trap,rom_unsupported,rom_unsupported,rom_firq
    fdb rom_irq,rom_swi,rom_nmi,rom_reset
