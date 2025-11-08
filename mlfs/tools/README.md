# MLFS Tools

This directory contains utility tools for working with MLFS filesystem images.

## Tools

### `cli/`

The MLFS command-line interface - an interactive shell for creating, managing, and working with MLFS filesystem images.

**Key Features:**
- Interactive shell with command history and prompts
- Create and format MLFS images with custom sizes
- Multi-partition support with flexible layouts
- Full filesystem operations (mkdir, touch, write, read, rm, rmdir)
- Navigation with cd, pwd, ls commands
- Partition management (mkpart, mkfs, mount, unmount)
- File content operations (cat, write)
- Filesystem information display (info, partitions)
- Batch command support via stdin

**Usage:** 
- Interactive: `mlfs`
- Mount existing image: `mlfs <image_file>`
- Batch mode: `mlfs < commands.txt`

See [cli/README.md](cli/README.md) and [cli/USAGE.md](cli/USAGE.md) for detailed documentation and examples.

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
├── cli/                    # Interactive CLI tool
│   ├── main.c              # CLI interface
│   ├── cli_commands.c/h    # Command implementations
│   ├── file_io.c           # File I/O operations
│   ├── CMakeLists.txt      # Build configuration
│   ├── README.md           # Detailed documentation
│   ├── USAGE.md            # Usage guide
│   └── example_usage.sh    # Example script
├── mlfs_info/              # Filesystem analysis tool
│   ├── mlfs_info.c         # Source code
│   ├── CMakeLists.txt      # Build configuration  
│   └── README.md           # Detailed documentation
├── mlfs_blockdev/          # Block device management tool
│   ├── mlfs_blockdev.c     # Source code
│   ├── CMakeLists.txt      # Build configuration
│   └── README.md           # Detailed documentation
├── tests/                  # Test scripts
│   ├── test_mlfs_info.sh   # mlfs_info tests
│   ├── test_multi_partition.sh  # Multi-partition tests
│   └── test_subdirs.sh     # Subdirectory tests
├── CMakeLists.txt          # Tools build configuration
└── README.md               # This file
```

## Tool Comparison

| Feature | CLI | mlfs_info | mlfs_blockdev |
|---------|-----|-----------|---------------|
| **Purpose** | Create and manage MLFS images | Analyze/inspect MLFS images | Manage MLFS on block devices |
| **Input** | Image files | Image files or devices | Block devices only |
| **Access** | Read-write | Read-only | Read-only or read-write |
| **Use Case** | Image creation & manipulation | Safe examination | Hardware setup & management |
| **Interactive** | Yes (shell interface) | No (command-line tool) | No (command-line tool) |
| **Requires Root** | No | No (for files) | Yes (for write operations) |
| **Risk Level** | Safe (works with files) | Safe | High (can destroy data) |

## Quick Start Examples

### Creating an Image File with CLI (Safe)
```bash
# Start interactive CLI
mlfs

# Or create and work with an image directly
mlfs << EOF
format disk.img 32 4096
mount disk.img
mkdir documents
touch readme.txt
write readme.txt "Welcome to MLFS!"
ls
cat readme.txt
info
quit
EOF
```

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

### Typical Workflow
```bash
# 1. Create image with CLI
mlfs << EOF
format myfs.img 64
mkpart 1 32 4096 main
mkfs 0
mount myfs.img 0
mkdir data
touch data/config.ini
quit
EOF

# 2. Analyze with mlfs_info
mlfs_info myfs.img 0

# 3. Write to CompactFlash with mlfs_blockdev
sudo mlfs_blockdev /dev/sdb write_image myfs.img

# 4. Verify
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
