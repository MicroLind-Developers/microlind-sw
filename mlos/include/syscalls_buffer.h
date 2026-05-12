#ifndef MLOS_SYSCALLS_BUFFER_H
#define MLOS_SYSCALLS_BUFFER_H

#include "../../bios/include/integer.h"

// Buffer syscall numbers - starting from 20 to avoid conflicts with existing syscalls
#define SYS_BUF_READ_U8     20
#define SYS_BUF_READ_U16    21
#define SYS_BUF_READ_U32    22
#define SYS_BUF_WRITE_U8    23
#define SYS_BUF_WRITE_U16   24
#define SYS_BUF_WRITE_U32   25
#define SYS_BUF_READ        26
#define SYS_BUF_WRITE       27

// Function prototypes for buffer syscalls
uint8_t sys_buf_read_u8(uint32_t addr);
uint16_t sys_buf_read_u16(uint32_t addr);
uint32_t sys_buf_read_u32(uint32_t addr);
int16_t sys_buf_write_u8(uint32_t addr, uint8_t value);
int16_t sys_buf_write_u16(uint32_t addr, uint16_t value);
int16_t sys_buf_write_u32(uint32_t addr, uint32_t value);
int16_t sys_buf_read(uint32_t addr, void *buf, uint16_t len);
int16_t sys_buf_write(uint32_t addr, const void *buf, uint16_t len);

#endif /* MLOS_SYSCALLS_BUFFER_H */