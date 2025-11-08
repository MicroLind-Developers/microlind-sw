# MLFS Kernel Module

A Linux kernel module that integrates MLFS (MicroLind File System) with the Linux VFS (Virtual File System), allowing you to mount MLFS partitions directly in Linux.

## Status

**Version:** 0.4.0  
**Implementation:** ✅ Full read-write support with statistics tracking  
**Compatibility:** 100% binary-compatible with userspace MLFS library  
**Kernel Support:** Linux 5.x, 6.x (tested on 6.14)

## Features Overview

### Core Functionality ✅
- ✅ **Mount/Unmount** - Standard Linux mount command integration
- ✅ **File Operations** - Read, write, create, delete files
- ✅ **Directory Operations** - Create, delete, list directories  
- ✅ **Multi-Partition Support** - Mount multiple MLFS partitions simultaneously
- ✅ **Proper VFS Integration** - Full Linux VFS compatibility
- ✅ **Block Allocation** - Dynamic block allocation with bitmap management
- ✅ **Synchronization** - fsync() support for data integrity

### Monitoring & Statistics ✅
- ✅ **Proc Filesystem** - Real-time statistics via `/proc/fs/mlfs/<device>/stats`
- ✅ **Operation Counters** - Track reads, writes, creates, deletes
- ✅ **Space Usage** - Monitor free/used blocks and bytes
- ✅ **Performance Metrics** - Bytes transferred, operation counts
- ✅ **Error Tracking** - Count filesystem errors

### Developer Features ✅
- ✅ **Debug Mode** - Verbose kernel logging with `debug=1` parameter
- ✅ **Modular Design** - Separated proc filesystem code
- ✅ **Atomic Statistics** - Thread-safe operation counters

### Limitations ⏳
- ⏳ **Page Cache Integration** - Direct I/O only (no page cache)
- ⏳ **Read-ahead** - No read-ahead optimization
- ⏳ **Single-Extent Files** - No indirect extent support yet
- ❌ **Extended Attributes** - Not implemented
- ❌ **Symbolic Links** - Not supported
- ❌ **Memory-Mapped Files** - mmap() not implemented
- ❌ **Journaling** - No journal for crash recovery

## Prerequisites

### Required Packages

```bash
# Ubuntu/Debian
sudo apt-get install build-essential linux-headers-$(uname -r)

# RHEL/CentOS/Fedora
sudo yum install kernel-devel kernel-headers
# or
sudo dnf install kernel-devel kernel-headers

# Arch Linux
sudo pacman -S linux-headers
```

### Kernel Configuration

The following kernel options must be enabled (they usually are by default):
- `CONFIG_BLOCK` - Block layer support
- `CONFIG_EXT2_FS` or similar - Example filesystem code is helpful

## Building

### Quick Build

```bash
cd mlfs/kmod
make
```

This will create `mlfs.ko` - the kernel module file.

### Build Output

The module now compiles from multiple source files:

```
make -C /lib/modules/6.x.x-xxx/build M=/path/to/mlfs/kmod modules
make[1]: Entering directory '/usr/src/linux-headers-6.x.x-xxx'
  CC [M]  /path/to/mlfs/kmod/mlfs_module.o
  CC [M]  /path/to/mlfs/kmod/mlfs_proc.o
  LD [M]  /path/to/mlfs/kmod/mlfs.o
  MODPOST /path/to/mlfs/kmod/Module.symvers
  CC [M]  /path/to/mlfs/kmod/mlfs.mod.o
  LD [M]  /path/to/mlfs/kmod/mlfs.ko
  BTF [M] /path/to/mlfs/kmod/mlfs.ko
make[1]: Leaving directory '/usr/src/linux-headers-6.x.x-xxx'
```

Files compiled:
- `mlfs_module.c` → Main VFS implementation
- `mlfs_proc.c` → Proc filesystem support
- Both linked into `mlfs.ko`

### Clean Build

```bash
make clean
```

## Installation

### Temporary Installation (Testing)

```bash
# Load the module
sudo insmod mlfs.ko

# Or with debug messages
sudo insmod mlfs.ko debug=1

# Verify it's loaded
lsmod | grep mlfs
dmesg | grep mlfs
```

### Permanent Installation

