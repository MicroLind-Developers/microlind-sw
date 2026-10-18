; -----------------------------------------------------------------
; C-callable MLOS syscall shims
; -----------------------------------------------------------------
; These wrappers are for code linked with the kernel/runtime. They adapt
; CMOC-style stack arguments to MLOS_SYSCALL_DISPATCH.
; -----------------------------------------------------------------

    IFNDEF MLOS_SYSCALL_INC
        include "../include/syscall.inc"
    ENDC

; void sys_exit(uint8_t code)
_sys_exit:
    pshs u
    tfr s,u
    lda #SYS_EXIT
    ldb 2,u
    jsr MLOS_SYSCALL_DISPATCH
    puls u,pc

; int16_t sys_putc(uint8_t ch)
_sys_putc:
    pshs u
    tfr s,u
    lda #SYS_PUTC
    ldb 2,u
    jsr MLOS_SYSCALL_DISPATCH
    puls u,pc

; int16_t sys_getc(void)
_sys_getc:
    lda #SYS_GETC
    jsr MLOS_SYSCALL_DISPATCH
    rts

; int16_t sys_write(const void *buf, uint16_t len)
_sys_write:
    pshs u
    tfr s,u
    lda #SYS_WRITE
    ldx 2,u
    ldy 4,u
    jsr MLOS_SYSCALL_DISPATCH
    puls u,pc

; int16_t sys_read(void *buf, uint16_t len)
_sys_read:
    pshs u
    tfr s,u
    lda #SYS_READ
    ldx 2,u
    ldy 4,u
    jsr MLOS_SYSCALL_DISPATCH
    puls u,pc

; void *sys_sbrk(int16_t delta)
_sys_sbrk:
    pshs u
    tfr s,u
    lda #SYS_SBRK
    ldx 2,u
    jsr MLOS_SYSCALL_DISPATCH
    puls u,pc

; uint32_t sys_ticks(void)
_sys_ticks:
    lda #SYS_TICKS
    jsr MLOS_SYSCALL_DISPATCH
    rts
