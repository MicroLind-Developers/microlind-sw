# MLFS Kernel Module - Safety Guide

## ⚠️ What Went Wrong?

If you tried mounting `/dev/sda` and got a **kernel panic**, here's what likely happened:

1. **Wrong Device**: `/dev/sda` probably doesn't contain an MLFS filesystem
2. **Corrupted Data**: When the kernel module tried to read the partition table or superblock, it got garbage data
3. **Missing Validation**: The original code didn't validate all fields before using them
4. **Division by Zero**: If block_size was 0, calculating `dentries_per_block` would crash

## 🛡️ Safety Improvements Added

The kernel module now validates:
- ✅ Partition table magic number
- ✅ Superblock magic number  
- ✅ Block size (must be 512-65536, i.e., log2_block_size 9-16)
- ✅ Total blocks (must be > 0)
- ✅ Root directory blocks (must be > 0)
- ✅ Partition existence

If any validation fails, the mount will fail gracefully with an error message instead of crashing.

## 🧪 Safe Testing Methods

### Method 1: Loopback Device (RECOMMENDED)

Use a file-backed virtual block device:

```bash
# Run the automated safe test
cd /home/erli/private/microlind/microlind-sw/mlfs/kmod
sudo ./safe_test.sh
```

This script:
1. Creates a 10MB image file
2. Formats it with MLFS using the CLI
3. Creates a loopback device (`/dev/loop20`)
4. Loads the kernel module
5. Attempts to mount
6. Cleans up automatically

### Method 2: Manual Loopback Testing

```bash
# 1. Create and format image
cd /home/erli/private/microlind/microlind-sw/mlfs
mkdir -p /tmp/mlfs_test
dd if=/dev/zero of=/tmp/mlfs_test/test.img bs=1M count=10

# Format with CLI
./build/cli/mlfs << 'EOF'
open /tmp/mlfs_test/test.img
format
mkpart 1 8 4096 testpart
partition 1
mkfs
exit
EOF

# 2. Setup loopback
sudo losetup /dev/loop20 /tmp/mlfs_test/test.img

# 3. Load module
cd kmod
sudo insmod mlfs.ko debug=1

# 4. Mount
sudo mkdir -p /tmp/mlfs_test/mnt
sudo mount -t mlfs -o partition=0 /dev/loop20 /tmp/mlfs_test/mnt

# 5. Test
ls -la /tmp/mlfs_test/mnt
df -h /tmp/mlfs_test/mnt

# 6. Cleanup
sudo umount /tmp/mlfs_test/mnt
sudo losetup -d /dev/loop20
sudo rmmod mlfs
```

### Method 3: Real Hardware (DANGEROUS - Only After Testing)

**⚠️ WARNING: Only do this after successful loopback testing!**

```bash
# 1. BACKUP YOUR DATA FIRST!
# 2. Make sure you have the RIGHT device (e.g., /dev/sdb for CF card)
# 3. NEVER use /dev/sda unless you're 100% sure!

# Format device with mlfs_blockdev (as root)
sudo /home/erli/private/microlind/microlind-sw/mlfs/build/tools/mlfs_blockdev/mlfs_blockdev /dev/sdX
# Then use: format, mkpart, mkfs commands

# Load module and mount
sudo insmod mlfs.ko debug=1
sudo mount -t mlfs -o partition=0 /dev/sdX /mnt/mlfs
```

## 🔍 Debugging Kernel Issues

### Check Kernel Messages

Always check `dmesg` for errors:

```bash
sudo dmesg | tail -50
```

Look for:
- `mlfs:` messages (our debug output)
- `BUG:` or `Oops:` (kernel crashes)
- Error codes like `-EINVAL`, `-EIO`

### Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `Invalid partition table magic` | Device isn't MLFS formatted | Format with CLI or blockdev tool |
| `Invalid superblock magic` | Partition doesn't have filesystem | Run `mkfs` command |
| `Invalid log2_block_size` | Corrupted superblock | Reformat partition |
| `Partition X does not exist` | Wrong partition number | Use `partition=0` for first partition |
| `Failed to read partition table` | I/O error | Check device connections |

### Enable Debug Mode

Load the module with debugging enabled:

```bash
sudo insmod mlfs.ko debug=1
```

This will log detailed information about mount operations.

### Unload Stuck Module

If the module gets stuck:

```bash
# Check if anything is using it
lsmod | grep mlfs

# Force unmount if needed
sudo umount -f /mnt/mlfs

# Remove module
sudo rmmod mlfs

# If it won't unload, you may need to reboot
```

## 🚨 What To Do If Kernel Panics

1. **DON'T PANIC** - Your system will reboot
2. After reboot, check `/var/log/kern.log` for the panic trace
3. Look for the function that crashed (it will be in the trace)
4. Report the issue with the full kernel log
5. **DO NOT** try mounting the same device again without fixing the code

## 📋 Pre-Flight Checklist

Before mounting ANY device:

- [ ] Is the device properly formatted with MLFS?
- [ ] Have you tested with a loopback device first?
- [ ] Is debug mode enabled (`debug=1`)?
- [ ] Do you have a backup of important data?
- [ ] Are you using the correct device path?
- [ ] Have you checked `dmesg` is clear?

## 🎯 Recommended Testing Workflow

1. **Day 1**: Test with loopback devices only
2. **Day 2**: Test with USB flash drive (expendable)
3. **Day 3**: Test with CompactFlash card (backup first!)
4. **Never**: Test with your primary system disk (`/dev/sda`)

## 🔧 Recovery After Failed Mount

```bash
# 1. Check if module is loaded
lsmod | grep mlfs

# 2. Check if anything is mounted
mount | grep mlfs

# 3. Force unmount if needed
sudo umount -f /path/to/mountpoint

# 4. Unload module
sudo rmmod mlfs

# 5. Check logs
sudo dmesg | tail -100

# 6. If system is unstable, reboot
sudo reboot
```

## 📞 Getting Help

If you encounter issues:

1. Save the output of `dmesg`
2. Note what command you ran
3. Check if the device was properly formatted
4. Provide kernel version: `uname -r`
5. Describe what happened step-by-step

Remember: **Kernel modules can crash your system!** Always test carefully and have backups.