```bash
# Install to system modules directory
sudo make install

# Load module automatically at boot
echo "mlfs" | sudo tee -a /etc/modules

# Load now
sudo modprobe mlfs
```

## Usage

### Basic Mounting

```bash
# Create mount point
sudo mkdir -p /mnt/mlfs

# Mount partition 0 (default)
sudo mount -t mlfs /dev/sdb /mnt/mlfs

# Mount specific partition
sudo mount -t mlfs -o partition=1 /dev/sdb /mnt/mlfs

# Verify mount
mount | grep mlfs
df -h /mnt/mlfs
```

### Accessing Files

```bash
# List directory
ls -la /mnt/mlfs

# Read file
cat /mnt/mlfs/readme.txt

# Copy file from MLFS
cp /mnt/mlfs/data.bin /tmp/

# Search for files
find /mnt/mlfs -name "*.txt"

# Show filesystem info
stat -f /mnt/mlfs
```

### Working with Files and Directories

The kernel module provides full read-write access to MLFS filesystems:

```bash
# Create files
echo "Hello, MLFS!" > /mnt/mlfs/test.txt

# Create directories
mkdir /mnt/mlfs/mydir

# Copy files
cp /etc/hosts /mnt/mlfs/mydir/

# Delete files
rm /mnt/mlfs/test.txt

# Delete directories
rmdir /mnt/mlfs/mydir

# Write data
dd if=/dev/urandom of=/mnt/mlfs/random.dat bs=1K count=100

# Verify data integrity
md5sum /mnt/mlfs/random.dat
```

### Viewing Filesystem Statistics

**New in v0.4.0:** Each mounted MLFS filesystem automatically creates comprehensive statistics at `/proc/fs/mlfs/<device>/stats`

#### Quick View

```bash
# View all statistics
cat /proc/fs/mlfs/sdb/stats

# Monitor in real-time
watch -n 1 'cat /proc/fs/mlfs/sdb/stats'

# Extract specific metrics
grep "Read Operations:" /proc/fs/mlfs/sdb/stats
grep "Free Blocks:" /proc/fs/mlfs/sdb/stats
grep "Usage:" /proc/fs/mlfs/sdb/stats
```

#### Statistics Output Format

```
MLFS Filesystem Statistics
==========================

Device Information:
-------------------
Device:           sdb
Partition:        0
Partition LBA:    2048

Block Configuration:
--------------------
Block Size:       2048 bytes
Sectors/Block:    4

Space Usage:
------------
Total Blocks:     1024
Used Blocks:      45
Free Blocks:      979
Usage:            4%

Total Space:      2097152 bytes (2048 KB, 2 MB)
Used Space:       92160 bytes (90 KB, 0 MB)
Free Space:       2004992 bytes (1958 KB, 1 MB)

Filesystem Layout:
------------------
Bitmap Start:     1
Bitmap Blocks:    1
Root Dir Block:   2
Root Dir Blocks:  1
Entries/Block:    16

Operation Statistics:
---------------------
Read Operations:  127
Write Operations: 45
Read Bytes:       65536 (64 KB, 0 MB)
Write Bytes:      32768 (32 KB, 0 MB)
Errors:           0

File/Directory Operations:
--------------------------
Directory Lookups: 89
Files Created:     12
Files Deleted:     3
Dirs Created:      5
Dirs Deleted:      2
```

#### What Each Statistic Means

| Statistic | Description |
|-----------|-------------|
| **Read Operations** | Number of successful file read operations |
| **Write Operations** | Number of successful file write operations |
| **Read Bytes** | Total bytes read from files |
| **Write Bytes** | Total bytes written to files |
| **Errors** | Number of I/O errors encountered |
| **Directory Lookups** | Number of directory lookups (ls, find, etc.) |
| **Files Created** | Number of files created |
| **Files Deleted** | Number of files deleted |
| **Dirs Created** | Number of directories created |
| **Dirs Deleted** | Number of directories deleted |

#### Using Statistics for Monitoring

