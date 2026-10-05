# Microlind BIOS ABI

The BIOS is the hardware service layer for Microlind. It owns direct access to
the XR88C92 serial port, MMU, VIA/parallel port, IRQ controller, and later block
devices. OS code should use BIOS calls for early boot and low-level hardware
access, then wrap those calls in kernel syscalls for user programs.

## Structure

- `src/init.asm`
  Reset entry, CPU/MMU setup, stack setup, basic hardware init, and CPU vector
  table.

- `src/bios.asm`
  Authoritative image layout, including drivers, module services, font, upper
  ROM messages, and reset code. Both standalone build systems assemble this
  entry point and validate the resulting addresses.

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

The legacy C-wrapper jump table described in this section is source-only in
the current standalone ROM build: `bios_vectors.asm` and `bios_c_shim.asm` are
not linked into that image. Its range `$F800–$F87F` remains reserved. Do not
call the `bios_*` C function-pointer macros against this image. RAM modules
use the separate register ABI below, through assembly bridges.

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

Build and run the host regression checks:

```sh
make -C bios test
```

`make -C bios` also builds the RAM-resident `biosfs.mlp` extension and the
CMOC acceptance application `fsdiag.mlp`. Their services, serial commands,
image builder, and board acceptance steps are documented in
[modules/filesystem/README.md](modules/filesystem/README.md). The complete Make
build requires CMOC; `make -C bios filesystem` builds just the assembly module.
Run the simulator integration tests with `make -C bios test-fs`.

Or build the standalone CMake project:

```sh
cmake -S bios -B bios/build/cmake
cmake --build bios/build/cmake
ctest --test-dir bios/build/cmake --output-on-failure
```

Run the BIOS in the sibling simulator's CLI:

```sh
make -C bios test-sim
# Override the default ../../microlind-sim/build/microlind-sim-cli when needed:
make -C bios test-sim SIMULATOR=/absolute/path/to/microlind-sim-cli
```

The integration runner creates private ROM/RAM fixtures and temporary CF images.
It executes the actual BIOS services on the simulated HD6309 and checks boot
with and without VDC/CF, sector reads and writes, register preservation, LBA
bounds, read-only media, missing-media timeouts, the MLPT raw-boot guard,
VDC memory access, nonblocking serial input, and VIA Timer 2 IRQ dispatch.
The runner also compiles the production host MLFS library with `cc` to create
module fixtures for all eight block sizes. It verifies complete payload copies,
memory bounds, zeroed tails, invalid metadata/headers/checksums, mid-load CF
failures, module entry arguments, and launch/return through the BIOS menu.
It never opens an existing disk image. Each simulator process has a 30-second
timeout. These checks complement physical board validation.

To include these checks in CTest, configure with
`-DSIMULATOR_EXECUTABLE=/absolute/path/to/microlind-sim-cli`.

Both builds produce `bios.ihex`, an assembler listing, and a symbol dump.
Assembly assertions and `tools/check_rom.py` reject I/O-window output,
overlapping records, invalid vectors, and mismatched module service entries.
Alternate assembler output formats remain supported; an Intel HEX image is
always generated and checked before the requested output is accepted.

The layout is `$E000–$F3FF` for firmware code, `$F800–$F87F` reserved for the
legacy C jump table, `$F880–$F8FF` for RAM-module services, `$F900–$FCFF` for the
font, `$FD00–$FDFF` for boot messages and the filesystem menu helper, and `$FE00–$FFFF` for reset code and
vectors. The existing VDC font bytes are preserved.

## RAM-module register ABI, version 1

The descriptor at `$F880` contains `MBR1`, a big-endian ABI version word,
and an entry-count word. Each entry starting at `$F888` is a three-byte
absolute `JMP`. `include/module.inc` defines the addresses; these calls do
**not** use CMOC's stack-argument convention.

| Index | Service | Input / result |
|---|---|---|
| 0 | CF init | C clear, A=0 on success; C set, A=error |
| 1 | CF read | Q=LBA28, X=512-byte destination; CF status in A/C |
| 2 | CF write | Q=LBA28, X=512-byte source; CF status in A/C |
| 3 | Serial print | X=NUL-terminated text; X advances |
| 4 | Serial putc | A=byte |
| 5 | Serial try-getc | C clear, A=byte; C set if empty; no echo |
| 6 | Joystick 1 | A=pressed bits: up/down/left/right/button in bits 0–4 |
| 7 | VDC cursor | A=row, B=column; C set on invalid position or timeout |
| 8 | VDC RAM byte | X=VDC address, A=byte; C set on timeout |
| 9 | VDC update address | X=VDC address; C set on timeout |
| 10 | VDC selected write | B=byte; C set on timeout |
| 11 | VDC register write | A=register, B=value; C set on timeout |
| 12 | VDC register read | A=register; returns B=value, C set on timeout |
| 13 | VDC clear | C set on timeout |
| 14 | VDC print | X=NUL-terminated ASCII text; C set on timeout |
| 15 | VDC foreground | A=RGBI color |
| 16 | VDC background | A=RGBI color; C set on timeout |
| 17 | Install IRQ handler | X=RTI handler or zero for default; returns previous X |
| 18 | Load module | X=root filename, B=kind; returns A/C status and X=entry |
| 19 | Run module | X=root filename, B=kind, Y=filesystem API or zero; A/C status |

