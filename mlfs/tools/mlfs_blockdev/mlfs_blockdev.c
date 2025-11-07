/****************************** mlfs_blockdev.c ******************************/
/*
 * MLFS Block Device Tool
 * 
 * A utility for working with MLFS filesystems on real block devices
 * (e.g., /dev/sda, CompactFlash cards, SD cards).
 * 
 * This tool provides read-only and read-write access to block devices,
 * with safety features to prevent accidental data loss.
 * 
 * WARNING: Writing to block devices requires root/sudo and can destroy data!
 *          Always use read-only mode (-r) when examining unknown devices.
 */

#define _GNU_SOURCE  // For pread/pwrite
#include "mlfs.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <errno.h>
#include <ctype.h>
#include <stdbool.h>

#define SECTOR_SIZE 512

// Context structure for block device I/O
typedef struct {
    int fd;
    bool read_only;
    const char *device_path;
} blockdev_ctx_t;

// Block device read callback
static int blockdev_read(void *ctx, uint64_t lba, uint32_t count, void *buf)
{
    blockdev_ctx_t *bctx = (blockdev_ctx_t *)ctx;
    
    if(!bctx || bctx->fd < 0) {
        fprintf(stderr, "Error: Invalid device context\n");
        return -1;
    }
    
    uint64_t offset = lba * SECTOR_SIZE;
    size_t bytes_to_read = count * SECTOR_SIZE;
    
    ssize_t result = pread(bctx->fd, buf, bytes_to_read, offset);
    if(result < 0) {
        perror("pread");
        return -1;
    }
    
    if((size_t)result != bytes_to_read) {
        fprintf(stderr, "Error: Short read (expected %zu bytes, got %zd bytes)\n",
                bytes_to_read, result);
        return -1;
    }
    
    return 0;
}

// Block device write callback
static int blockdev_write(void *ctx, uint64_t lba, uint32_t count, const void *buf)
{
    blockdev_ctx_t *bctx = (blockdev_ctx_t *)ctx;
    
    if(!bctx || bctx->fd < 0) {
        fprintf(stderr, "Error: Invalid device context\n");
        return -1;
    }
    
    if(bctx->read_only) {
        fprintf(stderr, "Error: Device is opened read-only\n");
        return -1;
    }
    
    uint64_t offset = lba * SECTOR_SIZE;
    size_t bytes_to_write = count * SECTOR_SIZE;
    
    ssize_t result = pwrite(bctx->fd, buf, bytes_to_write, offset);
    if(result < 0) {
        perror("pwrite");
        return -1;
    }
    
    if((size_t)result != bytes_to_write) {
        fprintf(stderr, "Error: Short write (expected %zu bytes, wrote %zd bytes)\n",
                bytes_to_write, result);
        return -1;
    }
    
    // Sync to ensure data is written to device
    if(fsync(bctx->fd) != 0) {
        perror("fsync");
        return -1;
    }
    
    return 0;
}

// Get block device size in bytes
static int64_t get_device_size(int fd)
{
    uint64_t size_in_bytes = 0;
    
    // Try BLKGETSIZE64 ioctl (works for block devices)
    if(ioctl(fd, BLKGETSIZE64, &size_in_bytes) == 0) {
        return (int64_t)size_in_bytes;
    }
    
    // Fallback: seek to end (works for regular files)
    off_t end = lseek(fd, 0, SEEK_END);
    if(end < 0) {
        return -1;
    }
    lseek(fd, 0, SEEK_SET); // Reset to beginning
    
    return (int64_t)end;
}

