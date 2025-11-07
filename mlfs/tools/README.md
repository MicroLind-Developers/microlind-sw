# MLFS Tools

This directory contains utility tools for working with MLFS filesystem images.

## Tools

### `mlfs_info/`

A comprehensive filesystem analysis tool that parses MLFS image files and displays detailed information about the filesystem structure and contents.

**Key Features:**
- Partition table analysis with detailed partition information
- Superblock information and filesystem metadata  
- Block allocation statistics and usage analysis
- Directory tree visualization with file details
- Multi-partition support with selective analysis
- Human-readable output formatting
- Works with both image files and block devices

**Usage:** `mlfs_info <image_file> [partition_number]`

See [mlfs_info/README.md](mlfs_info/README.md) for detailed documentation and examples.

### `mlfs_blockdev/`

A userspace utility for working with MLFS filesystems on real Linux block devices (e.g., CompactFlash cards, SD cards, USB drives).

**Key Features:**
- Direct block device access using POSIX I/O (`pread`/`pwrite`)
- Safe read-only mode for device examination
- Create and manage partitions on block devices
- Format partitions with MLFS filesystems
- Comprehensive safety features and confirmation prompts
- Stepping stone toward kernel driver development

**Usage:** `mlfs_blockdev [options] <device> <command> [args...]`

**⚠️ WARNING:** This tool can permanently destroy data! Always use `-r` (read-only) when examining devices.

See [mlfs_blockdev/README.md](mlfs_blockdev/README.md) for detailed documentation, safety guidelines, and examples.

## Project Structure

```
tools/
├── mlfs_info/              # Filesystem analysis tool
│   ├── mlfs_info.c         # Source code
│   ├── CMakeLists.txt      # Build configuration  
│   └── README.md           # Detailed documentation
├── mlfs_blockdev/          # Block device management tool
│   ├── mlfs_blockdev.c     # Source code
│   ├── CMakeLists.txt      # Build configuration
│   └── README.md           # Detailed documentation
├── CMakeLists.txt          # Tools build configuration
├── README.md               # This file
└── test_*.sh              # Test scripts
```

## Tool Comparison

| Feature | mlfs_info | mlfs_blockdev |
|---------|-----------|---------------|
| **Purpose** | Analyze/inspect MLFS images | Manage MLFS on block devices |
| **Input** | Image files or devices | Block devices only |
| **Access** | Read-only | Read-only or read-write |
| **Use Case** | Safe examination | Hardware setup & management |
| **Requires Root** | No (for files) | Yes (for write operations) |
| **Risk Level** | Safe | High (can destroy data) |

## Quick Start Examples

### Examining an Image File (Safe)
```bash
# Analyze image file structure
mlfs_info disk.img

# View specific partition contents
mlfs_info disk.img 0
```

### Working with Block Devices (Requires Care!)
```bash
# Step 1: Safely examine device (no root needed)
mlfs_blockdev -r /dev/sdb info

# Step 2: Setup MLFS on CompactFlash (DESTRUCTIVE - requires sudo)
sudo mlfs_blockdev /dev/sdb format
sudo mlfs_blockdev /dev/sdb mkpart 1 8192 12 system
sudo mlfs_blockdev /dev/sdb mkfs 0

# Step 3: Verify with read-only tools
sudo mlfs_blockdev -r /dev/sdb info
sudo mlfs_info /dev/sdb 0
```

## Building All Tools

To build all tools in this directory:

```bash
cd mlfs/build
make tools
```

Or to build the entire MLFS project including tools:

```bash
cd mlfs/build  
make
```

## Installation

Tools can be installed system-wide:

```bash
cd mlfs/build
make install
```

This will install the tools to `/usr/local/bin` by default.
