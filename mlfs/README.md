# MLFS — MicroLind File System

A lightweight, embedded file system designed for microcontroller and embedded systems.

## Features

- **Multi-partition support** with custom partition table format (MLPT)
- **Flexible block sizes** (512 bytes to 64KB, configurable per partition)
- **Directory support** with full subdirectory navigation
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

## Components

- **`lib/`** - Core MLFS library implementation
- **`cli/`** - Command-line interface for filesystem management
- **`tools/`** - Utilities for filesystem analysis (mlfs_info)
- **`tests/`** - Comprehensive test suite using Check framework

## Architecture

- **MLPT (MicroLind Partition Table)** - Custom partition table format
- **Superblock** - Filesystem metadata per partition
- **Bitmap allocation** - Efficient block allocation tracking
- **Directory entries** - Support for files and subdirectories
- **Extent-based files** - Efficient storage with extent lists

## Supported Block Sizes

- 512 bytes to 65536 bytes (2^9 to 2^16)
- Must be multiples of disk sector size
- Configurable per partition for optimal space usage