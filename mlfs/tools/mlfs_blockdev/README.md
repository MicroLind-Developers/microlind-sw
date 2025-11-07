# mlfs_blockdev - MLFS Block Device Tool

A userspace utility for working with MLFS filesystems on real Linux block devices such as CompactFlash cards, SD cards, USB drives, and other storage media.

## Overview

`mlfs_blockdev` provides direct access to MLFS filesystems on block devices using standard POSIX I/O (`pread`/`pwrite`). This tool is designed as a stepping stone toward kernel driver integration, allowing you to test and work with MLFS on real hardware before developing a full kernel module.

**Key Features:**
- Direct block device access using POSIX file descriptors
- Safe read-only mode for examining devices without risk
- Confirmation prompts for destructive operations
- Support for all MLFS partition table operations
- Proper sector-aligned I/O with synchronous writes
- Comprehensive device information display

## Safety Features

### ⚠️ WARNING: Data Destruction Risk

This tool can **permanently destroy** data on block devices. Always exercise caution:

- **Always use `-r` (read-only) when examining unknown devices**
- Double-check device paths (`/dev/sda` vs `/dev/sdb` - one typo = data loss!)
- Use `lsblk` or `fdisk -l` to verify device identity before any write operations
- Unmount any existing filesystems on the device before using this tool
- Keep backups of important data

### Built-in Safety Measures

1. **Read-Only Mode (`-r`)**: Prevents any writes to the device
2. **Confirmation Prompts**: Requires typing "YES" for destructive operations
3. **Block Device Detection**: Warns when operating on non-block devices
4. **Root Permission Check**: Alerts when write operations might fail due to permissions
5. **Synchronous I/O**: Uses `O_SYNC` and `fsync()` to ensure data integrity

## Usage

```bash
mlfs_blockdev [options] <device> <command> [args...]
```

### Options

- `-r` - Open device in read-only mode (safe for examination)
- `-h` - Show help message

### Commands

#### `info`
Display device information and partition table.

```bash
# Safe read-only inspection (no root needed for most devices)
mlfs_blockdev -r /dev/sdb info

# Read-write access (allows checking current state)
sudo mlfs_blockdev /dev/sdb info
```

**Example Output:**
```
Device Information
==================
Device Path:   /dev/sdb
Access Mode:   Read-Only
Sector Size:   512 bytes
Device Size:   1.9 GB (2006597632 bytes)
Total Sectors: 3919136

MLFS Partition Table Found
===========================
Magic:      0x4D4C5054
Version:    0.1.0
Partitions: 1

Partition 0:
  Type:       1 (MLFS)
  Start LBA:  1
  Blocks:     8192
  Block Size: 4096 bytes (log2: 12)
  Name:       main
  Size:       32.0 MB
```

#### `format`
Create an empty MLFS partition table on the device.

**⚠️ DESTROYS ALL DATA on the device!**

```bash
sudo mlfs_blockdev /dev/sdb format
```

This will:
1. Display a warning and require "YES" confirmation
2. Write an empty MLFS partition table to LBA 0
3. Prepare the device for partition creation

#### `mkpart`
Create a new partition in the MLFS partition table.

```bash
sudo mlfs_blockdev /dev/sdb mkpart <start_lba> <size_mb> <block_size> <name>
```

**Arguments:**
- `start_lba` - Starting sector (LBA) for the partition (must be > 0)
- `size_mb` - Size of partition in megabytes (1-2048)
- `block_size` - Block size in bytes (must be power of 2: 512, 1024, 2048, 4096, etc.)
  - 512 bytes (minimum)
  - 1024 bytes
  - 2048 bytes
  - **4096 bytes (recommended - matches Linux page size)**
  - 8192 bytes
  - 16384 bytes
  - 32768 bytes
  - 65536 bytes (maximum)
- `name` - Partition name (up to 13 characters)

**Examples:**
```bash
# Create 32 MB partition starting at LBA 1, using 4KB blocks
sudo mlfs_blockdev /dev/sdb mkpart 1 32 4096 system

# Create 64 MB partition with 8KB blocks
sudo mlfs_blockdev /dev/sdb mkpart 65537 64 8192 data
```

