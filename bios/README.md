# Microlind BIOS ABI

The BIOS is the hardware service layer for Microlind. It owns direct access to
the XR88C92 serial port, MMU, VIA/parallel port, IRQ controller, and later block
devices. OS code should use BIOS calls for early boot and low-level hardware
access, then wrap those calls in kernel syscalls for user programs.

## Structure

- `src/init.asm`
  Reset entry, CPU/MMU setup, stack setup, basic hardware init, and CPU vector
  table.

- `driver/*.asm`
  Hardware-specific routines. These use register-oriented assembly ABIs such as
  `X = pointer`, `A = byte`, or `D = word`.

- `driver/bios_c_shim.asm`
  C-callable wrappers around the hardware drivers. These adapt CMOC stack
  arguments into the register ABI used by the drivers.

- `src/bios_vectors.asm`
  Fixed ROM jump table. Each entry is a `JMP` instruction to a C ABI wrapper.
  This is the stable binary interface that kernels and programs can call when
  BIOS is in ROM.

- `include/bios.h`
  C declarations for directly linked BIOS shims and optional fixed-address
  jump-table macros.

- `include/syscalls.h`
  Convenience `sys_*` aliases for firmware-level calls. This is useful for
  small C programs linked directly against BIOS, but MLOS has its own kernel
  syscall header in `mlos/include/syscalls.h`.

## BIOS Jump Table

The default jump table base is:

```asm
BIOS_JUMPTAB_BASE EQU $F800
```

Each entry is one absolute `JMP`, so every table slot is 3 bytes:

```asm
BIOS_JUMPTAB_ENTRY_SIZE EQU 3
```

Example from assembly:

```asm
BIOS_SERIAL_PRINT EQU BIOS_JUMPTAB_BASE+(2*BIOS_JUMPTAB_ENTRY_SIZE)

ldx #message
jsr BIOS_SERIAL_PRINT

message:
    fcn "hello"
```

Example from C when calling ROM BIOS directly:

```c
#define MICROLIND_USE_BIOS_JUMPTAB
#include "bios.h"

void main(void)
{
    bios_serial_print("hello\r\n");
}
```

## Current Exported BIOS Services

Serial:

- `serial_init`
- `serial_start`
- `serial_print`
- `serial_putc`
- `serial_input`
- `serial_print_byte`
- `serial_print_byte_hex`
- `serial_print_word_hex`
- `serial_print_crlf`
- counter/timer helpers

LED:

- `set_led`
- `set_led_red`
- `set_led_green`
- `set_led_blue`
- `set_led_off`

MMU:

- `mmu_init`
- `mmu_set_register`
- `mmu_set_register_0..3`
- `mmu_get_register`
- `mmu_get_register_0..3`

Parallel / joystick:

- `parallel_init`
- `parallel_enable_timer_interrupt`
- `parallel_disable_timer_interrupt`
- `parallel_reset_interrupt`
- `beep(duration_ms, frequency_hz)` (PC speaker on VIA PB7; blocking)
- `parallel_get_port_a`
- `read_joy1`
- `read_joy2`

IRQ:

- `irq_init`
- `irq_set_filter`
- `irq_get_active`
- `irq_get_current_filter`

## Stability Rules

Once OS or application code depends on a BIOS ROM, treat `bios_vectors.asm` as
append-only:

- Do not reorder existing entries.
- Do not change the meaning of an existing entry.
- Add new services at the end.
- Keep `BIOS_JUMPTAB_ENTRY_SIZE` in `bios/include/bios.h` synchronized with the
  actual jump-table encoding.

If a service needs a new argument convention, add a new entry instead of changing
an old one.

## BIOS vs Kernel Syscalls

BIOS calls are hardware services:

```text
serial_putc
mmu_set_register
parallel_get_port_a
```

Kernel syscalls are OS policy services:

```text
sys_write
sys_sbrk
sys_exit
sys_open
```

MLOS should use BIOS calls internally, but user programs should call MLOS
syscalls. That keeps C applications independent from the current serial chip,
filesystem layout, and memory banking policy.

## Build Notes

The current `bios/Makefile` needs cleanup before it is the authoritative build
path. It still references old root-level source paths and a missing LED driver
file. The CMake source list is closer to the intended C-shim structure.

Before relying on a BIOS image, verify:

```sh
cd bios
make
```

or the CMake equivalent after the BIOS build files have been cleaned up.
