#ifndef MLOS_SYSCALLS_H
#define MLOS_SYSCALLS_H

#include "../../bios/include/integer.h"

#define SYS_EXIT        0
#define SYS_PUTC        1
#define SYS_GETC        2
#define SYS_WRITE       3
#define SYS_READ        4
#define SYS_SBRK        5
#define SYS_TICKS       6
#define SYS_BLOCK_READ  7
#define SYS_BLOCK_WRITE 8
#define SYS_OPEN        9
#define SYS_CLOSE       10
#define SYS_READ_FD     11
#define SYS_WRITE_FD    12
#define SYS_SEEK        13

#define SYS_ENOSYS      (-1)
#define SYS_EINVAL      (-2)
#define SYS_ENOMEM      (-3)

void sys_exit(uint8_t code);
int16_t sys_putc(uint8_t ch);
int16_t sys_getc(void);
int16_t sys_write(const void *buf, uint16_t len);
int16_t sys_read(void *buf, uint16_t len);
void *sys_sbrk(int16_t delta);
uint32_t sys_ticks(void);

#endif /* MLOS_SYSCALLS_H */
