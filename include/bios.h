#ifndef MICROLIND_BIOS_H
#define MICROLIND_BIOS_H


/* Fixed-width integer typedefs */
#include "integer.h"


/* Serial (XR88C92) */
void serial_init(void);
void serial_start(void);
void serial_print(const char* s);
void serial_putc(uint8_t ch);
void serial_input(char* buf, uint16_t size);
void serial_print_byte(uint8_t v);
void serial_print_byte_hex(uint8_t v);
void serial_print_word_hex(uint16_t v);
void serial_print_crlf(void);
void serial_set_ct(uint16_t ct);
void serial_set_ct_mode(uint8_t mode);
void serial_enable_ct_irq(void);
void serial_start_ct(void);
void serial_stop_ct(void);

/* LED via serial OPCR */
void set_led(uint8_t state);
void set_led_red(void);
void set_led_green(void);
void set_led_blue(void);
void set_led_off(void);

/* MMU */
void mmu_init(void);
void mmu_set_register(uint8_t reg, uint8_t val);
void mmu_set_register_0(uint8_t val);
void mmu_set_register_1(uint8_t val);
void mmu_set_register_2(uint8_t val);
void mmu_set_register_3(uint8_t val);
uint8_t mmu_get_register(uint8_t reg);
uint8_t mmu_get_register_0(void);
uint8_t mmu_get_register_1(void);
uint8_t mmu_get_register_2(void);
uint8_t mmu_get_register_3(void);

/* Parallel (6522) */
void parallel_init(void);
void parallel_enable_timer_interrupt(void);
void parallel_disable_timer_interrupt(void);
void parallel_reset_interrupt(void);
uint8_t parallel_get_port_a(void);
uint8_t read_joy1(void);
uint8_t read_joy2(void);

/* IRQ */
void irq_init(void);
void irq_set_filter(uint8_t level);
uint8_t irq_get_active(void);
uint8_t irq_get_current_filter(void);

/* Optional: fixed-address BIOS jump table bindings
   Define MICROLIND_USE_BIOS_JUMPTAB to bind function pointers to ROM */
#ifdef MICROLIND_USE_BIOS_JUMPTAB

typedef void (*bios_vfn)(void);
typedef void (*bios_vfn_pchar)(const char*);
typedef void (*bios_vfn_u8)(uint8_t);
typedef void (*bios_vfn_buf_u16)(char*, uint16_t);
typedef void (*bios_vfn_u16)(uint16_t);

#ifndef BIOS_JUMPTAB_BASE
#define BIOS_JUMPTAB_BASE 0xF800u
#endif

#define bios_serial_init          ((bios_vfn        )(BIOS_JUMPTAB_BASE + 0))
#define bios_serial_start         ((bios_vfn        )(BIOS_JUMPTAB_BASE + 2))
#define bios_serial_print         ((bios_vfn_pchar  )(BIOS_JUMPTAB_BASE + 4))
#define bios_serial_putc          ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 6))
#define bios_serial_input         ((bios_vfn_buf_u16)(BIOS_JUMPTAB_BASE + 8))
#define bios_serial_print_byte    ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 10))
#define bios_serial_print_byte_hex((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 12))
#define bios_serial_print_word_hex((bios_vfn_u16    )(BIOS_JUMPTAB_BASE + 14))
#define bios_serial_print_crlf    ((bios_vfn        )(BIOS_JUMPTAB_BASE + 16))
#define bios_serial_set_ct        ((bios_vfn_u16    )(BIOS_JUMPTAB_BASE + 18))
#define bios_serial_set_ct_mode   ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 20))
#define bios_serial_enable_ct_irq ((bios_vfn        )(BIOS_JUMPTAB_BASE + 22))
#define bios_serial_start_ct      ((bios_vfn        )(BIOS_JUMPTAB_BASE + 24))
#define bios_serial_stop_ct       ((bios_vfn        )(BIOS_JUMPTAB_BASE + 26))
#define bios_set_led              ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 28))
#define bios_set_led_red          ((bios_vfn        )(BIOS_JUMPTAB_BASE + 30))
#define bios_set_led_green        ((bios_vfn        )(BIOS_JUMPTAB_BASE + 32))
#define bios_set_led_blue         ((bios_vfn        )(BIOS_JUMPTAB_BASE + 34))
#define bios_set_led_off          ((bios_vfn        )(BIOS_JUMPTAB_BASE + 36))

#define bios_mmu_init             ((bios_vfn        )(BIOS_JUMPTAB_BASE + 38))
#define bios_mmu_set_register     ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 40)) /* note: expects (reg,val) via stack; see caution */
#define bios_mmu_set_register_0   ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 42))
#define bios_mmu_set_register_1   ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 44))
#define bios_mmu_set_register_2   ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 46))
#define bios_mmu_set_register_3   ((bios_vfn_u8     )(BIOS_JUMPTAB_BASE + 48))
#define bios_mmu_get_register     ((uint8_t (*)(uint8_t))(BIOS_JUMPTAB_BASE + 50))
#define bios_mmu_get_register_0   ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 52))
#define bios_mmu_get_register_1   ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 54))
#define bios_mmu_get_register_2   ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 56))
#define bios_mmu_get_register_3   ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 58))

#define bios_parallel_init                ((bios_vfn)(BIOS_JUMPTAB_BASE + 60))
#define bios_parallel_enable_timer_interrupt ((bios_vfn)(BIOS_JUMPTAB_BASE + 62))
#define bios_parallel_disable_timer_interrupt ((bios_vfn)(BIOS_JUMPTAB_BASE + 64))
#define bios_parallel_reset_interrupt     ((bios_vfn)(BIOS_JUMPTAB_BASE + 66))
#define bios_parallel_get_port_a          ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 68))
#define bios_read_joy1                    ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 70))
#define bios_read_joy2                    ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 72))

#define bios_irq_init                     ((bios_vfn)(BIOS_JUMPTAB_BASE + 74))
#define bios_irq_set_filter               ((bios_vfn_u8)(BIOS_JUMPTAB_BASE + 76))
#define bios_irq_get_active               ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 78))
#define bios_irq_get_current_filter       ((uint8_t (*)(void))(BIOS_JUMPTAB_BASE + 80))

#endif /* MICROLIND_USE_BIOS_JUMPTAB */

#endif /* MICROLIND_BIOS_H */


