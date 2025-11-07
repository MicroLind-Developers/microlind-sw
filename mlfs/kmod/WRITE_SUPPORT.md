# MLFS Write Support

## Overview
MLFS kernel module now supports read-write operations (v0.2.0).

## Implemented Features

### ✅ Core Write Operations
1. **File Writing** (`mlfs_write`)
   - Write to existing files
   - Modify file content at any offset
   - Partial block writes (read-modify-write)
   - Respects existing file size limits
   - **Limitation**: Cannot grow files beyond current size (requires block allocation)

2. **Block I/O** (`mlfs_write_fs_block_data`)
   - Writes filesystem blocks (e.g., 4096 bytes) by aggregating 512-byte sectors
   - Properly handles block size conversion
   - Immediate sync for data safety (`sync_dirty_buffer`)

3. **Sync Operations**
   - `fsync` support for file data
   - `sync_fs` support for filesystem-wide sync
   - Ensures data is written to disk before returning

### Current Capabilities
- ✅ Read files
- ✅ Write to existing files (overwrite)
- ✅ Modify file content
- ✅ Sync data to disk
- ✅ List directories
- ✅ Create new files
- ✅ Delete files
- ✅ Create directories
- ✅ Delete directories
- ✅ Block allocation from bitmap
- ❌ Grow files beyond initial allocation
- ❌ File rename/move
- ❌ Hard links
- ❌ Symbolic links

## Testing

### Full Read-Write Test (Recommended)
```bash
# Run the comprehensive test script
cd /home/erli/private/microlind/microlind-sw/mlfs/kmod
./test_full_rw.sh
```

This tests:
- File creation and deletion
- Directory creation and deletion
- File writing and reading
- Subdirectory operations
- Data persistence

### Basic Write Test
```bash
# Run the basic write test
cd /home/erli/private/microlind/microlind-sw/mlfs/kmod
./test_write.sh
```

### Manual Testing
```bash
# 1. Load module
sudo insmod mlfs.ko

# 2. Mount filesystem
sudo mount -t mlfs -o partition=0 /dev/sda /mnt/mlfs

# 3. Write to existing file
echo "New content" | sudo tee /mnt/mlfs/test.txt

# 4. Verify
cat /mnt/mlfs/test.txt

# 5. Unmount
sudo umount /mnt/mlfs
```

## Future Enhancements

Additional features that could be implemented:

### 1. File Growth (Priority: HIGH)
- Allocate additional blocks for growing files
- Support multiple extents per file
- Update extent information dynamically

### 2. File Operations
- `rename` - Move/rename files and directories
- `link` - Hard link support
- `symlink` - Symbolic link support

### 3. Performance Optimizations
- Delayed allocation for better block allocation
- Write caching to reduce sync overhead
- Bitmap caching for faster allocation

### 4. Reliability
- Journaling for crash recovery
- Filesystem check/repair tool
- Better error handling

## Architecture Notes

### Block Size Handling
The kernel module maintains the superblock's block size at **512 bytes** to match the hardware sector size, but filesystem blocks (e.g., 4096 bytes) are handled through aggregation:

```c
sectors_per_block = fs_block_size / 512
```

This prevents buffer cache corruption while allowing efficient filesystem-level I/O.

### Inode Lifecycle
Custom inode allocation/deallocation is implemented via:
- `mlfs_alloc_inode()` - Allocates from kmem_cache
- `mlfs_destroy_inode()` - Frees to kmem_cache  
- `mlfs_init_once()` - Initializes VFS inode structures (REQUIRED)

### Write Safety
All writes use `sync_dirty_buffer()` to ensure data reaches disk immediately, prioritizing data safety over performance.

## Limitations

### Current Limitations
1. **No file growth**: Can only overwrite existing file content
2. **No file creation**: Cannot create new files
3. **No directory operations**: Cannot create/delete directories
4. **No file deletion**: Cannot delete files
5. **Single extent per file**: No support for fragmented files

### Design Limitations
1. **No journaling**: Crashes during writes may corrupt filesystem
2. **No caching optimization**: Every write syncs immediately (slow)
3. **No extent expansion**: Files are limited to their initial extent

## Performance Considerations

### Current Performance
- **Write speed**: Limited by `sync_dirty_buffer()` (safe but slow)
- **Read speed**: Good (cached through buffer cache)
- **Small writes**: Inefficient (read-modify-write for partial blocks)

### Future Optimizations
1. **Delayed sync**: Use `mark_buffer_dirty()` without immediate sync
2. **Write caching**: Batch writes before syncing
3. **Async I/O**: Allow async writes for better throughput

## Safety Notes

⚠️ **IMPORTANT**: The kernel module now modifies disk data!

1. **Always test on non-critical devices first**
2. **Use loopback devices for testing** (`test_write.sh` does this)
3. **Backup data before testing on real hardware**
4. **Verify writes with the CLI tool** before trusting the module

## Example Usage

### Scenario: Modify configuration file
```bash
# 1. Create filesystem with CLI
cd mlfs/cli/build
./mlfs_cli << EOF
format /tmp/test.img 32
mkpart 1 30 4096 data
mkfs 0
mount 0
touch config.txt
write config.txt "debug=false
log_level=info
"
unmount
close
quit
EOF

# 2. Mount with kernel module
sudo losetup /dev/loop20 /tmp/test.img
sudo insmod mlfs.ko
sudo mkdir -p /mnt/mlfs
sudo mount -t mlfs -o partition=0 /dev/loop20 /mnt/mlfs

# 3. Modify configuration
echo "debug=true" | sudo tee /mnt/mlfs/config.txt

# 4. Verify
cat /mnt/mlfs/config.txt

# 5. Cleanup
sudo umount /mnt/mlfs
sudo losetup -d /dev/loop20
sudo rmmod mlfs

# 6. Verify persistence with CLI
./mlfs_cli << EOF
open /tmp/test.img
mount 0
cat config.txt
unmount
close
quit
EOF
```

## Debugging

### Enable Debug Output
Debug messages are printed to kernel log when `MLFS_DEBUG` is defined:
```bash
# View kernel messages
sudo dmesg | grep mlfs | tail -50
```

### Common Issues

#### 1. "Operation not permitted" when writing
- Check file permissions
- Ensure mounted with write permissions
- Verify not mounted read-only

#### 2. "No space left on device"
- Trying to grow file (not supported yet)
- File extent is full
- Solution: Create file with enough space initially

#### 3. Kernel panic on write
- Likely buffer cache corruption
- Check `sectors_per_block` calculation
- Verify block size alignment

## Testing Checklist

Before deploying:
- [ ] Test basic file writes
- [ ] Test partial block writes
- [ ] Test multiple files
- [ ] Test sync operations
- [ ] Verify data persistence after unmount
- [ ] Test on loopback device
- [ ] Test on real hardware (with backups!)

## Version History

### v0.3.0 (Current)
- **Full read-write support**
- Block allocation from bitmap
- File creation (`create`)
- File deletion (`unlink`)
- Directory creation (`mkdir`)
- Directory deletion (`rmdir`)
- Complete CRUD operations
- All basic filesystem operations functional

### v0.2.0
- Added write support for existing files
- Implemented sync operations
- Fixed inode lifecycle management
- Fixed block size handling

### v0.1.0
- Initial read-only implementation
- Directory listing
- File reading
- Basic VFS integration