```bash
# Track write activity
watch -n 1 'grep "Write Operations:" /proc/fs/mlfs/sdb/stats'

# Monitor space usage
while true; do
    clear
    echo "=== MLFS Space Usage ==="
    grep -A 3 "Space Usage:" /proc/fs/mlfs/sdb/stats
    sleep 2
done

# Create a simple monitoring script
cat > monitor_mlfs.sh << 'EOF'
#!/bin/bash
DEVICE=${1:-sdb}
STATS="/proc/fs/mlfs/$DEVICE/stats"

if [ ! -f "$STATS" ]; then
    echo "Error: $STATS not found"
    exit 1
fi

echo "Monitoring /proc/fs/mlfs/$DEVICE/stats"
echo "Press Ctrl+C to exit"
echo ""

while true; do
    clear
    cat "$STATS"
    sleep 1
done
EOF
chmod +x monitor_mlfs.sh
./monitor_mlfs.sh sdb
```

#### Statistics Collection is Automatic

- **No Configuration Needed** - Statistics are automatically enabled
- **Real-time Updates** - Counters update immediately on each operation
- **Thread-safe** - Uses atomic counters for SMP safety
- **Low Overhead** - Minimal performance impact
- **Per-filesystem** - Each mounted filesystem has its own statistics

### Unmounting

```bash
# Unmount filesystem
sudo umount /mnt/mlfs

# Unload module (if no longer needed)
sudo rmmod mlfs
```

## Mount Options

| Option | Description | Example |
|--------|-------------|---------|
| `partition=N` | Mount partition N (0-15) | `-o partition=1` |

### Examples

```bash
# Mount partition 0 (default)
sudo mount -t mlfs /dev/sdb /mnt/mlfs

# Mount partition 1
sudo mount -t mlfs -o partition=1 /dev/sdb /mnt/mlfs1

# Mount partition 2 read-only (already enforced, but explicit)
sudo mount -t mlfs -o partition=2,ro /dev/sdc /mnt/mlfs2
```

## Complete Workflow Example

### Step 1: Prepare Device with MLFS

```bash
# Create MLFS partition table and filesystem
sudo mlfs_blockdev /dev/sdb format
sudo mlfs_blockdev /dev/sdb mkpart 1 32 4096 system
sudo mlfs_blockdev /dev/sdb mkfs 0

# Verify with info tool
sudo mlfs_info /dev/sdb 0
```

### Step 2: Build and Load Module

```bash
cd mlfs/kmod
make
sudo insmod mlfs.ko debug=1
```

### Step 3: Mount and Use

```bash
sudo mkdir -p /mnt/mlfs
sudo mount -t mlfs -o partition=0 /dev/sdb /mnt/mlfs

# Browse filesystem
ls -la /mnt/mlfs/

# Read files (once they exist)
cat /mnt/mlfs/readme.txt
```

### Step 4: Cleanup

```bash
sudo umount /mnt/mlfs
sudo rmmod mlfs
```

## Debugging

### Enable Debug Messages

```bash
# Load with debug enabled
sudo insmod mlfs.ko debug=1

# Watch kernel messages
sudo dmesg -w | grep mlfs
```

### Common Debug Output

```
mlfs: MicroLind File System v0.4.0 (full read-write with statistics)
mlfs: Filesystem registered successfully
mlfs: Created /proc/fs/mlfs
mlfs: Filling super block
mlfs: Reading partition table (partition 0)
mlfs: Partition 0 starts at LBA 2048
mlfs: Reading superblock from LBA 2048
mlfs: Superblock: block_size=4096, total_blocks=8192, free_blocks=8150, root_dir=2, spb=8
mlfs: Mounted partition 0 (block size 4096, 8192 blocks)
mlfs: Created /proc/fs/mlfs/sdb/stats
mlfs: Reading directory inode 1 at pos 0
mlfs: Looking up 'readme.txt' in directory inode 1
mlfs: Creating inode 131074 for 'readme.txt'
mlfs: Reading 256 bytes from inode 131074 at offset 0
mlfs: create: test.txt in dir inode 1
mlfs: Allocating 1 blocks (free: 8150)
mlfs: Allocated blocks 10-10 (free: 8149)
mlfs: mkdir: newdir in dir inode 1
```

### Troubleshooting

#### "No such device"
```bash
# Check device exists
ls -l /dev/sdb

# Check partition table
sudo mlfs_blockdev -r /dev/sdb info
```

#### "Invalid argument" on mount
```bash
# Verify MLFS filesystem exists
sudo mlfs_info /dev/sdb 0

# Check dmesg for specific error
dmesg | tail -20
```

