# MLFS C to 6309 Assembler Translation Roadmap

This document outlines the strategy for translating the MLFS C library to 6309 assembler.

## Overview

The MLFS (MicroLind File System) library is currently implemented in C. This roadmap describes how to translate it to 6309 assembler for use on the Microlind hardware platform.

## Documentation

1. **`../docs/C_TO_6309_TRANSLATION.md`** - Comprehensive guide on translating C to 6309 assembler
2. **`../docs/6309_TRANSLATION_GUIDE.md`** - 6309 instruction reference and patterns
3. **`mlfs_6309_example.asm`** - Example translations of key functions
4. **`include/mlfs_types.inc`** - Structure offsets and constants

## Translation Strategy

### Phase 1: Foundation (Prerequisites)

- [x] Create structure offset definitions (`mlfs_types.inc`)
- [x] Create helper function library (memcpy, memset, strcmp, etc.)
- [ ] Implement 32-bit arithmetic routines (multiply, divide, add, subtract)
- [ ] Create memory management system (replace malloc/free)
- [ ] Define calling conventions and stack frame layout

### Phase 2: Core Utilities

Translate simple utility functions first:

- [ ] `mlfs_cksum32()` - Checksum calculation
- [ ] `mlfs_bitmap_bits_per_block()` - Simple calculation
- [ ] `mlfs_now_unix()` - Time function (may need BIOS integration)
- [ ] `mlfs_fill_uuid()` - UUID generation

### Phase 3: Low-Level I/O

- [ ] `mlfs_read_block()` - Block read operation
- [ ] `mlfs_write_block()` - Block write operation
- [ ] Handle function pointer calls for I/O operations

### Phase 4: Bitmap Operations

- [ ] `mlfs_bitmap_get()` - Get bit from bitmap
- [ ] `mlfs_bitmap_set()` - Set bit in bitmap
- [ ] `mlfs_bitmap_find_run()` - Find free block run
- [ ] `mlfs_bitmap_mark_run()` - Mark block run as used/free

### Phase 5: Directory Helpers

- [ ] `mlfs_dir_write_empty()` - Initialize empty directory
- [ ] `mlfs_dir_lookup_in_dir()` - Find entry in directory
- [ ] `mlfs_dir_add_entry_to_dir()` - Add entry to directory
- [ ] `mlfs_dir_remove_entry_from_dir()` - Remove entry from directory
- [ ] `mlfs_dir_count_entries_in_dir()` - Count directory entries

### Phase 6: Path Resolution

- [ ] `mlfs_split_path()` - Split path into components
- [ ] `mlfs_resolve_path()` - Resolve path to directory and filename

### Phase 7: Partition Table Operations

- [ ] `mlfs_read_mlpt()` - Read partition table
- [ ] `mlfs_write_mlpt()` - Write partition table
- [ ] `mlfs_make_single_partition()` - Create single partition
- [ ] `mlfs_make_empty_partition_table()` - Create empty partition table
- [ ] `mlfs_add_partition()` - Add partition to table

### Phase 8: Filesystem Operations

- [ ] `mlfs_mkfs()` - Format filesystem
- [ ] `mlfs_mount()` - Mount filesystem
- [ ] `mlfs_alloc_run()` - Allocate block range

### Phase 9: File Operations

- [ ] `mlfs_create_empty_file()` - Create new file
- [ ] `mlfs_pwrite_file()` - Write to file
- [ ] `mlfs_pread_file()` - Read from file
- [ ] `mlfs_delete_file()` - Delete file

### Phase 10: Directory Operations

- [ ] `mlfs_create_directory()` - Create directory
- [ ] `mlfs_delete_directory()` - Delete directory
- [ ] `mlfs_read_directory()` - List directory contents

## Key Challenges

### 1. Memory Management

**Problem**: C code uses `malloc()` and `free()` extensively.

**Solution**: 
- Use static buffers for temporary block operations
- Use stack allocation for small buffers
- Implement a simple buffer pool for frequently used operations

**Implementation**:
```asm
    section .bss
MLFS_BLOCK_BUF_1       rmb 512    ; Block buffer 1
MLFS_BLOCK_BUF_2       rmb 512    ; Block buffer 2
MLFS_BLOCK_BUF_IN_USE fcb 0      ; Allocation flag
```

### 2. Function Pointers

**Problem**: I/O operations use function pointers.

**Solution**: Call through function pointer using `jsr ,y` syntax.

**Implementation**:
```asm
    ldx fs_ptr
    ldy MLFS_T_IO + MLFS_IO_READ,x  ; Load function pointer
    ; Setup parameters...
    jsr ,y                           ; Call function
```

### 3. 32-bit and 64-bit Arithmetic

**Problem**: Many calculations use 32-bit or 64-bit values.