// Format device size for human-readable display
static void format_size(uint64_t bytes, char *buf, size_t buf_size)
{
    if(bytes < 1024) {
        snprintf(buf, buf_size, "%lu B", bytes);
    } else if(bytes < 1024 * 1024) {
        snprintf(buf, buf_size, "%.1f KB", bytes / 1024.0);
    } else if(bytes < 1024 * 1024 * 1024) {
        snprintf(buf, buf_size, "%.1f MB", bytes / (1024.0 * 1024.0));
    } else {
        snprintf(buf, buf_size, "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0));
    }
}

// Check if a path is a block device
static bool is_block_device(const char *path)
{
    struct stat st;
    if(stat(path, &st) != 0) {
        return false;
    }
    return S_ISBLK(st.st_mode);
}

// Confirm dangerous operation
static bool confirm_operation(const char *device, const char *operation)
{
    printf("\n");
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║                  ⚠️  WARNING - DATA LOSS  ⚠️                 ║\n");
    printf("╠════════════════════════════════════════════════════════════╣\n");
    printf("║  Operation: %-46s ║\n", operation);
    printf("║  Device:    %-46s ║\n", device);
    printf("║                                                            ║\n");
    printf("║  This operation will PERMANENTLY DESTROY all data on      ║\n");
    printf("║  this device! This action CANNOT be undone!               ║\n");
    printf("╚════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    
    printf("Type 'YES' in all capitals to confirm: ");
    fflush(stdout);
    
    char response[32] = {0};
    if(fgets(response, sizeof(response), stdin) == NULL) {
        return false;
    }
    
    // Remove newline
    response[strcspn(response, "\n")] = 0;
    
    return strcmp(response, "YES") == 0;
}

// Display device information
static void cmd_info(blockdev_ctx_t *bctx, mlfs_io_t *io)
{
    printf("Device Information\n");
    printf("==================\n");
    printf("Device Path:   %s\n", bctx->device_path);
    printf("Access Mode:   %s\n", bctx->read_only ? "Read-Only" : "Read-Write");
    printf("Sector Size:   %d bytes\n", SECTOR_SIZE);
    
    int64_t device_size = get_device_size(bctx->fd);
    if(device_size > 0) {
        char size_str[32];
        format_size(device_size, size_str, sizeof(size_str));
        printf("Device Size:   %s (%ld bytes)\n", size_str, device_size);
        printf("Total Sectors: %ld\n", device_size / SECTOR_SIZE);
    }
    
    printf("\n");
    
    // Try to read partition table
    mlpt_t pt;
    int rc = mlfs_read_mlpt(io, &pt);
    if(rc == 0) {
        printf("MLFS Partition Table Found\n");
        printf("===========================\n");
        printf("Magic:      0x%08X\n", pt.magic);
        printf("Version:    %u.%u.%u\n", pt.major, pt.minor, pt.patch);
        printf("Partitions: %u\n\n", pt.count);
        
        for(uint16_t i = 0; i < pt.count; i++) {
            mlpt_entry_t *entry = &pt.entries[i];
            printf("Partition %u:\n", i);
            printf("  Type:       %u (%s)\n", entry->type, entry->type == 1 ? "MLFS" : "Unknown");
            printf("  Start LBA:  %u\n", entry->start_lba);
            printf("  Blocks:     %u\n", entry->block_count);
            printf("  Block Size: %u bytes (log2: %u)\n", 
                   1u << entry->log2_block_size, entry->log2_block_size);
            printf("  Name:       %s\n", entry->name);
            printf("  Size:       ");
            uint64_t part_bytes = (uint64_t)entry->block_count * (1u << entry->log2_block_size);
            char part_size[32];
            format_size(part_bytes, part_size, sizeof(part_size));
            printf("%s\n", part_size);
            printf("\n");
        }
    } else {
        printf("No valid MLFS partition table found (error %d)\n", rc);
        printf("Device may be unformatted or contain a different filesystem.\n");
    }
}

// Format device with MLFS (create empty partition table)
static void cmd_format(blockdev_ctx_t *bctx, mlfs_io_t *io)
{
    if(bctx->read_only) {
        fprintf(stderr, "Error: Cannot format - device is opened read-only\n");
        fprintf(stderr, "Reopen without -r flag to enable write access\n");
        return;
    }
    
    if(!confirm_operation(bctx->device_path, "Create MLFS Partition Table")) {
        printf("Operation cancelled.\n");
        return;
    }
    
    printf("\nCreating empty MLFS partition table...\n");
    int rc = mlfs_make_empty_partition_table(io);
    if(rc != 0) {
        fprintf(stderr, "Error: Failed to create partition table (error %d)\n", rc);
        return;
    }
    
    printf("✓ MLFS partition table created successfully\n");
    printf("\nNext steps:\n");
    printf("  1. Create partition:     mlfs_blockdev %s mkpart 1 32 4096 system\n", 
           bctx->device_path);
    printf("  2. Format partition:     mlfs_blockdev %s mkfs 0\n", 
           bctx->device_path);
    printf("  3. View device info:     mlfs_blockdev %s -r info\n", 
           bctx->device_path);
}

// Create a new partition
static void cmd_mkpart(blockdev_ctx_t *bctx, mlfs_io_t *io, 
                       uint32_t start_lba, uint32_t size_mb, 
                       uint32_t block_size, const char *name)
{
    if(bctx->read_only) {
        fprintf(stderr, "Error: Cannot create partition - device is opened read-only\n");
        return;
    }
    
    // Validate parameters
    if(start_lba == 0) {
        fprintf(stderr, "Error: start_lba must be non-zero (sector 0 is reserved for partition table)\n");
        return;
    }
    
    if(size_mb < 1 || size_mb > 2048) {
        fprintf(stderr, "Error: Size must be between 1 and 2048 MB\n");
        return;
    }
    
    if(strlen(name) > 13) {
        fprintf(stderr, "Error: Partition name must be 13 characters or less\n");
        return;
    }
    
    // Find log2 of block size
    uint8_t log2_block_size = 0;
    uint32_t bs = block_size;
    while(bs > 1) {
        bs >>= 1;
        log2_block_size++;
    }
    
    if((1U << log2_block_size) != block_size) {
        fprintf(stderr, "Error: Block size must be a power of 2\n");
        return;
    }
    
    if(log2_block_size < 9 || log2_block_size > 16) {
        fprintf(stderr, "Error: Block size must be between 512 and 65536 bytes\n");
        return;
    }
    
    // Calculate block count from size in MB
    uint64_t size_bytes = (uint64_t)size_mb * 1024 * 1024;
    uint32_t block_count = size_bytes / block_size;
    
    if(block_count == 0) {
        fprintf(stderr, "Error: Size too small (results in 0 blocks)\n");
        return;
    }
    
    printf("Creating partition '%s': %u MB, %u blocks of %u bytes, starting at LBA %u\n",
           name, size_mb, block_count, block_size, start_lba);
    
    int rc = mlfs_add_partition(io, start_lba, block_count, log2_block_size, name);
    if(rc != 0) {
        switch(rc) {
            case -95: fprintf(stderr, "Error: Partition overlaps with existing partition\n"); break;
            case -96: fprintf(stderr, "Error: Block size not aligned to sector size\n"); break;
            case -97: fprintf(stderr, "Error: Too many partitions (maximum %d)\n", MLPT_MAX_PARTS); break;
            case -98: fprintf(stderr, "Error: Invalid partition name\n"); break;
            case -99: fprintf(stderr, "Error: Invalid block size\n"); break;
            default: fprintf(stderr, "Error: Failed to create partition (error %d)\n", rc); break;
        }
        return;
    }
    
    printf("✓ Partition created successfully\n");
    printf("Use '%s -r %s info' to view partition table\n", "mlfs_blockdev", bctx->device_path);
}

// Format a specific partition with MLFS filesystem
static void cmd_mkfs(blockdev_ctx_t *bctx, mlfs_io_t *io, uint16_t partition)
{
    if(bctx->read_only) {
        fprintf(stderr, "Error: Cannot format partition - device is opened read-only\n");
        return;
    }
    
    if(!confirm_operation(bctx->device_path, "Format partition with MLFS")) {
        printf("Operation cancelled.\n");
        return;
    }
    
    mlfs_t fs;
    printf("\nFormatting partition %u with MLFS...\n", partition);
    int rc = mlfs_mkfs(io, partition, &fs);
    if(rc != 0) {
        fprintf(stderr, "Error: Failed to format partition (error %d)\n", rc);
        return;
    }
    
    printf("✓ Partition %u formatted successfully\n", partition);
}

// Display usage information
static void print_usage(const char *program)
{
    printf("MLFS Block Device Tool\n");
    printf("======================\n\n");
    printf("Usage: %s [options] <device> <command> [args...]\n\n", program);
    
    printf("Options:\n");
    printf("  -r            Open device in read-only mode (safe for examination)\n");
    printf("  -h            Show this help message\n\n");
    
    printf("Commands:\n");
    printf("  info                                Show device and partition table information\n");
    printf("  format                              Create empty MLFS partition table (DESTROYS DATA!)\n");
    printf("  mkpart <start> <size_mb>            Create new partition\n");
    printf("         <block_size> <name>\n");
    printf("  mkfs <partition>                    Format partition with MLFS filesystem\n\n");
    
    printf("Arguments:\n");
    printf("  <device>      Block device path (e.g., /dev/sdb, /dev/sdc)\n");
    printf("  <start>       Starting LBA sector for partition\n");
    printf("  <size_mb>     Partition size in megabytes\n");
    printf("  <block_size>  Block size in bytes (512, 1024, 2048, 4096, etc.)\n");
    printf("  <name>        Partition name (up to 13 characters)\n");
    printf("  <partition>   Partition number to format (0-15)\n\n");
    
    printf("Examples:\n");
    printf("  # Examine device safely (read-only)\n");
    printf("  sudo %s -r /dev/sdb info\n\n", program);
    
    printf("  # Create partition table and setup device\n");
    printf("  sudo %s /dev/sdb format\n", program);
    printf("  sudo %s /dev/sdb mkpart 1 32 4096 system\n", program);
    printf("  sudo %s /dev/sdb mkfs 0\n\n", program);
    
    printf("Safety Notes:\n");
    printf("  ⚠️  Always use -r (read-only) when examining unknown devices\n");
    printf("  ⚠️  Write operations require root/sudo privileges\n");
    printf("  ⚠️  Double-check device path to avoid destroying wrong disk!\n");
    printf("  ⚠️  Use 'lsblk' or 'fdisk -l' to identify correct device\n");
    printf("  ⚠️  Backup important data before any write operations\n\n");
    
    printf("Integration:\n");
    printf("  This tool provides userspace access to MLFS on block devices.\n");
    printf("  For kernel integration, a kernel module would be needed to\n");
    printf("  register MLFS as a filesystem type with the Linux VFS layer.\n\n");
}

// Main program
int main(int argc, char **argv)
{
    bool read_only = false;
    int opt;
    
    // Parse options
    while((opt = getopt(argc, argv, "rh")) != -1) {
        switch(opt) {
            case 'r':
                read_only = true;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    // Check for device and command
    if(optind >= argc) {
        fprintf(stderr, "Error: Device path required\n\n");
        print_usage(argv[0]);
        return 1;
    }
    
    const char *device_path = argv[optind];
    optind++;
    
    if(optind >= argc) {
        fprintf(stderr, "Error: Command required\n\n");
        print_usage(argv[0]);
        return 1;
    }
    
    const char *command = argv[optind];
    optind++;
    
    // Verify device path looks reasonable
    if(!is_block_device(device_path)) {
        fprintf(stderr, "Warning: '%s' is not a block device\n", device_path);
        fprintf(stderr, "This tool is designed for block devices like /dev/sdb\n");
        fprintf(stderr, "For regular files, use the mlfs CLI tool instead.\n\n");
        
        // Allow continuing for testing with regular files
        if(read_only) {
            printf("Continuing in read-only mode...\n\n");
        } else {
            fprintf(stderr, "Refusing to write to non-block-device. Use -r for read-only.\n");
            return 1;
        }
    }
    
    // Check permissions
    if(!read_only && geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root\n");
        fprintf(stderr, "Write operations typically require root/sudo privileges\n");
        fprintf(stderr, "If you encounter permission errors, try: sudo %s ...\n\n", argv[0]);
    }
    
    // Open device
    int flags = read_only ? O_RDONLY : O_RDWR;
    flags |= O_SYNC; // Synchronous I/O for data integrity
    
    int fd = open(device_path, flags);
    if(fd < 0) {
        perror("Error opening device");
        if(errno == EACCES && geteuid() != 0) {
            fprintf(stderr, "Try running with sudo: sudo %s ...\n", argv[0]);
        }
        return 1;
    }
    
    // Setup context
    blockdev_ctx_t bctx = {
        .fd = fd,
        .read_only = read_only,
        .device_path = device_path
    };
    
    mlfs_io_t io = {
        .ctx = &bctx,
        .read = blockdev_read,
        .write = blockdev_write,
        .sector_size = SECTOR_SIZE
    };
    
    // Execute command
    int result = 0;
    
    if(strcmp(command, "info") == 0) {
        cmd_info(&bctx, &io);
    }
    else if(strcmp(command, "format") == 0) {
        cmd_format(&bctx, &io);
    }
    else if(strcmp(command, "mkpart") == 0) {
        if(argc - optind < 4) {
            fprintf(stderr, "Error: mkpart requires 4 arguments: <start_lba> <size_mb> <block_size> <name>\n");
            result = 1;
        } else {
            uint32_t start_lba = (uint32_t)atoi(argv[optind]);
            uint32_t size_mb = (uint32_t)atoi(argv[optind + 1]);
            uint32_t block_size = (uint32_t)atoi(argv[optind + 2]);
            const char *name = argv[optind + 3];
            cmd_mkpart(&bctx, &io, start_lba, size_mb, block_size, name);
        }
    }
    else if(strcmp(command, "mkfs") == 0) {
        if(argc - optind < 1) {
            fprintf(stderr, "Error: mkfs requires partition number\n");
            result = 1;
        } else {
            uint16_t partition = (uint16_t)atoi(argv[optind]);
            cmd_mkfs(&bctx, &io, partition);
        }
    }
    else {
        fprintf(stderr, "Error: Unknown command '%s'\n", command);
        result = 1;
    }
    
    // Cleanup
    close(fd);
    
    return result;
}

