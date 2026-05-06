; -----------------------------------------------------------------
; MLOS shared constants
; -----------------------------------------------------------------

MLOS_INC EQU 1

    IFNDEF MEMORY_INC
        include "../../bios/include/memory.inc"
    ENDC

MLOS_ORIGIN      EQU $8000
MLOS_STACK_TOP   EQU $C000

; Initial linear heap used by MEM_MANAGER_SBRK.
; Keep this below the BIOS/driver RAM area for now.
MLOS_HEAP_START  EQU $9000
MLOS_HEAP_END    EQU $BFFF

; BIOS ROM jump table entry points. A JSR to these addresses enters a JMP
; table slot and returns through the target BIOS routine.
BIOS_JUMPTAB_BASE       EQU $F800
BIOS_JUMPTAB_ENTRY_SIZE EQU 3

BIOS_SERIAL_PRINT       EQU BIOS_JUMPTAB_BASE+(2*BIOS_JUMPTAB_ENTRY_SIZE)
BIOS_SERIAL_PUTC        EQU BIOS_JUMPTAB_BASE+(3*BIOS_JUMPTAB_ENTRY_SIZE)
BIOS_SERIAL_INPUT       EQU BIOS_JUMPTAB_BASE+(4*BIOS_JUMPTAB_ENTRY_SIZE)
BIOS_SERIAL_CRLF        EQU BIOS_JUMPTAB_BASE+(8*BIOS_JUMPTAB_ENTRY_SIZE)
BIOS_SET_LED_GREEN      EQU BIOS_JUMPTAB_BASE+(16*BIOS_JUMPTAB_ENTRY_SIZE)
BIOS_IRQ_GET_ACTIVE     EQU BIOS_JUMPTAB_BASE+(39*BIOS_JUMPTAB_ENTRY_SIZE)