#### "Operation not permitted"
```bash
# Need root for mounting
sudo mount -t mlfs ...

# Check module is loaded
lsmod | grep mlfs
```

#### Module won't load
```bash
# Check for errors
sudo dmesg | grep mlfs

# Verify kernel headers match
uname -r
ls /lib/modules/$(uname -r)/build
```

## Architecture

### VFS Integration

```
User Space:     open("/mnt/mlfs/file.txt")
                       ↓
VFS Layer:      File Operations → mlfs_file_operations
                Inode Operations → mlfs_dir_inode_operations
                Super Operations → mlfs_super_ops
                       ↓
MLFS Module:    Read superblock, directories, files
                       ↓
Block Layer:    sb_bread() → read physical blocks
                       ↓
Device Driver:  /dev/sdb → CompactFlash hardware
```

### Key Components

**Module Initialization (`mlfs_init`)**
- Registers filesystem with VFS (`register_filesystem`)
- Creates inode cache
- Returns to kernel

**Mount (`mlfs_mount` → `mlfs_fill_super`)**
- Reads partition table from LBA 0
- Finds requested partition's start LBA
- Reads MLFS superblock
- Creates root inode
- Returns super_block to VFS

**Directory Listing (`mlfs_readdir`)**
- Reads directory block
- Parses mlfs_dentry structures
- Emits entries to VFS via `dir_emit`

**File Lookup (`mlfs_lookup`)**
- Searches directory for name
- Creates inode if found
- Returns dentry to VFS

**File Read (`mlfs_read`)**
- Calculates block number from offset
- Reads blocks using `sb_bread`
- Copies data to user space

## Limitations (Current Version)

### Performance

- No page cache integration (direct block reads)
- No read-ahead optimization
- Single-extent files only (no indirect extents)
- No directory entry caching

### Features

- No extended attributes
- No symbolic links
- No special files (devices, fifos, sockets)
- No journaling

## Roadmap

### Phase 1: Read-Only (✅ Completed)
- [x] Basic VFS integration
- [x] Mount/unmount
- [x] Directory listing
- [x] File reading
- [x] Multi-partition support

### Phase 2: Write Support (✅ Completed)
- [x] File creation
- [x] File writing
- [x] File deletion
- [x] Directory creation/deletion
- [x] Bitmap allocation
- [x] Proper error handling for disk full
- [x] Filesystem statistics via /proc

### Phase 3: Performance (⏳ Next)
- [ ] Page cache integration (`address_space_operations`)
- [ ] Read-ahead support
- [ ] Directory entry caching (dcache)
- [ ] Inode caching optimization

### Phase 4: Advanced Features (🔮 Future)
- [ ] Multi-extent files (indirect extent blocks)
- [ ] Extended attributes
- [ ] Symbolic links
- [ ] Timestamp updates
- [ ] Journaling for reliability

## Testing

### Automated Test Script

The repository includes a comprehensive test script for proc filesystem statistics:

```bash
cd mlfs/kmod/tests
sudo ./test_proc_stats.sh
```

This script will:
1. Load the MLFS kernel module
2. Create a test image and format it
3. Mount the filesystem
4. Create test files and directories
5. Display statistics at each step
6. Verify proc entry creation and cleanup
7. Clean up everything automatically

### Manual Testing with Loop Device (Safe)

```bash
# Create test image
dd if=/dev/zero of=/tmp/test.img bs=1M count=64

# Setup MLFS on it
sudo mlfs_blockdev /tmp/test.img format
sudo mlfs_blockdev /tmp/test.img mkpart 1 32 4096 test
sudo mlfs_blockdev /tmp/test.img mkfs 0

# Create loop device
sudo losetup /dev/loop0 /tmp/test.img

# Mount via kernel module
sudo insmod mlfs.ko debug=1
sudo mount -t mlfs -o partition=0 /dev/loop0 /mnt/mlfs

# Test basic operations
ls -la /mnt/mlfs/
echo "test" > /mnt/mlfs/test.txt
cat /mnt/mlfs/test.txt

# Check statistics
cat /proc/fs/mlfs/loop0/stats

# Test file operations
mkdir /mnt/mlfs/testdir
cp /etc/hosts /mnt/mlfs/testdir/
dd if=/dev/urandom of=/mnt/mlfs/random.dat bs=1K count=100
sync

# Verify statistics updated
cat /proc/fs/mlfs/loop0/stats | grep "Write Operations"

# Cleanup
sudo umount /mnt/mlfs
sudo losetup -d /dev/loop0
sudo rmmod mlfs
```