#### `mkfs`
Format a specific partition with an MLFS filesystem.

**⚠️ DESTROYS DATA in the partition!**

```bash
sudo mlfs_blockdev /dev/sdb mkfs <partition_number>
```

**Arguments:**
- `partition_number` - Partition to format (0-15)

**Example:**
```bash
# Format partition 0
sudo mlfs_blockdev /dev/sdb mkfs 0
```

## Complete Workflow Example

### Setting up a CompactFlash Card with MLFS

```bash
# Step 1: Identify the device
lsblk
# Look for your CF card, e.g., /dev/sdb (2GB CF card)

# Step 2: Verify it's the correct device (READ-ONLY CHECK)
sudo mlfs_blockdev -r /dev/sdb info
# Should show no MLFS partition table if it's a fresh card

# Step 3: Unmount any existing filesystems
sudo umount /dev/sdb1  # if mounted

# Step 4: Create MLFS partition table
sudo mlfs_blockdev /dev/sdb format
# Type: YES

# Step 5: Create partitions
# Partition 0: 32 MB system partition (4KB blocks)
sudo mlfs_blockdev /dev/sdb mkpart 1 32 4096 system

# Partition 1: 64 MB data partition (4KB blocks)
# Start after first partition: 1 + (32 MB * 1024 * 1024 / 512) = 65537
sudo mlfs_blockdev /dev/sdb mkpart 65537 64 4096 data

# Step 6: Format partitions with MLFS
sudo mlfs_blockdev /dev/sdb mkfs 0
# Type: YES
sudo mlfs_blockdev /dev/sdb mkfs 1
# Type: YES

# Step 7: Verify setup
sudo mlfs_blockdev -r /dev/sdb info

# Step 8: Use mlfs_info to examine partition contents
sudo mlfs_info /dev/sdb 0  # View system partition
sudo mlfs_info /dev/sdb 1  # View data partition
```

## Technical Details

### I/O Implementation

The tool uses POSIX system calls for block device access:

- **`pread(fd, buf, size, offset)`** - Atomic read at specific offset
- **`pwrite(fd, buf, size, offset)`** - Atomic write at specific offset
- **`fsync(fd)`** - Ensure data is written to physical media
- **`O_SYNC`** flag - Synchronous I/O for data integrity

These system calls are thread-safe and don't modify the file descriptor position, making them ideal for block device access.

### Sector Alignment

All I/O operations are aligned to 512-byte sectors:
- LBA (Logical Block Address) = sector number
- Byte offset = LBA × 512
- MLFS blocks are always multiples of sector size

### Device Size Detection

The tool attempts to detect device size using:
1. `BLKGETSIZE64` ioctl (works for block devices)
2. `lseek()` fallback (works for regular files during testing)

### Permissions

Block device access typically requires:
- **Read-only access**: May work without root on some systems
- **Read-write access**: Almost always requires root/sudo

This is a Linux kernel security measure to prevent unauthorized access to raw disk devices.

## Integration with Other Tools

### Using with mlfs_info

The `mlfs_info` tool can read block devices directly:

```bash
# Examine partition structure
sudo mlfs_info /dev/sdb 0

# List all partitions
sudo mlfs_info /dev/sdb
```

### Using with MLFS CLI

Currently, the MLFS CLI only supports image files, not block devices. To work around this:

```bash
# Option 1: Create a disk image and copy to device
dd if=mlfs_image.img of=/dev/sdb bs=1M

# Option 2: Create a loop device (Linux only)
sudo losetup /dev/loop0 /dev/sdb
# Then use CLI with /dev/loop0
```

## Kernel Driver Path

This tool demonstrates userspace MLFS access. To create a full kernel driver:

### Step 1: Kernel Module Structure

Create a Linux kernel module that:
1. Registers MLFS as a filesystem type using `register_filesystem()`
2. Implements VFS operations (`file_operations`, `inode_operations`, etc.)
3. Uses kernel block I/O subsystem (`submit_bio`, `mpage_readpage`, etc.)
4. Handles page cache integration for performance
5. Implements write-back caching with journal if needed