CF transfers preserve Y, U, and W, advance X by 512 on success, and use bounded
waits before and after the data phase. The write service assumes the board's
existing byte-wide PIO configuration and must be verified on hardware before
gameplay implementation; run the generated filesystem diagnostic for this check. Driver comments document other register clobbers.

IRQ installation preserves CC and does not enable interrupts. A module must
configure its peripheral, provide an RTI handler, and restore the previous
handler and peripheral state before returning or allowing its RAM to be reused.
FIRQ remains separate and unused. VDC calls retain bounded timeout behavior;
the calling module must handle failures rather than continue rendering blindly.

## MLFS bootstrap and module launch

`src/bootstrap.asm` reads partition 0 of an MLPT/MLFS 1.1.0 card, using the
existing 512-byte storage buffer and 54 bytes of private state at `$D940`.
It supports block sizes from 512 bytes to 64 KB. It checks table/version fields,
superblock checksums, checked LBA28 partition bounds, directory/extent bounds,
and complete MLP1 headers and payload checksums. It performs no disk writes.

The bootstrap accepts root files with one inline contiguous extent and no
indirect extents. It requires the host formatter's ordering: superblock,
bitmap, root directory, then file data. Unsupported layouts return an error.
Names may have one leading `/`; subdirectory traversal belongs to the runtime
extension. The logical file length must exactly match header plus payload.

Menu option **7. Load MLFS extension** loads and runs `/biosfs.mlp`, opening
its serial console. The extension supports mounting, stat/list/read/write,
creation/removal, contiguous file growth, rename/move, and allocation counts.
Console command `t` loads `/fsdiag.mlp` and tests the separate partition 1.
Every menu launch reloads the module, so it also works after the destructive
RAM test.

Load returns C clear, A=0, and X=absolute entry address after checksum validation
and zeroing the uninitialized tail. On failure C is set, and A identifies the
error: 1=CF I/O, 2=metadata, 3=missing root file, 4=unsupported/invalid extent,
5=module header, 6=payload checksum. Invalid payload data may remain in its
reserved region after a failed load; callers must check carry before execution.
The loader is not reentrant and clobbers D, W, X, Y, U, and CC.

Run validates first, then calls the entry with X=`$F880` (BIOS descriptor) and
Y=the caller's filesystem service pointer, or zero for the extension's first
entry. A module returns with RTS and must balance its stack and restore any
peripheral/IRQ-hook state it changes. Run restores DP, Y, U, and the caller's
IRQ masks on return; A=0/C clear means successful launch and return. It ignores
the module's own result registers. RAM modules need an assembly entry bridge
before calling C code. The loader and launcher must execute from ROM or outside
the region they load into, and loading an active module's region is unsupported.

## MLP1 package format

| Offset | Field | Size |
|---|---|---|
| 0 | `MLP1` magic | 4 bytes |
| 4 | ABI version (1) | 16 bits |
| 6 | Kind: filesystem=0, application=1 | 16 bits |
| 8 | Fixed load address | 16 bits |
| 10 | Entry offset within payload | 16 bits |
| 12 | Initialized payload size | 16 bits |
| 14 | Total memory size, including uninitialized tail | 16 bits |
| 16 | Additive 32-bit checksum of payload bytes | 32 bits |

All integer fields are big-endian. Filesystem modules load at `$4000` and end
before `$C000`; applications load at `$0400` and end before `$4000`. The entry
must lie within initialized bytes. The loader clears the remaining
memory tail before invoking the module.

Package an addressed Intel HEX or Motorola S-record image:

```sh
python3 bios/tools/pack_module.py app.srec app.mlp --kind application \
    --entry 0x0400 --memory-size 0x1000
```

The tool rejects overlapping records, bad record checksums, unsupported module
addresses, invalid entry points, and oversized memory regions. Missing bytes
between initialized address records are filled with zero. No files on a CF
device are written by this command.
