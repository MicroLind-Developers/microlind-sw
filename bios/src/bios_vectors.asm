; -----------------------------------------------------------------
; µLind BIOS jump table (fixed ROM ABI)
; Each entry is a JMP to a C-ABI wrapper symbol in driver/bios_c_shim.asm
; Update BIOS_JUMPTAB_BASE as per your memory map
; -----------------------------------------------------------------

    IFNDEF IO_INC
        include "../driver/io.inc"
    ENDC

    IFNDEF BIOS_JUMPTAB_BASE
BIOS_JUMPTAB_BASE  EQU $F800
    ENDC

            org BIOS_JUMPTAB_BASE

; Serial
            jmp _serial_init
            jmp _serial_start
            jmp _serial_print
            jmp _serial_putc
            jmp _serial_input
            jmp _serial_print_byte
            jmp _serial_print_byte_hex
            jmp _serial_print_word_hex
            jmp _serial_print_crlf
            jmp _serial_set_ct
            jmp _serial_set_ct_mode
            jmp _serial_enable_ct_irq
            jmp _serial_start_ct
            jmp _serial_stop_ct
            jmp _set_led
            jmp _set_led_red
            jmp _set_led_green
            jmp _set_led_blue
            jmp _set_led_off

; MMU
            jmp _mmu_init
            jmp _mmu_set_register
            jmp _mmu_set_register_0
            jmp _mmu_set_register_1
            jmp _mmu_set_register_2
            jmp _mmu_set_register_3
            jmp _mmu_get_register
            jmp _mmu_get_register_0
            jmp _mmu_get_register_1
            jmp _mmu_get_register_2
            jmp _mmu_get_register_3

; Parallel
            jmp _parallel_init
            jmp _parallel_enable_timer_interrupt
            jmp _parallel_disable_timer_interrupt
            jmp _parallel_reset_interrupt
            jmp _parallel_get_port_a
            jmp _read_joy1
            jmp _read_joy2

; IRQ
            jmp _irq_init
            jmp _irq_set_filter
            jmp _irq_get_active
            jmp _irq_get_current_filter


