# µLind Project AI Assistant Guidelines

This document provides essential information for AI assistants working with the µLind project, a Hitachi 6309-based embedded operating system.

## Project Overview

µLind is a Hitachi 6309-based embedded operating system designed for microcontroller and embedded systems. It consists of three main layers:

1. **BIOS** (Basic Input/Output System) - Hardware service layer with direct access to hardware
2. **MLOS** (MicroLind Operating System) - Kernel layer providing OS services
3. **MLFS** (MicroLind File System) - Embedded file system implementation

## Key Components

### BIOS Layer
- Located in `/bios/` directory
- Provides hardware abstraction layer for serial ports, MMU, IRQ controller, parallel port, and block devices
- Uses register-oriented assembly ABIs (e.g., `X = pointer`, `A = byte`, `D = word`)
- Implements BIOS jump table for stable binary interface
- Hardware drivers are in `/bios/driver/`
- C-callable wrappers in `/bios/driver/bios_c_shim.asm`

### MLOS Layer
- Located in `/mlos/` directory
- Kernel layer that provides stable kernel services to C programs
- Syscall dispatcher in `/mlos/src/syscall_dispatch.asm`
- Memory manager in `/mlos/src/memory_manager.asm`
- Uses register ABI for syscalls:
  - `A = syscall number`
  - `B = small argument, character, or exit code`
  - `X = arg0 pointer or 16-bit value`
  - `Y = arg1 pointer or value`
- Return convention:
  - `D or X = return value, depending on syscall`
  - `C clear = success`
  - `C set = failure`
  - `D = negative SYS_E* error code on failure`

### MLFS Layer
- Located in `/mlfs/` directory
- Lightweight embedded file system designed for microcontroller systems
- Supports multi-partition with custom partition table format (MLPT)
- Flexible block sizes from 512 bytes to 64KB
- Extensive test suite with automated coverage analysis

## Build System

The project uses both Make and CMake build systems:

### Make-based Build
- Root `Makefile` defines prototype tests for IRQ, parallel, and PS2 interfaces
- `bios/Makefile` and `mlos/Makefile` for respective layers
- Uses `lwasm` assembler for Hitachi 6309 assembly code

### CMake-based Build
- Main `CMakeLists.txt` in root directory
- CMakeLists.txt in each component directory (`bios`, `mlos`, `mlfs`)
- Generates `compile_commands.json` for IDE integration
- Output format is Intel HEX (`ihex`)

## Hardware Architecture

- Hitachi 6309-based system with XR88C92 serial port
- MMU (Memory Management Unit) with 3 16K banks and one 8K bank
- CompactFlash card support for block device access
- VIA/parallel port support
- IRQ controller for interrupt handling
- Serial port for console I/O

## Code Patterns and Conventions

### Assembly Code
- Uses Hitachi 6309 assembly syntax
- Register-oriented calling conventions
- Hardware registers defined in `/bios/include/registers.h`
- Memory management with MMU configuration
- Interrupt handling with vector table setup

### BIOS Services
- All BIOS services are exported through jump table at `BIOS_JUMPTAB_BASE` ($F800)
- Each jump table entry is 3 bytes (absolute `JMP` instruction)
- Services are grouped by hardware type:
  - Serial port functions
  - LED control functions
  - MMU management functions
  - Parallel port/joystick functions
  - IRQ controller functions

### Syscall ABI
- First-stage dispatcher uses register ABI:
  - `A = syscall number`
  - `B = small argument, character, or exit code`
  - `X = arg0 pointer or 16-bit value`
  - `Y = arg1 pointer or value`
- Return convention:
  - Success: `C clear`, return value in `D` or `X`
  - Failure: `C set`, error code in `D` (negative SYS_E* value)

## Testing and Development

### Testing Approach
- Unit tests for each component
- Integration tests for BIOS/MLOS interaction
- MLFS has comprehensive test suite with coverage analysis
- Test files in `/tests/` directory

### Development Environment
- Uses `lwasm` assembler for 6502 assembly
- CMake for build system management
- Makefiles for traditional build approach
- Development focused on embedded systems with limited resources

## Key Directories and Files

- `/bios/` - BIOS layer with hardware drivers and jump table
- `/mlos/` - MLOS kernel with syscall dispatcher and memory manager
- `/mlfs/` - MLFS file system implementation
- `/driver/` - Hardware driver implementations
- `/include/` - Header files for BIOS and MLOS
- `/tests/` - Test suite for all components
- `Makefile` - Root Makefile for prototype tests
- `CMakeLists.txt` - Main CMake build configuration

## Important Notes

1. BIOS calls are hardware services that should be used for early boot and low-level hardware access
2. MLOS kernel syscalls are OS policy services that user programs should call instead of BIOS directly
3. The BIOS jump table is append-only once OS or application code depends on it
4. All hardware-specific names are kept out of `syscalls.h` to maintain abstraction
5. Memory management is currently a simple linear heap but will be replaced with page management
6. Block I/O is implemented through CompactFlash driver for storage access
7. File I/O is implemented through MLFS with separate file system and block I/O layers

## Current Roadmap

1. Convert `SYS_WRITE` to counted buffer output
2. Add `SYS_GETC` for blocking character input
3. Wire timer ticks for `SYS_TICKS`
4. Replace linear heap with page management
5. Add block device syscalls
6. Mount MLFS in the kernel
7. Define program loading convention
8. Add process state support

This project is designed for embedded systems with limited resources, focusing on reliability and performance in constrained environments.