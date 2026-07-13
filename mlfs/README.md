# MLFS — MicroLind File System

A lightweight, embedded file system designed for microcontroller and embedded systems.

## Features

- **Multi-partition support** with custom partition table format (MLPT)
- **Flexible block sizes** (512 bytes to 64KB, configurable per partition)
- **Directory support** with full subdirectory navigation
- **Rename support** for files and directories
- **Extent-based storage** for efficient file allocation
- **Comprehensive test suite** with automated coverage analysis
- **CLI tools** for filesystem management and inspection

## Quick Start

### Building

```bash
mkdir build && cd build
cmake ..
make
```

### Running Tests

```bash
# Run all tests
make check

# Or use CTest directly
ctest --output-on-failure --verbose
```

### Code Coverage

```bash
# Build with coverage enabled
cmake -DENABLE_COVERAGE=ON ..
make

# Generate coverage report
make coverage-report

# View HTML report
firefox build/coverage/html/index.html
```

## Documentation

- **[Coverage Analysis](COVERAGE.md)** - Detailed coverage setup and usage
- **[Tests README](tests/README.md)** - Test suite documentation
- **[CLI Documentation](cli/README.md)** - Command-line interface guide
- **[Library Documentation](lib/README.md)** - Core library API reference
- **[Kernel Module](kmod/README.md)** - Linux kernel driver (separate build)

## Components

- **`lib/`** - Core MLFS library implementation
- **`cli/`** - Command-line interface for filesystem management
- **`tools/`** - Utilities (mlfs_info for analysis, mlfs_blockdev for block devices)
- **`kmod/`** - Linux kernel module for native read/write mounting
- **`tests/`** - Comprehensive test suite using Check framework

## Architecture

- **MLPT (MicroLind Partition Table)** - Custom partition table format
- **Superblock** - Filesystem metadata per partition
- **Bitmap allocation** - Efficient block allocation tracking
- **Directory entries** - Support for files and subdirectories
- **Extent-based files** - Efficient storage with extent lists

## Block Sizes and Partition Planning

MLFS supports configurable block sizes from 512 bytes to 64 KB. Choosing the right block size depends on your partition size and use case.

### Block Size Reference Table

| Block Size | Log2 | Min Partition | Recommended Size Range | Best For | Notes |
|------------|------|---------------|------------------------|----------|-------|
| **512 B** | 9 | 256 KB | 256 KB - 4 MB | Very small flash, bootloaders | Matches sector size, high metadata overhead |
| **1 KB** | 10 | 512 KB | 512 KB - 8 MB | Small config storage | Good for many tiny files |
| **2 KB** | 11 | 1 MB | 1 MB - 16 MB | Small embedded systems | Balanced for limited storage |
| **4 KB** | 12 | 2 MB | 8 MB - 256 MB | **General purpose (recommended)** | Matches Linux page size, optimal for most uses |
| **8 KB** | 13 | 4 MB | 16 MB - 512 MB | Medium data storage | Good compromise for larger files |
| **16 KB** | 14 | 8 MB | 32 MB - 1 GB | Large file storage | Reduces metadata, good for media |
| **32 KB** | 15 | 16 MB | 64 MB - 2 GB | Bulk data, media files | Low metadata overhead |
| **64 KB** | 16 | 32 MB | 128 MB - 4 GB | Large partitions, archives | Maximum efficiency for large files |

### Block Size Selection Guidelines

**For Small Partitions (< 8 MB):**
- Use **512 B - 2 KB** blocks
- Minimizes internal fragmentation
- Example: 4 MB bootloader partition with 1 KB blocks

**For Medium Partitions (8 MB - 128 MB):**
- Use **4 KB** blocks (recommended)
- Matches Linux page size for optimal kernel integration
- Example: 32 MB system partition with 4 KB blocks

**For Large Partitions (> 128 MB):**
- Use **8 KB - 32 KB** blocks
- Reduces bitmap size and directory overhead
- Example: 512 MB data partition with 16 KB blocks

**For Very Large Partitions (> 1 GB):**
- Use **32 KB - 64 KB** blocks
- Maximum efficiency, lowest metadata overhead
- Example: 2 GB media partition with 64 KB blocks

### Trade-offs

| Aspect | Small Blocks (512 B - 2 KB) | Medium Blocks (4 KB - 8 KB) | Large Blocks (16 KB - 64 KB) |
|--------|----------------------------|----------------------------|------------------------------|
| **Space Efficiency** | ✅ Excellent for small files | ✅ Good balance | ❌ Wastes space on small files |
| **Metadata Overhead** | ❌ High (larger bitmap) | ✅ Moderate | ✅ Low |
| **I/O Efficiency** | ❌ More operations needed | ✅ Good | ✅ Excellent |
| **Large Files** | ❌ Slow, many extents | ✅ Good | ✅ Fast |
| **Kernel Integration** | ❌ Mismatched to page size | ✅ Matches 4K pages | ⚠️ May need buffering |

### Examples

```bash
# Bootloader partition: 4 MB with 1 KB blocks
mkpart 1 4 1024 boot

# System partition: 32 MB with 4 KB blocks (recommended)
mkpart 8193 32 4096 system

# Data partition: 256 MB with 16 KB blocks
mkpart 73729 256 16384 data

# Media partition: 1 GB with 32 KB blocks
mkpart 598017 1024 32768 media
```

### Calculating Start LBA for Next Partition

When creating multiple partitions, calculate the start LBA for the next partition:

```
next_start_lba = prev_start_lba + (partition_size_mb * 1024 * 1024) / 512

Example:
- Partition 0 starts at LBA 1, size 32 MB
- Partition 1 starts at: 1 + (32 * 1024 * 1024) / 512 = 65537
```

Or use the `info` command in the CLI to see suggested start positions.
