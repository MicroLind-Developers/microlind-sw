; -----------------------------------------------------------------
; C-callable BIOS wrapper shims for µLind
; Adapts C stack arguments to existing driver routines using 6809 regs
; Exported with leading underscore names to match C symbols
; Toolchain: lwasm/lwlink (lwtools) + cmoc
; -----------------------------------------------------------------

    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC


; -----------------------------
; Serial (XR88C92)
; -----------------------------

    export _serial_init
_serial_init:
    jsr SERIAL_INIT
    rts

    export _serial_start
_serial_start:
    jsr SERIAL_START
    rts

; void serial_print(const char* s)
    export _serial_print
_serial_print:
    pshs u
    tfr  s,u
    ldx  2,u
    jsr  SERIAL_PRINT_A
    puls u,pc

; void serial_putc(uint8_t ch)
    export _serial_putc
_serial_putc:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  SERIAL_PRINT_CHAR_A
    puls u,pc

; void serial_input(char* buf, uint16_t size)
    export _serial_input
_serial_input:
    pshs u
    tfr  s,u
    ldx  2,u      ; buf
    ldy  4,u      ; size
    jsr  SERIAL_INPUT_A
    puls u,pc

; void serial_print_byte(uint8_t v)
    export _serial_print_byte
_serial_print_byte:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  SERIAL_PRINT_BYTE_A
    puls u,pc

; void serial_print_byte_hex(uint8_t v)
    export _serial_print_byte_hex
_serial_print_byte_hex:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  SERIAL_PRINT_BYTE_HEX_A
    puls u,pc

; void serial_print_word_hex(uint16_t v)
    export _serial_print_word_hex
_serial_print_word_hex:
    pshs u
    tfr  s,u
    ldx  2,u
    jsr  SERIAL_PRINT_WORD_HEX_A
    puls u,pc

; void serial_print_crlf(void)
    export _serial_print_crlf
_serial_print_crlf:
    jsr  SERIAL_PRINT_CRLF_A
    rts

; void serial_set_ct(uint16_t ct)
    export _serial_set_ct
_serial_set_ct:
    pshs u
    tfr  s,u
    ldd  2,u
    jsr  SERIAL_SET_CT
    puls u,pc

; void serial_set_ct_mode(uint8_t mode)
    export _serial_set_ct_mode
_serial_set_ct_mode:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  SERIAL_SET_CT_MODE
    puls u,pc

; void serial_enable_ct_irq(void)
    export _serial_enable_ct_irq
_serial_enable_ct_irq:
    jsr  SERIAL_ENABLE_CT_IRQ
    rts

; void serial_start_ct(void)
    export _serial_start_ct
_serial_start_ct:
    jsr  SERIAL_START_CT
    rts

; void serial_stop_ct(void)
    export _serial_stop_ct
_serial_stop_ct:
    jsr  SERIAL_STOP_CT
    rts

; void set_led(uint8_t state)
    export _set_led
_set_led:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  SET_LED
    puls u,pc

    export _set_led_red
_set_led_red:
    jsr  SET_LED_RED
    rts

    export _set_led_green
_set_led_green:
    jsr  SET_LED_GREEN
    rts

    export _set_led_blue
_set_led_blue:
    jsr  SET_LED_BLUE
    rts

    export _set_led_off
_set_led_off:
    jsr  SET_LED_OFF
    rts

; -----------------------------
; MMU
; -----------------------------

; void mmu_init(void)
    export _mmu_init
_mmu_init:
    pshs u
    ldx  #.ret_from_mmu_init
    jsr  MMU_INIT
.ret_from_mmu_init:
    puls u,pc

; void mmu_set_register(uint8_t reg, uint8_t val)
    export _mmu_set_register
_mmu_set_register:
    pshs u
    tfr  s,u
    clra
    ldb  2,u      ; reg index (8-bit)
    tfr  d,x      ; X = 0:reg
    lda  3,u      ; value
    jsr  MMU_SET_REGISTER
    puls u,pc

; void mmu_set_register_0(uint8_t val)
    export _mmu_set_register_0
_mmu_set_register_0:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  MMU_SET_REGISTER_0
    puls u,pc

; void mmu_set_register_1(uint8_t val)
    export _mmu_set_register_1
_mmu_set_register_1:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  MMU_SET_REGISTER_1
    puls u,pc

; void mmu_set_register_2(uint8_t val)
    export _mmu_set_register_2
_mmu_set_register_2:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  MMU_SET_REGISTER_2
    puls u,pc

; void mmu_set_register_3(uint8_t val)
    export _mmu_set_register_3
_mmu_set_register_3:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  MMU_SET_REGISTER_3
    puls u,pc

; uint8_t mmu_get_register(uint8_t reg)
    export _mmu_get_register
_mmu_get_register:
    pshs u
    tfr  s,u
    clra
    ldb  2,u      ; reg index (8-bit)
    tfr  d,x
    jsr  MMU_GET_REGISTER
    puls u,pc

; uint8_t mmu_get_register_0(void)
    export _mmu_get_register_0
_mmu_get_register_0:
    jsr  MMU_GET_REGISTER_0
    rts

; uint8_t mmu_get_register_1(void)
    export _mmu_get_register_1
_mmu_get_register_1:
    jsr  MMU_GET_REGISTER_1
    rts

; uint8_t mmu_get_register_2(void)
    export _mmu_get_register_2
_mmu_get_register_2:
    jsr  MMU_GET_REGISTER_2
    rts

; uint8_t mmu_get_register_3(void)
    export _mmu_get_register_3
_mmu_get_register_3:
    jsr  MMU_GET_REGISTER_3
    rts

; -----------------------------
; Parallel (6522 VIA)
; -----------------------------

; void parallel_init(void)
    export _parallel_init
_parallel_init:
    jsr  PARALLEL_INIT
    rts

; void parallel_enable_timer_interrupt(void)
    export _parallel_enable_timer_interrupt
_parallel_enable_timer_interrupt:
    jsr  PARALLEL_ENABLE_TIMER_INTERRUPT
    rts

; void parallel_disable_timer_interrupt(void)
    export _parallel_disable_timer_interrupt
_parallel_disable_timer_interrupt:
    jsr  PARALLEL_DISABLE_TIMER_INTERRUPT
    rts

; void parallel_reset_interrupt(void)
    export _parallel_reset_interrupt
_parallel_reset_interrupt:
    jsr  PARALLEL_RESET_INTERRUPT
    rts

; uint8_t parallel_get_port_a(void)
    export _parallel_get_port_a
_parallel_get_port_a:
    jsr  PARALLEL_GET_PORT_A
    rts

; uint8_t read_joy1(void)
    export _read_joy1
_read_joy1:
    jsr  READ_JOY1
    rts

; uint8_t read_joy2(void)
    export _read_joy2
_read_joy2:
    jsr  READ_JOY2
    rts

; -----------------------------
; IRQ controller
; -----------------------------

; void irq_init(void)
    export _irq_init
_irq_init:
    jsr  IRQ_INIT
    rts

; void irq_set_filter(uint8_t level)
    export _irq_set_filter
_irq_set_filter:
    pshs u
    tfr  s,u
    lda  2,u
    jsr  IRQ_SET_FILTER
    puls u,pc

; uint8_t irq_get_active(void)
    export _irq_get_active
_irq_get_active:
    jsr  IRQ_GET_ACTIVE
    rts

; uint8_t irq_get_current_filter(void)
    export _irq_get_current_filter
_irq_get_current_filter:
    jsr  IRQ_GET_CURRENT_FILTER
    rts


