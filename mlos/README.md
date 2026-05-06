# MLOS Implementation Notes

MLOS is the Microlind operating system layer. Its job is to provide stable
kernel services to C programs while hiding BIOS and hardware details behind an
OS syscall ABI.

The current code is a bootable skeleton, not a complete OS.

## Current Structure

- `src/kernel.asm`
  Kernel entry point at `MLOS_ORIGIN`, stack initialization, memory manager
  initialization, and a serial banner through the BIOS jump table.

- `src/syscall_dispatch.asm`
  First syscall dispatcher. It accepts a syscall number in `A`, arguments in
  registers, and dispatches to kernel services.

- `src/syscall_c_shim.asm`
  C-callable wrappers named `_sys_*`. These adapt CMOC stack arguments into the
  dispatcher register ABI.

- `src/memory_manager.asm`
  First-stage linear heap with `MEM_MANAGER_SBRK`. This is enough to support a
  C runtime and later `malloc`.

- `include/mlos.inc`
  Kernel memory layout and BIOS jump-table constants used by assembly.

- `include/syscall.inc`
  Assembly syscall numbers and error codes.

- `include/syscalls.h`
  C-facing syscall API for OS programs.

## Build

Using Make:

```sh
cd mlos
make
```

Output:

```text
mlos/build/mlos.ihex
```

Using CMake:

```sh
cmake -S mlos -B /tmp/mlos-build
cmake --build /tmp/mlos-build
```

## Current Syscall ABI

The first-stage dispatcher uses this register ABI:

```text
A = syscall number
B = small argument, character, or exit code
X = arg0 pointer or 16-bit value
Y = arg1 pointer or 16-bit value
```

Return convention:

```text
D or X = return value, depending on syscall
C clear = success
C set   = failure
D       = negative SYS_E* error code on failure
```

Current syscall numbers:

```text
SYS_EXIT        0
SYS_PUTC        1
SYS_GETC        2
SYS_WRITE       3
SYS_READ        4
SYS_SBRK        5
SYS_TICKS       6
SYS_BLOCK_READ  7
SYS_BLOCK_WRITE 8
SYS_OPEN        9
SYS_CLOSE       10
SYS_READ_FD     11
SYS_WRITE_FD    12
SYS_SEEK        13
```

Currently implemented:

- `SYS_EXIT`
- `SYS_PUTC`
- `SYS_WRITE`
- `SYS_READ`
- `SYS_SBRK`
- `SYS_TICKS`, currently returns zero

Currently reserved but not implemented:

- `SYS_GETC`
- block I/O
- file I/O

## C Usage

Kernel-linked C code can include:

```c
#include "syscalls.h"
```

Example:

```c
void app_main(void)
{
    sys_write("hello from MLOS\r\n", 17);
    sys_putc('>');
    sys_sbrk(64);
}
```

The C wrappers are in `src/syscall_c_shim.asm`. They are normal link symbols,
not ROM BIOS calls.

## Implementation Roadmap

### 1. Make Console I/O Counted

`SYS_WRITE` currently treats `X` as a NUL-terminated string and ignores `Y`.
The public C prototype is already:

```c
int16_t sys_write(const void *buf, uint16_t len);
```

Next step: implement counted writes so binary buffers and strings with embedded
zero bytes work correctly.

Suggested dispatcher behavior:

```text
X = buffer
Y = length
return D = bytes written
```

### 2. Add Blocking Character Input

Implement `SYS_GETC` on top of the BIOS serial input path or a BIOS serial
character-read routine.

Suggested behavior:

```text
return D = character in low byte
```

Add a non-blocking variant later if needed.

### 3. Wire Timer Ticks

`SYS_TICKS` should return a monotonic counter updated from IRQ/FIRQ timer code.

Needed pieces:

- timer initialization during `MLOS_START`
- IRQ/FIRQ vector ownership
- a kernel RAM tick counter
- atomic read of the counter in `SYS_TICKS`

### 4. Replace Linear Heap with Page Management

The current memory manager is deliberately simple:

```text
MLOS_HEAP_START = $9000
MLOS_HEAP_END   = $BFFF
```

Keep `SYS_SBRK` stable, but internally move toward:

- detected physical memory banks
- bitmap of 256-byte pages or larger pages
- reserved kernel pages
- user/process allocation regions
- bank mapping ownership

### 5. Add Block Device Syscalls

Implement:

```c
int16_t sys_block_read(uint32_t lba, void *buf);
int16_t sys_block_write(uint32_t lba, const void *buf);
```

Use fixed 512-byte sectors for CompactFlash. Keep block I/O separate from file
I/O so MLFS can be developed and tested independently.

### 6. Mount MLFS in the Kernel

After block I/O works, add MLFS-backed file syscalls:

```c
int16_t sys_open(const char *path, uint8_t flags);
int16_t sys_close(int16_t fd);
int16_t sys_read_fd(int16_t fd, void *buf, uint16_t len);
int16_t sys_write_fd(int16_t fd, const void *buf, uint16_t len);
int16_t sys_seek(int16_t fd, uint32_t pos);
```

Start with a small fixed file descriptor table in kernel RAM.

### 7. Define Program Loading

Before multitasking, define a simple program loading convention:

- load address
- initial stack
- argument block format
- return path to shell
- which MMU banks belong to the program

Then implement `SYS_EXIT` as return-to-shell instead of halt.

### 8. Add Process State Later

Do not start with full multitasking. First make one program run reliably.

Later process state should include:

- saved registers
- stack pointer
- MMU bank map
- open file descriptors
- process state flags

## Design Rules

- User programs call MLOS syscalls, not BIOS directly.
- MLOS can call BIOS during early bring-up.
- Keep syscall numbers stable once programs depend on them.
- Return negative errors consistently.
- Prefer adding new syscalls over changing argument meaning.
- Keep hardware-specific names out of `syscalls.h`.

## Near-Term Work Items

Recommended next commits:

1. Convert `SYS_WRITE` to counted buffer output.
2. Add `SYS_GETC`.
3. Add a small `examples/hello.c` that links against `syscall_c_shim.asm`.
4. Fix BIOS build files so the BIOS jump table image is reproducible.
5. Add block read/write around `compactflash.asm`.
