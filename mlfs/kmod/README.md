# MLFS Kernel Module

A Linux kernel module that integrates MLFS (MicroLind File System) with the Linux VFS (Virtual File System), allowing you to mount MLFS partitions directly in Linux.

## Status

**Current Implementation:** ✅ Read-only support  
**Planned:** Write support, caching, performance optimizations

## Features

- ✅ Mount MLFS partitions using standard `mount` command
- ✅ Read files and directories through standard Linux APIs
- ✅ Multi-partition support via mount options
- ✅ Proper VFS integration (superblock, inodes, dentries)
- ✅ Standard file operations (read, seek, readdir)
- ✅ Debug mode for troubleshooting
- ⏳ Write operations (TODO)
- ⏳ Page cache integration (TODO)
- ⏳ Memory-mapped files (TODO)

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

```
make -C /lib/modules/6.x.x-xxx/build M=/path/to/mlfs/kmod modules
make[1]: Entering directory '/usr/src/linux-headers-6.x.x-xxx'
  CC [M]  /path/to/mlfs/kmod/mlfs_kernel.o
  LD [M]  /path/to/mlfs/kmod/mlfs.o
  MODPOST /path/to/mlfs/kmod/Module.symvers
  CC [M]  /path/to/mlfs/kmod/mlfs.mod.o
  LD [M]  /path/to/mlfs/kmod/mlfs.ko
make[1]: Leaving directory '/usr/src/linux-headers-6.x.x-xxx'
```

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
mlfs: MicroLind File System v0.1.0 (read-only)
mlfs: Filesystem registered successfully
mlfs: Filling super block
mlfs: Reading partition table (partition 0)
mlfs: Partition 0 starts at LBA 1
mlfs: Reading superblock from LBA 1
mlfs: Superblock: block_size=4096, total_blocks=8192, root_dir=2
mlfs: Mounted partition 0 (block size 4096, 8192 blocks)
mlfs: Reading directory inode 1 at pos 0
mlfs: Looking up 'readme.txt' in directory inode 1
mlfs: Creating inode 65538 for 'readme.txt'
mlfs: Reading 256 bytes from inode 65538 at offset 0
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

### Read-Only

- All mounts are read-only (`-o ro` is enforced)
- Cannot create, modify, or delete files
- Cannot change permissions or timestamps

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

### Phase 1: Read-Only (✅ Current)
- [x] Basic VFS integration
- [x] Mount/unmount
- [x] Directory listing
- [x] File reading
- [x] Multi-partition support

### Phase 2: Write Support (⏳ Next)
- [ ] File creation
- [ ] File writing
- [ ] File deletion
- [ ] Directory creation/deletion
- [ ] Bitmap allocation
- [ ] Proper error handling for disk full

### Phase 3: Performance (🔮 Future)
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

### Test with Loop Device (Safe)

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

# Test operations
ls -la /mnt/mlfs/

# Cleanup
sudo umount /mnt/mlfs
sudo losetup -d /dev/loop0
sudo rmmod mlfs
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

### Code Structure

```
mlfs_kernel.c
├── Module init/exit
├── Filesystem registration
├── Mount/unmount
│   ├── Parse partition table
│   ├── Read superblock
│   └── Create root inode
├── Super operations
│   ├── put_super
│   ├── statfs
│   └── show_options
├── Inode operations
│   └── lookup (find files in directory)
├── File operations
│   ├── read (regular files)
│   └── readdir (directories)
└── Helper functions
    ├── mlfs_iget (create inodes)
    ├── mlfs_read_super
    └── mlfs_read_partition_table
```

## Resources

- [Linux Kernel Documentation - VFS](https://www.kernel.org/doc/html/latest/filesystems/vfs.html)
- [Writing a Simple Filesystem](https://www.kernel.org/doc/html/latest/filesystems/index.html)
- [Linux Device Drivers, 3rd Edition](https://lwn.net/Kernel/LDD3/)
- [Kernel Module Programming Guide](https://tldp.org/LDP/lkmpg/2.6/html/)

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

- [mlfs_blockdev](../tools/mlfs_blockdev/README.md) - Block device management tool
- [MLFS CLI](../cli/README.md) - Userspace filesystem tool
- [MLFS Library](../lib/README.md) - Core library documentation