### Comprehensive Test Suite

```bash
#!/bin/bash
# Complete MLFS kernel module test

set -e

echo "=== MLFS Kernel Module Test Suite ==="

# 1. Build module
echo "Building module..."
make clean && make

# 2. Load module
echo "Loading module..."
sudo rmmod mlfs 2>/dev/null || true
sudo insmod mlfs.ko debug=1

# 3. Setup test device
echo "Setting up test device..."
dd if=/dev/zero of=/tmp/mlfs_test.img bs=1M count=128
sudo losetup /dev/loop0 /tmp/mlfs_test.img
sudo ../build/tools/mlfs_blockdev/mlfs_blockdev /dev/loop0 format
sudo ../build/tools/mlfs_blockdev/mlfs_blockdev /dev/loop0 mkpart 1 32 4096 test
sudo ../build/tools/mlfs_blockdev/mlfs_blockdev /dev/loop0 mkfs 0

# 4. Mount filesystem
echo "Mounting filesystem..."
sudo mkdir -p /mnt/mlfs_test
sudo mount -t mlfs -o partition=0 /dev/loop0 /mnt/mlfs_test

# 5. Test file operations
echo "Testing file operations..."
echo "Hello, MLFS!" | sudo tee /mnt/mlfs_test/hello.txt
sudo mkdir /mnt/mlfs_test/testdir
sudo cp /etc/hosts /mnt/mlfs_test/testdir/
sudo dd if=/dev/urandom of=/mnt/mlfs_test/random.dat bs=1K count=50

# 6. Verify operations
echo "Verifying operations..."
[ -f /mnt/mlfs_test/hello.txt ] || { echo "FAIL: hello.txt not found"; exit 1; }
[ -d /mnt/mlfs_test/testdir ] || { echo "FAIL: testdir not found"; exit 1; }
[ -f /mnt/mlfs_test/testdir/hosts ] || { echo "FAIL: hosts not found"; exit 1; }

# 7. Check statistics
echo "Checking statistics..."
if [ -f /proc/fs/mlfs/loop0/stats ]; then
    cat /proc/fs/mlfs/loop0/stats
    
    # Verify counters are non-zero
    READS=$(grep "Read Operations:" /proc/fs/mlfs/loop0/stats | awk '{print $3}')
    WRITES=$(grep "Write Operations:" /proc/fs/mlfs/loop0/stats | awk '{print $3}')
    
    [ "$READS" -gt 0 ] || { echo "FAIL: No read operations recorded"; exit 1; }
    [ "$WRITES" -gt 0 ] || { echo "FAIL: No write operations recorded"; exit 1; }
    
    echo "✓ Statistics verified"
else
    echo "FAIL: Proc stats not found"
    exit 1
fi

# 8. Test deletion
echo "Testing deletion..."
sudo rm /mnt/mlfs_test/testdir/hosts
sudo rmdir /mnt/mlfs_test/testdir

# 9. Cleanup
echo "Cleaning up..."
sudo umount /mnt/mlfs_test
sudo losetup -d /dev/loop0
rm /tmp/mlfs_test.img
sudo rmmod mlfs

echo "=== All tests passed! ==="
```

### Test with Real Hardware

```bash
# Identify device (be CAREFUL!)
lsblk

# Setup MLFS (DESTROYS DATA!)
sudo mlfs_blockdev /dev/sdb format
sudo mlfs_blockdev /dev/sdb mkpart 1 32 4096 test
sudo mlfs_blockdev /dev/sdb mkfs 0

# Mount and test
sudo insmod mlfs.ko debug=1
sudo mount -t mlfs -o partition=0 /dev/sdb /mnt/mlfs
ls /mnt/mlfs/
sudo umount /mnt/mlfs
sudo rmmod mlfs
```

## Development

### Adding Write Support

Key areas to implement:

1. **Remove read-only flag** in `mlfs_fill_super`:
   ```c
   // sb->s_flags |= SB_RDONLY;  /* Remove this line */
   ```

2. **Implement write operations** in `mlfs_file_operations`:
   ```c
   .write = mlfs_write,
   .write_iter = mlfs_write_iter,
   ```

