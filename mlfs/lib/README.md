# MLFS Library

This directory contains the core MLFS (MicroLind File System) library implementation.

## Structure

```
lib/
├── src/                    # Library source code
│   └── mlfs.c             # Main implementation
├── include/               # Public header files
│   ├── mlfs.h             # Public API header
│   └── mlfs_types.h       # Data structure definitions
├── CMakeLists.txt         # Library build configuration
└── README.md              # This file
```

## Files

### `include/mlfs.h`
- **Public API header** - Include this in your projects
- Function declarations for all MLFS operations
- Constants and configuration macros
- I/O function type definitions

### `include/mlfs_types.h`
- **Data structure definitions**
- On-disk format structures (packed)
- In-memory filesystem state structures
- Partition and superblock definitions

### `src/mlfs.c`
- **Main implementation** of all MLFS functions
- Filesystem operations (mkfs, mount)
- File operations (create, read, write, delete)
- Directory operations (create, list, delete)
- Block allocation and bitmap management

## Usage

To use the MLFS library in your project:

### CMake Integration

```cmake
# Add as subdirectory
add_subdirectory(path/to/mlfs/lib)

# Link with your target
target_link_libraries(your_target PRIVATE mlfs)
```

### C Code

```c
#include "mlfs.h"

// Your code here - all MLFS functions are available
```

## API Overview

### Core Functions

| Function | Purpose |
|----------|---------|
| `mlfs_mkfs()` | Format filesystem |
| `mlfs_mount()` | Mount filesystem |
| `mlfs_make_single_partition()` | Create partition table |

### File Operations

| Function | Purpose |
|----------|---------|
| `mlfs_create_empty_file()` | Create new file |
| `mlfs_pwrite_file()` | Write to file |
| `mlfs_pread_file()` | Read from file |
| `mlfs_delete_file()` | Delete file |

### Directory Operations

| Function | Purpose |
|----------|---------|
| `mlfs_create_directory()` | Create directory |
| `mlfs_read_directory()` | List directory contents |
| `mlfs_delete_directory()` | Delete empty directory |

### Memory Management

| Function | Purpose |
|----------|---------|
| `mlfs_alloc_run()` | Allocate block range |

## Build Options

The library can be configured through CMake options:

- **CMAKE_BUILD_TYPE**: `Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`
- **CMAKE_C_STANDARD**: C99 (required)

## Dependencies

The library has minimal dependencies:
- Standard C library (C99)
- No external libraries required
- Designed for embedded and systems programming

## Thread Safety

⚠️ **Not thread-safe** - The current implementation is not designed for concurrent access. External synchronization is required for multi-threaded usage.

## Limitations

See the main project documentation for current limitations and planned features.
