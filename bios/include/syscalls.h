#ifndef MICROLIND_SYSCALLS_H
#define MICROLIND_SYSCALLS_H

#include "bios.h"

#ifdef MICROLIND_USE_BIOS_JUMPTAB

#define sys_serial_init          bios_serial_init
#define sys_serial_start         bios_serial_start
#define sys_serial_print         bios_serial_print
#define sys_serial_putc          bios_serial_putc
#define sys_serial_input         bios_serial_input
#define sys_serial_print_byte    bios_serial_print_byte
#define sys_serial_print_byte_hex bios_serial_print_byte_hex
#define sys_serial_print_word_hex bios_serial_print_word_hex
#define sys_serial_print_crlf    bios_serial_print_crlf
#define sys_serial_set_ct        bios_serial_set_ct
#define sys_serial_set_ct_mode   bios_serial_set_ct_mode
#define sys_serial_enable_ct_irq bios_serial_enable_ct_irq
#define sys_serial_start_ct      bios_serial_start_ct
#define sys_serial_stop_ct       bios_serial_stop_ct

#define sys_set_led              bios_set_led
#define sys_set_led_red          bios_set_led_red
#define sys_set_led_green        bios_set_led_green
#define sys_set_led_blue         bios_set_led_blue
#define sys_set_led_off          bios_set_led_off

#define sys_mmu_init             bios_mmu_init
#define sys_mmu_set_register     bios_mmu_set_register
#define sys_mmu_set_register_0   bios_mmu_set_register_0
#define sys_mmu_set_register_1   bios_mmu_set_register_1
#define sys_mmu_set_register_2   bios_mmu_set_register_2
#define sys_mmu_set_register_3   bios_mmu_set_register_3
#define sys_mmu_get_register     bios_mmu_get_register
#define sys_mmu_get_register_0   bios_mmu_get_register_0
#define sys_mmu_get_register_1   bios_mmu_get_register_1
#define sys_mmu_get_register_2   bios_mmu_get_register_2
#define sys_mmu_get_register_3   bios_mmu_get_register_3

#define sys_parallel_init        bios_parallel_init
#define sys_parallel_enable_timer_interrupt bios_parallel_enable_timer_interrupt
#define sys_parallel_disable_timer_interrupt bios_parallel_disable_timer_interrupt
#define sys_parallel_reset_interrupt bios_parallel_reset_interrupt
#define sys_parallel_get_port_a  bios_parallel_get_port_a
#define sys_read_joy1            bios_read_joy1
#define sys_read_joy2            bios_read_joy2

#define sys_irq_init             bios_irq_init
#define sys_irq_set_filter       bios_irq_set_filter
#define sys_irq_get_active       bios_irq_get_active
#define sys_irq_get_current_filter bios_irq_get_current_filter

#else

#define sys_serial_init          serial_init
#define sys_serial_start         serial_start
#define sys_serial_print         serial_print
#define sys_serial_putc          serial_putc
#define sys_serial_input         serial_input
#define sys_serial_print_byte    serial_print_byte
#define sys_serial_print_byte_hex serial_print_byte_hex
#define sys_serial_print_word_hex serial_print_word_hex
#define sys_serial_print_crlf    serial_print_crlf
#define sys_serial_set_ct        serial_set_ct
#define sys_serial_set_ct_mode   serial_set_ct_mode
#define sys_serial_enable_ct_irq serial_enable_ct_irq
#define sys_serial_start_ct      serial_start_ct
#define sys_serial_stop_ct       serial_stop_ct

#define sys_set_led              set_led
#define sys_set_led_red          set_led_red
#define sys_set_led_green        set_led_green
#define sys_set_led_blue         set_led_blue
#define sys_set_led_off          set_led_off

#define sys_mmu_init             mmu_init
#define sys_mmu_set_register     mmu_set_register
#define sys_mmu_set_register_0   mmu_set_register_0
#define sys_mmu_set_register_1   mmu_set_register_1
#define sys_mmu_set_register_2   mmu_set_register_2
#define sys_mmu_set_register_3   mmu_set_register_3
#define sys_mmu_get_register     mmu_get_register
#define sys_mmu_get_register_0   mmu_get_register_0
#define sys_mmu_get_register_1   mmu_get_register_1
#define sys_mmu_get_register_2   mmu_get_register_2
#define sys_mmu_get_register_3   mmu_get_register_3

#define sys_parallel_init        parallel_init
#define sys_parallel_enable_timer_interrupt parallel_enable_timer_interrupt
#define sys_parallel_disable_timer_interrupt parallel_disable_timer_interrupt
#define sys_parallel_reset_interrupt parallel_reset_interrupt
#define sys_parallel_get_port_a  parallel_get_port_a
#define sys_read_joy1            read_joy1
#define sys_read_joy2            read_joy2

#define sys_irq_init             irq_init
#define sys_irq_set_filter       irq_set_filter
#define sys_irq_get_active       irq_get_active
#define sys_irq_get_current_filter irq_get_current_filter

#endif

#endif /* MICROLIND_SYSCALLS_H */