### Step 2: Key Kernel APIs

```c
// In kernel module
#include <linux/fs.h>
#include <linux/blkdev.h>
#include <linux/buffer_head.h>

static struct file_system_type mlfs_fs_type = {
    .owner      = THIS_MODULE,
    .name       = "mlfs",
    .mount      = mlfs_mount,
    .kill_sb    = mlfs_kill_sb,
};

module_init(mlfs_init);
module_exit(mlfs_exit);
```

### Step 3: VFS Integration

Implement standard Linux VFS operations:
- `mlfs_mount()` - Mount filesystem
- `mlfs_read_super()` - Read superblock
- `mlfs_inode_operations` - File/directory operations
- `mlfs_file_operations` - Read/write/seek operations
- `mlfs_address_space_operations` - Page cache operations

### Step 4: Block I/O

Use kernel block layer:
- `sb_bread()` / `sb_getblk()` for block buffer operations
- `mark_buffer_dirty()` for write-back
- `sync_dirty_buffer()` for synchronous writes

### Step 5: Testing

1. Test with this userspace tool first
2. Develop kernel module incrementally
3. Use QEMU/KVM for safe kernel development
4. Test with real hardware (CompactFlash, SD cards)

## Troubleshooting

### "Permission denied" when opening device

**Solution:** Use `sudo`:
```bash
sudo mlfs_blockdev /dev/sdb info
```

### "Device is busy" error

**Cause:** Device is mounted or in use by another process.

**Solution:**
```bash
# Check what's using it
lsof /dev/sdb
# Unmount if mounted
sudo umount /dev/sdb1
# Try again
sudo mlfs_blockdev /dev/sdb info
```

### Accidentally used wrong device

**If you haven't confirmed "YES" yet:** Cancel immediately (Ctrl+C).

**If operation already completed:** Data is likely lost. Professional data recovery services might be able to help for critical data.

### Device size shows as 0 or incorrect

**Cause:** Device might be failing or kernel hasn't recognized it.

**Solution:**
```bash
# Rescan SCSI bus
echo "- - -" | sudo tee /sys/class/scsi_host/host*/scan
# Check dmesg for errors
dmesg | tail -20
```

## Comparison: File vs Block Device

|Feature|Image File (`mlfs` CLI)|Block Device (`mlfs_blockdev`)|
|-------|----------------------|------------------------------|
|**Access Method**|`fopen()`, `fread()`, `fwrite()`|`open()`, `pread()`, `pwrite()`|
|**Requires Root**|No|Yes (for write)|
|**Safety**|Safe - just a file|Dangerous - can destroy disks|
|**Performance**|Limited by filesystem cache|Direct hardware access|
|**Use Case**|Development, testing, simulation|Real hardware, production|
|**Portability**|Works everywhere|Linux-specific|

## Future Enhancements

Possible improvements for this tool:

1. **Mount Support**: Add read-only mounting capability
2. **File Operations**: List, create, read files directly (without CLI)
3. **Interactive Mode**: Command-line interface like `mlfs` CLI
4. **Batch Operations**: Script support for automated setup
5. **Integrity Checking**: Verify filesystem consistency
6. **Backup/Restore**: Clone partitions between devices
7. **Statistics**: Show detailed usage and performance metrics
8. **Auto-detection**: Scan for MLFS partitions on all devices

## See Also

- [MLFS CLI](../cli/README.md) - For working with image files
- [mlfs_info](../mlfs_info/README.md) - Filesystem analysis tool
- [MLFS Library](../../lib/README.md) - Core library documentation
- Linux Block Device Programming - Kernel documentation
- `man 2 pread` - POSIX read at offset
- `man 2 pwrite` - POSIX write at offset
- `man 2 ioctl_list` - Device ioctl operations

## Author & License

Part of the MicroLind File System (MLFS) project.

See [LICENSE.md](../../LICENSE.md) for licensing information.


