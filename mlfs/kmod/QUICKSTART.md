# MLFS Kernel Module - Quick Start Guide

Get up and running with the MLFS kernel module in 5 minutes!

## Prerequisites

```bash
# Install kernel headers
sudo apt-get install linux-headers-$(uname -r)  # Ubuntu/Debian
sudo yum install kernel-devel                    # RHEL/CentOS
sudo pacman -S linux-headers                     # Arch Linux
```

## Quick Test (Automated)

The easiest way to test the kernel module:

```bash
cd mlfs/kmod
sudo ./test_kmod.sh
```

This script will:
1. ✅ Build the kernel module
2. ✅ Create a test image
3. ✅ Format it with MLFS
4. ✅ Setup a loop device
5. ✅ Load the module
6. ✅ Mount the filesystem
7. ✅ Run basic tests
8. ✅ Show you how to access it

Press Enter when done to cleanup automatically.

## Manual Test (Step by Step)

### Step 1: Build the Module

```bash
cd mlfs/kmod
make
```

Expected output:
```
  CC [M]  .../mlfs_kernel.o
  LD [M]  .../mlfs.o
  ...
  LD [M]  .../mlfs.ko
```

### Step 2: Create Test Image

```bash
# Create 64 MB test image
dd if=/dev/zero of=/tmp/test.img bs=1M count=64

# Format with MLFS
cd ../tools/mlfs_blockdev
sudo ./mlfs_blockdev /tmp/test.img format
sudo ./mlfs_blockdev /tmp/test.img mkpart 1 32 4096 test  
sudo ./mlfs_blockdev /tmp/test.img mkfs 0
```

### Step 3: Setup Loop Device

```bash
sudo losetup /dev/loop0 /tmp/test.img
```

### Step 4: Load Module

```bash
cd ../../kmod
sudo insmod mlfs.ko debug=1
```

Check it loaded:
```bash
lsmod | grep mlfs
sudo dmesg | tail
```

### Step 5: Mount Filesystem

```bash
sudo mkdir -p /mnt/mlfs
sudo mount -t mlfs -o partition=0 /dev/loop0 /mnt/mlfs
```

### Step 6: Test Access

```bash
# List files
ls -la /mnt/mlfs/

# Show stats
df -h /mnt/mlfs
stat -f /mnt/mlfs

# Watch kernel messages
sudo dmesg -w | grep mlfs
```

### Step 7: Cleanup

```bash
sudo umount /mnt/mlfs
sudo losetup -d /dev/loop0
sudo rmmod mlfs
```

## Real Hardware (CompactFlash)

⚠️ **WARNING**: This will DESTROY all data on the device!

### Identify Device

```bash
lsblk
# Look for your CF card, typically /dev/sdb or /dev/sdc
# Double-check size to ensure it's the right device!
```

### Format Device

```bash
# Setup MLFS (DESTROYS ALL DATA!)
sudo mlfs_blockdev /dev/sdb format
sudo mlfs_blockdev /dev/sdb mkpart 1 32 4096 system
sudo mlfs_blockdev /dev/sdb mkfs 0
```

### Mount Device

```bash
# Load module
cd mlfs/kmod
sudo insmod mlfs.ko debug=1

# Mount
sudo mkdir -p /mnt/cf
sudo mount -t mlfs -o partition=0 /dev/sdb /mnt/cf

# Access
ls -la /mnt/cf/
```

### Unmount

```bash
sudo umount /mnt/cf
sudo rmmod mlfs
```

## Troubleshooting

### Module won't load

```bash
# Check for errors
sudo dmesg | grep mlfs

# Verify kernel headers
ls /lib/modules/$(uname -r)/build

# Try rebuilding
make clean && make
```

### Mount fails

```bash
# Check module is loaded
lsmod | grep mlfs

# Check device has MLFS
sudo mlfs_info /dev/sdb 0

# Check kernel messages
sudo dmesg | tail -20
```

### "Operation not permitted"

```bash
# All operations need sudo
sudo mount -t mlfs ...
```

## Next Steps

- Read the full [README.md](README.md) for complete documentation
- Check [Architecture](#architecture) section to understand how it works
- See [Roadmap](#roadmap) for planned features
- Try with real CompactFlash hardware!

## What's Supported

✅ **Working Now (Read-Only):**
- Mounting MLFS partitions
- Listing directories
- Reading files
- Multi-partition support
- Standard Linux tools (ls, cat, cp, find, etc.)

❌ **Not Yet (Coming Soon):**
- Creating files
- Writing to files
- Deleting files
- Creating directories
- Modifying anything

## Example Session

```bash
$ cd mlfs/kmod
$ make
  CC [M]  mlfs_kernel.o
  LD [M]  mlfs.ko

$ sudo insmod mlfs.ko debug=1
$ sudo mount -t mlfs -o partition=0 /dev/sdb /mnt/cf

$ ls -la /mnt/cf/
drwxr-xr-x  2 root root 4096 Nov  6 14:30 .
drwxr-xr-x 23 root root 4096 Nov  6 14:25 ..
-rw-r--r--  1 root root  256 Nov  6 14:30 readme.txt

$ cat /mnt/cf/readme.txt
Hello from MLFS kernel module!

$ sudo umount /mnt/cf
$ sudo rmmod mlfs
```

## Performance Tips

Current implementation is basic (direct block reads). For better performance in future versions:

- Page cache integration (TODO)
- Read-ahead support (TODO)
- Directory caching (TODO)

## Safety Notes

- ✅ Read-only mode is safe - cannot damage filesystem
- ⚠️ Always unmount before removing device
- ⚠️ Don't remove module while mounted
- ⚠️ Backup data before testing on real hardware

## Getting Help

If you encounter issues:

1. Check kernel messages: `sudo dmesg | grep mlfs`
2. Enable debug mode: `sudo insmod mlfs.ko debug=1`
3. Verify MLFS format: `sudo mlfs_info /dev/device 0`
4. Check module info: `modinfo mlfs.ko`
5. Review [README.md](README.md) troubleshooting section

## Fun Facts

- This is a **real Linux filesystem driver**!
- It registers with the VFS layer just like ext4, btrfs, etc.
- Uses standard Linux APIs (sb_bread, generic_file_llseek, etc.)
- Shows up in `/proc/filesystems` when loaded
- Works with all standard Linux tools (ls, find, grep, etc.)

Enjoy your journey into Linux kernel filesystem development! 🚀

