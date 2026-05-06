; -----------------------------------------------------------------
; MLOS syscall numbers
; -----------------------------------------------------------------

MLOS_SYSCALL_INC EQU 1

SYS_EXIT        EQU 0
SYS_PUTC        EQU 1
SYS_GETC        EQU 2
SYS_WRITE       EQU 3
SYS_READ        EQU 4
SYS_SBRK        EQU 5
SYS_TICKS       EQU 6
SYS_BLOCK_READ  EQU 7
SYS_BLOCK_WRITE EQU 8
SYS_OPEN        EQU 9
SYS_CLOSE       EQU 10
SYS_READ_FD     EQU 11
SYS_WRITE_FD    EQU 12
SYS_SEEK        EQU 13

SYS_ENOSYS      EQU -1
SYS_EINVAL      EQU -2
SYS_ENOMEM      EQU -3