**Solution**: 
- Use 6309 Q register for 32-bit operations
- Implement 32-bit multiply/divide routines
- Use 16-bit approximations where possible

### 4. String Operations

**Problem**: C uses standard library string functions.

**Solution**: Implement custom string routines:
- `MLFS_STRLEN` - String length
- `MLFS_STRCMP` - String compare
- `MLFS_STRNCPY` - String copy with length

### 5. Error Handling

**Problem**: C uses return codes and early exits.

**Solution**: Use standard 6309 branch instructions:
- `beq` / `bne` for zero checks
- `bhs` / `blo` for comparisons
- Return error codes in D register

## Calling Convention

### Parameters
- Pass parameters on stack (right-to-left order)
- Small parameters (8/16-bit) passed as values
- Pointers passed as 16-bit addresses
- Return values in D register (16-bit) or A register (8-bit)

### Stack Frame
```
[S+LOCALS+RET+SAVED] = Parameter N
[S+LOCALS+RET+SAVED-2] = Parameter N-1
...
[S+LOCALS+RET] = Parameter 1
[S+LOCALS] = Saved U (frame pointer)
[S+LOCALS-2] = Return address
[S] = Local variables
```

### Register Usage
- **A, B, D**: Parameters, return values, temporaries (caller-saved)
- **X, Y**: Index registers, pointers (caller-saved)
- **U**: Frame pointer (callee-saved)
- **S**: Stack pointer (callee-saved)
- **E, F**: Temporaries (caller-saved)
- **W, V**: Temporaries (caller-saved)
- **Q**: 32-bit temporaries (caller-saved)

## Testing Strategy

1. **Unit Tests**: Test each function individually
2. **Integration Tests**: Test function combinations
3. **Filesystem Tests**: Test complete filesystem operations
4. **Performance Tests**: Compare with C implementation

## Build Integration

### Makefile Integration

Add to `mlfs/lib/Makefile`:
```makefile
MLFS_6309_SRC = mlfs_6309.asm helper_functions.asm
MLFS_6309_OBJ = $(MLFS_6309_SRC:.asm=.o)
MLFS_6309_BIN = $(BUILD)/mlfs_6309.ihex

mlfs_6309: build
	lwasm -3 -f ihex -I include -o $(MLFS_6309_BIN) $(MLFS_6309_SRC)
```

### CMake Integration

Add to `mlfs/lib/CMakeLists.txt`:
```cmake
# 6309 Assembler version
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/mlfs_6309.ihex
    COMMAND lwasm -3 -f ihex -I ${CMAKE_CURRENT_SOURCE_DIR}/include 
            -o ${CMAKE_CURRENT_BINARY_DIR}/mlfs_6309.ihex
            ${CMAKE_CURRENT_SOURCE_DIR}/mlfs_6309.asm
    DEPENDS mlfs_6309.asm include/mlfs_types.inc
    COMMENT "Building MLFS 6309 assembler version"
)
```

## File Organization

```
mlfs/lib/
├── include/
│   ├── mlfs.h              # C API (existing)
│   ├── mlfs_types.h        # C types (existing)
│   └── mlfs_types.inc      # 6309 structure offsets (new)
├── src/
│   └── mlfs.c              # C implementation (existing)
├── mlfs_6309.asm           # Main 6309 implementation (new)
├── mlfs_6309_example.asm   # Example translations (new)
├── helper_functions.asm    # Utility functions (new)
└── TRANSLATION_ROADMAP.md  # This file
```

## Progress Tracking

Use this checklist to track translation progress:

- [ ] Phase 1: Foundation
- [ ] Phase 2: Core Utilities
- [ ] Phase 3: Low-Level I/O
- [ ] Phase 4: Bitmap Operations
- [ ] Phase 5: Directory Helpers
- [ ] Phase 6: Path Resolution
- [ ] Phase 7: Partition Table Operations
- [ ] Phase 8: Filesystem Operations
- [ ] Phase 9: File Operations
- [ ] Phase 10: Directory Operations

## Next Steps

1. **Review the translation guides** in `docs/`
2. **Study the example code** in `mlfs_6309_example.asm`
3. **Start with Phase 1** - Implement helper functions
4. **Test incrementally** - Test each function as you translate it
5. **Integrate with BIOS** - Connect I/O functions to BIOS drivers

## Resources

- **6309 Instruction Set**: See `docs/6309_TRANSLATION_GUIDE.md`
- **C Translation Patterns**: See `docs/C_TO_6309_TRANSLATION.md`
- **LWASM Documentation**: http://lwtools.projects.l-w.ca/
- **Existing BIOS Code**: `microlind-sw/bios/` for examples

## Notes

- The translation prioritizes correctness over optimization initially
- Some C features (like variable-length arrays) may need redesign
- Error handling should match C behavior for compatibility
- Consider creating a C wrapper for testing against the C implementation