3. **Implement create operations** in `mlfs_dir_inode_operations`:
   ```c
   .create = mlfs_create,
   .unlink = mlfs_unlink,
   .mkdir = mlfs_mkdir,
   .rmdir = mlfs_rmdir,
   ```

4. **Implement bitmap allocation**:
   ```c
   int mlfs_alloc_block(struct super_block *sb);
   void mlfs_free_block(struct super_block *sb, unsigned long block);
   ```

5. **Add buffer cache modifications**:
   ```c
   mark_buffer_dirty(bh);
   sync_dirty_buffer(bh);
   ```

## What the Kernel Module Can Do

### Supported Operations

| Operation | Status | Details |
|-----------|--------|---------|
| **Mount filesystem** | ✅ Full | Mount any MLFS partition via standard mount command |
| **Unmount filesystem** | ✅ Full | Clean unmount with resource cleanup |
| **Read files** | ✅ Full | Read any file, any size, any offset |
| **Write files** | ✅ Full | Write to existing files or create new ones |
| **Create files** | ✅ Full | Create new files with initial block allocation |
| **Delete files** | ✅ Full | Delete files and reclaim blocks |
| **Create directories** | ✅ Full | Create new directories |
| **Delete directories** | ✅ Full | Delete empty directories |
| **List directories** | ✅ Full | List directory contents (ls, find, etc.) |
| **Stat files** | ✅ Full | Get file metadata (size, times, mode) |
| **Seek in files** | ✅ Full | lseek() to any position |
| **Sync data** | ✅ Full | fsync() to flush data to disk |
| **Multiple mounts** | ✅ Full | Mount multiple partitions simultaneously |
| **Block allocation** | ✅ Full | Dynamic block allocation from bitmap |
| **Statistics** | ✅ Full | Real-time statistics via /proc |

### What is NOT Supported (Will probably never...):

| Feature | Status | Workaround |
|---------|--------|------------|
| **Memory-mapped files** | ❌ | Use read()/write() instead of mmap() |
| **Page cache** | ❌ | All I/O is direct (slower but simpler) |
| **Read-ahead** | ❌ | Reads happen on-demand only |
| **Extended attributes** | ❌ | No xattr support |
| **Symbolic links** | ❌ | Use regular files or directories |
| **Hard links** | ❌ | Each file is independent |
| **File locking** | ❌ | Use userspace locking |
| **Indirect extents** | ❌ | Files limited to 4 extents (inline) |
| **Journaling** | ❌ | No crash recovery (use sync often) |
| **Quotas** | ❌ | No disk quota support |
| **ACLs** | ❌ | Basic Unix permissions only |

### Code Structure

**Version 0.4.0** introduced a modular design with separated concerns:

```
mlfs/kmod/
├── mlfs_module.c           (Main VFS implementation)
│   ├── Module init/exit
│   ├── Filesystem registration
│   ├── Mount/unmount
│   │   ├── Parse partition table
│   │   ├── Read superblock
│   │   └── Create root inode
│   ├── Super operations
│   │   ├── put_super
│   │   ├── statfs
│   │   ├── sync_fs
│   │   └── show_options
│   ├── Inode operations
│   │   ├── lookup
│   │   ├── create
│   │   ├── mkdir
│   │   ├── unlink
│   │   └── rmdir
│   ├── File operations
│   │   ├── read
│   │   ├── write
│   │   ├── fsync
│   │   └── readdir
│   └── Helper functions
│       ├── Block I/O
│       ├── Bitmap allocation
│       └── Directory management
│
├── mlfs_proc.c              (Proc filesystem)
│   ├── Statistics display
│   ├── Proc entry management
│   └── Real-time metrics
│
├── mlfs_module.h            (Core data structures)
│   ├── On-disk structures
│   ├── In-memory structures
│   └── Helper macros
│
└── mlfs_proc.h              (Statistics API)
    ├── Counter definitions
    ├── Atomic operations
    └── Proc functions

Compiled output: mlfs.ko (single kernel module)
```

### Data Structure Compatibility

The kernel module uses **100% binary-compatible** on-disk structures with the userspace library:

| Structure | Size | Compatibility |
|-----------|------|---------------|
| `mlfs_extent` | 8 bytes | ✅ Identical to userspace `mlfs_extent_t` |
| `mlfs_dentry` | 128 bytes | ✅ Identical to userspace `mlfs_dentry_t` |
| `mlfs_superblock` | 512 bytes | ✅ Identical to userspace `mlfs_superblock_t` |
| `mlpt_entry` | 24 bytes | ✅ Identical to userspace `mlpt_entry_t` |
| `mlpt` | 512 bytes | ✅ Identical to userspace `mlpt_t` |

This means:
- ✅ Filesystems created with CLI tools can be mounted by the kernel
- ✅ Files written by the kernel can be read by CLI tools
- ✅ Full interoperability between kernel and userspace

## In this version (0.4.0):

### Code Refactoring
- **Modular Design**: Split code into `mlfs_module.c` (VFS) and `mlfs_proc.c` (statistics)
- **Better Organization**: Separated concerns for improved maintainability
- **Cleaner Headers**: `mlfs_module.h` for core, `mlfs_proc.h` for proc API

### Statistics Tracking
- **Operation Counters**: Track reads, writes, creates, deletes
- **Byte Counters**: Monitor total bytes read and written
- **Error Tracking**: Count filesystem errors
- **Atomic Counters**: Thread-safe with `atomic64_t`
- **Real-time Updates**: Statistics update immediately on each operation

### Proc Filesystem Enhancement
- **Comprehensive Stats**: `/proc/fs/mlfs/<device>/stats` shows detailed information
- **Multiple Sections**: Device info, space usage, operations, file/dir operations
- **Easy Monitoring**: Use standard tools like `cat`, `grep`, `watch`
- **Per-filesystem**: Each mounted filesystem has independent statistics
- **Automatic Management**: Proc entries created on mount, removed on unmount

### Developer Experience
- **Better Debug Output**: More informative kernel messages
- **Test Scripts**: Included `test_proc_stats.sh` for validation
- **Documentation**: Comprehensive README with examples
- **100% Compatibility**: Binary-compatible with userspace library

### Performance
- **No Overhead**: Statistics collection has minimal impact
- **Atomic Operations**: SMP-safe counter updates
- **On-demand Display**: Statistics calculated only when read

## Resources

- [Linux Kernel Documentation - VFS](https://www.kernel.org/doc/html/latest/filesystems/vfs.html)
- [Writing a Simple Filesystem](https://www.kernel.org/doc/html/latest/filesystems/index.html)
- [Linux Device Drivers, 3rd Edition](https://lwn.net/Kernel/LDD3/)
- [Kernel Module Programming Guide](https://tldp.org/LDP/lkmpg/2.6/html/)
- [Proc Filesystem Documentation](https://www.kernel.org/doc/html/latest/filesystems/proc.html)

## License

GPL v2 (required for kernel modules)

## Contributing

When contributing to the kernel module:
1. Follow Linux kernel coding style (`scripts/checkpatch.pl`)
2. Test thoroughly with both loop devices and real hardware
3. Check for memory leaks and proper resource cleanup
4. Run with debug enabled and verify dmesg output
5. Document any new features or changes

## See Also

### Related Tools and Documentation
- **[MLFS Library](../lib/README.md)** - Userspace MLFS library with 100% compatible data structures
- **[mlfs_blockdev](../tools/mlfs_blockdev/README.md)** - Block device management tool for formatting and partitioning
- **[mlfs_info](../tools/mlfs_info/README.md)** - Filesystem information tool
- **[MLFS CLI](../tools/cli/README.md)** - Command-line interface for MLFS operations

### Test Scripts (in tests/ directory)
- `tests/test_proc_stats.sh` - Automated test for proc filesystem statistics
- `tests/test_kmod.sh` - General kernel module functionality test
- `tests/test_write.sh` - Write operation tests
- `tests/test_full_rw.sh` - Full read-write operation tests
- `tests/test_with_files.sh` - CompactFlash test with files
- `tests/test_files_local.sh` - Local test with files (loop device)
- `tests/safe_test.sh` - Safe testing script for loop devices

### Module Files
- `mlfs_module.c` - Main VFS implementation
- `mlfs_module.h` - Core data structures
- `mlfs_proc.c` - Proc filesystem support
- `mlfs_proc.h` - Statistics API
- `Makefile` - Build configuration

