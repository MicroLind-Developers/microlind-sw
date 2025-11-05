/****************************** cli_commands.c *****************************/
// MLFS CLI command implementations
#include "cli_commands.h"
#include <sys/stat.h>
#include <unistd.h>

// Command table
const command_t commands[] = {
    {"help", "help", "Show available commands", cmd_help},
    {"mount", "mount <image_file> [partition]", "Mount a disk image file", cmd_mount},
    {"unmount", "unmount", "Unmount current disk image", cmd_unmount},
    {"format", "format <image_file> [size_mb]", "Create a new disk image with empty partition table", cmd_format},
    {"ls", "ls [path]", "List directory contents", cmd_ls},
    {"mkdir", "mkdir <name>", "Create a directory", cmd_mkdir},
    {"rmdir", "rmdir <name>", "Remove an empty directory", cmd_rmdir},
    {"touch", "touch <name> [size_blocks]", "Create an empty file", cmd_touch},
    {"rm", "rm <name>", "Remove a file", cmd_rm},
    {"cat", "cat <name>", "Display file contents", cmd_cat},
    {"write", "write <name> <content>", "Write content to a file", cmd_write},
    {"info", "info", "Show image and partition information", cmd_info},
    {"cd", "cd <directory>", "Change current directory", cmd_cd},
    {"pwd", "pwd", "Print current working directory", cmd_pwd},
    {"partitions", "partitions", "List all partitions in the image", cmd_partitions},
    {"partition", "partition <number>", "Switch to a different partition", cmd_partition},
    {"mkpart", "mkpart <start_lba> <size_mb> <block_size> <name>", "Create a new partition", cmd_mkpart},
    {"mkfs", "mkfs <partition>", "Format a partition with MLFS filesystem", cmd_mkfs},
    {"open", "open <image_file>", "Open an existing image file for partition operations", cmd_open},
    {"close", "close", "Close the current image file", cmd_close},
    {"quit", "quit", "Exit the CLI", cmd_quit},
    {"exit", "exit", "Exit the CLI", cmd_quit},
};

const int num_commands = sizeof(commands) / sizeof(commands[0]);

// Helper function to check if filesystem is mounted
static int check_mounted(cli_state_t *state)
{
    if(!state->mounted) {
        printf("Error: No filesystem mounted. Use 'mount <image_file>' first.\n");
        return 0;
    }
    return 1;
}

// Help command
int cmd_help(cli_state_t *state, int argc, char **argv)
{
    (void)state;
    (void)argc;
    (void)argv; // Suppress unused warnings

    printf("MLFS CLI - Available Commands:\n");
    printf("===============================\n\n");

    for(int i = 0; i < num_commands; i++) {
        printf("  %-20s - %s\n", commands[i].usage, commands[i].description);
    }
    printf("\nExample workflow:\n");
    printf("  format disk.img 64 4096    # Create 64MB disk with 4KB blocks\n");
    printf("  mount disk.img             # Mount the disk image\n");
    printf("  mkdir documents            # Create a directory\n");
    printf("  touch readme.txt           # Create a file\n");
    printf("  write readme.txt \"Hello\"   # Write content to file\n");
    printf("  ls                         # List contents\n");
    printf("  cat readme.txt             # Show file content\n");

    return 0;
}

// Mount command
int cmd_mount(cli_state_t *state, int argc, char **argv)
{
    if(argc < 2 || argc > 3) {
        printf("Usage: mount <image_file> [partition]\n");
        printf("  partition: Partition number to mount (default: 0)\n");
        return -1;
    }

    if(state->mounted) {
        printf("Error: Already mounted '%s' partition %u. Use 'unmount' first.\n", 
               state->image_path, state->current_partition);
        return -1;
    }

    // Parse partition number if provided
    uint16_t partition_number = 0;
    if(argc == 3) {
        int part_num = atoi(argv[2]);
        if(part_num < 0 || part_num > 65535) {
            printf("Error: Invalid partition number '%s' (must be 0-65535)\n", argv[2]);
            return -1;
        }
        partition_number = (uint16_t)part_num;
    }

    // Open the image file
    state->image_file = fopen(argv[1], "r+b");
    if(!state->image_file) {
        perror("Failed to open image file");
        return -1;
    }

    // Setup I/O structure
    state->io.ctx = state->image_file;
    state->io.read = file_io_read;
    state->io.write = file_io_write;
    state->io.sector_size = 512;

    // Try to mount the filesystem
    int result = mlfs_mount(&state->io, partition_number, &state->fs);
    if(result != 0) {
        printf("Error: Failed to mount partition %u (error %d)\n", partition_number, result);
        switch(result) {
            case -3: printf("Partition %u does not exist.\n", partition_number); break;
            case -4: printf("Partition %u is not an MLFS partition.\n", partition_number); break;
            default: printf("The partition might not contain a valid MLFS filesystem or may be corrupted.\n"); break;
        }
        printf("Image file remains open. Use 'partitions' to list partitions, 'mkfs %u' to format, or 'mkpart' to create partitions.\n", partition_number);
        // Keep the image file open for partition operations - don't close it!
        return -1;
    }

    // Success
    strncpy(state->image_path, argv[1], sizeof(state->image_path) - 1);
    state->image_path[sizeof(state->image_path) - 1] = '\0';
    state->current_partition = partition_number;
    state->mounted = 1;
    
    // Initialize current working directory to root
    init_cli_state_cwd(state);

    printf("Successfully mounted '%s' partition %u\n", argv[1], partition_number);
    printf("Block size: %u bytes, Total blocks: %u\n", 1U << state->fs.sb.log2_block_size, state->fs.sb.total_blocks);

    return 0;
}

// Unmount command
int cmd_unmount(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv; // Suppress unused warnings

    if(!state->mounted) {
        if(state->image_file) {
            printf("Image file '%s' is open but no filesystem is mounted.\n", state->image_path);
        } else {
            printf("No filesystem mounted and no image file open.\n");
        }
        return 0;
    }

    state->mounted = 0;
    printf("Unmounted filesystem from '%s'\n", state->image_path);
    printf("Image file remains open for partition operations.\n");
    printf("Use 'mount %s <partition>' to mount a different partition.\n", state->image_path);

    return 0;
}

// Format command - creates empty disk image with empty partition table
int cmd_format(cli_state_t *state, int argc, char **argv)
{
    if(argc < 2 || argc > 3) {
        printf("Usage: format <image_file> [size_mb]\n");
        printf("  size_mb: Size in megabytes (default: 64)\n");
        printf("Note: This creates an empty partition table. Use 'mkpart' to add partitions.\n");
        return -1;
    }

    if(state->mounted) {
        printf("Error: Please unmount current filesystem first.\n");
        return -1;
    }

    const char *filename = argv[1];
    uint32_t size_mb = (argc >= 3) ? atoi(argv[2]) : 64;

    // Validate parameters
    if(size_mb < 1 || size_mb > 2048) {
        printf("Error: Size must be between 1 and 2048 MB\n");
        return -1;
    }

    printf("Creating %s: %u MB with empty partition table...\n", filename, size_mb);

    // Create the image file
    FILE *file = fopen(filename, "w+b");
    if(!file) {
        perror("Failed to create image file");
        return -1;
    }

    // Calculate size and create sparse file
    uint64_t total_size = (uint64_t)size_mb * 1024 * 1024;
    fseek(file, total_size - 1, SEEK_SET);
    fputc(0, file);
    rewind(file);

    // Setup I/O for formatting
    mlfs_io_t io = {.ctx = file, .read = file_io_read, .write = file_io_write, .sector_size = 512};

    // Create empty partition table
    int result = mlfs_make_empty_partition_table(&io);
    if(result != 0) {
        printf("Error: Failed to create partition table (error %d)\n", result);
        fclose(file);
        unlink(filename);
        return -1;
    }

    // Keep the file open and setup I/O for partition operations
    strncpy(state->image_path, filename, sizeof(state->image_path) - 1);
    state->image_path[sizeof(state->image_path) - 1] = '\0';
    state->image_file = file;
    state->io.ctx = file;
    state->io.read = file_io_read;
    state->io.write = file_io_write;
    state->io.sector_size = 512;
    state->mounted = 0; // File is open but no filesystem mounted

    printf("Successfully created '%s' with empty partition table\n", filename);
    printf("Image file is now open and ready for partition creation.\n");
    printf("Next steps:\n");
    printf("  1. Use 'mkpart <start_lba> <size_mb> <block_size> <name>' to create partitions\n");
    printf("  2. Use 'mkfs <partition>' to format partitions with MLFS filesystem\n");
    printf("  3. Use 'mount %s <partition>' to mount and use a partition\n", filename);

    return 0;
}

// List directory command
int cmd_ls(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    const char *path = (argc >= 2) ? argv[1] : state->current_dir;

    char resolved_path[256];
    if(!resolve_path(state, path, resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", path);
        return -1;
    }

    mlfs_dentry_t entries[64];
    uint32_t count;

    int result = mlfs_read_directory(&state->fs, resolved_path, entries, 64, &count);
    if(result != 0) {
        printf("Error: Failed to read directory '%s' (error %d)\n", path, result);
        return -1;
    }

    printf("Contents of '%s' (%u entries):\n", path, count);
    printf("%-20s %10s %10s %s\n", "Name", "Type", "Size", "Modified");
    printf("%-20s %10s %10s %s\n", "----", "----", "----", "--------");

    for(uint32_t i = 0; i < count; i++) {
        const char *type = (entries[i].flags & 1) ? "DIR" : "FILE";
        printf("%-20s %10s %10u %u\n", entries[i].name, type, entries[i].size_bytes, entries[i].mtime);
    }

    if(count == 0) {
        printf("(empty)\n");
    }

    return 0;
}

// Make directory command
int cmd_mkdir(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc != 2) {
        printf("Usage: mkdir <name>\n");
        return -1;
    }

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    int result = mlfs_create_directory(&state->fs, resolved_path, 1);
    if(result != 0) {
        printf("Error: Failed to create directory '%s' (error %d)\n", argv[1], result);
        return -1;
    }

    printf("Created directory '%s'\n", argv[1]);
    return 0;
}

// Remove directory command
int cmd_rmdir(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc != 2) {
        printf("Usage: rmdir <name>\n");
        return -1;
    }

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    int result = mlfs_delete_directory(&state->fs, resolved_path);
    if(result != 0) {
        if(result == -3) {
            printf("Error: Directory '%s' is not empty\n", argv[1]);
        } else {
            printf("Error: Failed to remove directory '%s' (error %d)\n", argv[1], result);
        }
        return -1;
    }

    printf("Removed directory '%s'\n", argv[1]);
    return 0;
}

// Touch (create file) command
int cmd_touch(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc < 2 || argc > 3) {
        printf("Usage: touch <name> [size_blocks]\n");
        return -1;
    }

    uint32_t blocks = (argc >= 3) ? atoi(argv[2]) : 1;
    if(blocks < 1)
        blocks = 1;

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    int result = mlfs_create_empty_file(&state->fs, resolved_path, blocks);
    if(result != 0) {
        printf("Error: Failed to create file '%s' (error %d)\n", argv[1], result);
        return -1;
    }

    printf("Created file '%s' (%u blocks)\n", argv[1], blocks);
    return 0;
}

// Remove file command
int cmd_rm(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc != 2) {
        printf("Usage: rm <name>\n");
        return -1;
    }

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    int result = mlfs_delete_file(&state->fs, resolved_path);
    if(result != 0) {
        printf("Error: Failed to remove file '%s' (error %d)\n", argv[1], result);
        return -1;
    }

    printf("Removed file '%s'\n", argv[1]);
    return 0;
}

// Cat (show file) command
int cmd_cat(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc != 2) {
        printf("Usage: cat <name>\n");
        return -1;
    }

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    // Read the entire file
    char buffer[4096];
    ssize_t bytes_read = mlfs_pread_file(&state->fs, resolved_path, buffer, sizeof(buffer) - 1, 0);

    if(bytes_read < 0) {
        printf("Error: Failed to read file '%s'\n", argv[1]);
        return -1;
    }

    buffer[bytes_read] = '\0';
    printf("Contents of '%s' (%zd bytes):\n", argv[1], bytes_read);
    printf("================================\n");
    printf("%s", buffer);
    if(bytes_read > 0 && buffer[bytes_read - 1] != '\n') {
        printf("\n");
    }
    printf("================================\n");

    return 0;
}

// Write to file command
int cmd_write(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    if(argc != 3) {
        printf("Usage: write <name> <content>\n");
        return -1;
    }

    char resolved_path[256];
    if(!resolve_path(state, argv[1], resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", argv[1]);
        return -1;
    }

    const char *content = argv[2];
    ssize_t bytes_written = mlfs_pwrite_file(&state->fs, resolved_path, content, strlen(content), 0);

    if(bytes_written < 0) {
        printf("Error: Failed to write to file '%s'\n", argv[1]);
        return -1;
    }

    printf("Wrote %zd bytes to '%s'\n", bytes_written, argv[1]);
    return 0;
}

// Info command - enhanced to show partition layout and free space
int cmd_info(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv; // Suppress unused warnings

    if(!state->image_file) {
        printf("No image file open. Use 'format' or 'open' to work with an image.\n");
        return -1;
    }

    printf("MLFS Image Information\n");
    printf("======================\n\n");

    // Get file size
    long current_pos = ftell(state->image_file);
    fseek(state->image_file, 0, SEEK_END);
    long file_size = ftell(state->image_file);
    fseek(state->image_file, current_pos, SEEK_SET);

    printf("Image File:\n");
    printf("  File: %s\n", state->image_path);
    printf("  Size: %ld bytes", file_size);
    if(file_size >= 1024 * 1024) {
        printf(" (%.1f MB)", file_size / (1024.0 * 1024.0));
    }
    printf("\n");
    
    uint64_t total_sectors = (uint64_t)file_size / 512;
    printf("  Total sectors: %lu (512 bytes each)\n", total_sectors);
    printf("\n");

    // Read partition table
    mlpt_t pt;
    int result = mlfs_read_mlpt(&state->io, &pt);
    if(result != 0) {
        printf("Error: Failed to read partition table (error %d)\n", result);
        return -1;
    }

    printf("Partition Table:\n");
    printf("  Magic: 0x%08X\n", pt.magic);
    printf("  Version: %u.%u.%u\n", pt.major, pt.minor, pt.patch);
    printf("  Partitions: %u\n\n", pt.count);

    if(pt.count == 0) {
        printf("No partitions defined.\n");
        printf("Available space: LBA 1 to %lu (%lu sectors)\n", total_sectors - 1, total_sectors - 1);
        printf("Suggestion: mkpart 1 <size_mb> <block_size> <name>\n\n");
    } else {
        // Show all partitions with detailed layout
        printf("Partition Layout:\n");
        printf("Num | Start LBA | End LBA   | Sectors | Size     | Block Size | Name     | Status\n");
        printf("----+-----------+-----------+---------+----------+------------+----------+--------\n");

        uint32_t next_available_lba = 1; // Start after partition table

        for(uint16_t i = 0; i < pt.count; i++) {
            mlpt_entry_t *e = &pt.entries[i];
            uint32_t sectors_per_block = (1U << e->log2_block_size) / 512;
            uint32_t total_sectors_used = e->block_count * sectors_per_block;
            uint32_t end_lba = e->start_lba + total_sectors_used - 1;

            uint64_t partition_size = (uint64_t)e->block_count * (1U << e->log2_block_size);
            
            printf("%3u | %9u | %9u | %7u | ", i, e->start_lba, end_lba, total_sectors_used);
            
            if(partition_size >= 1024 * 1024) {
                printf("%7.1f MB", partition_size / (1024.0 * 1024.0));
            } else {
                printf("%7.1f KB", partition_size / 1024.0);
            }
            
            printf(" | %10u | %-8.8s | ", 1U << e->log2_block_size, e->name);
            
            // Check if this partition is formatted by trying to mount it (without actually mounting)
            mlfs_t temp_fs;
            int mount_result = mlfs_mount(&state->io, i, &temp_fs);
            if(mount_result == 0) {
                if(state->mounted && i == state->current_partition) {
                    printf("MOUNTED");
                } else {
                    printf("Ready");
                }
            } else {
                switch(mount_result) {
                    case -3: printf("Missing"); break;
                    case -4: printf("Wrong type"); break;
                    default: printf("Unformatted"); break;
                }
            }
            printf("\n");

            // Track the next available LBA
            if(end_lba + 1 > next_available_lba) {
                next_available_lba = end_lba + 1;
            }
        }
        printf("\n");

        // Show free space analysis
        printf("Free Space Analysis:\n");
        if(next_available_lba < total_sectors) {
            uint64_t free_sectors = total_sectors - next_available_lba;
            uint64_t free_bytes = free_sectors * 512;
            
            printf("  Next available LBA: %u\n", next_available_lba);
            printf("  Free sectors: %lu", free_sectors);
            if(free_bytes >= 1024 * 1024) {
                printf(" (%.1f MB)", free_bytes / (1024.0 * 1024.0));
            } else {
                printf(" (%.1f KB)", free_bytes / 1024.0);
            }
            printf("\n");
            printf("  Suggestion: mkpart %u <size_mb> <block_size> <name>\n", next_available_lba);
        } else {
            printf("  No free space remaining.\n");
        }
        printf("\n");
    }

    // If a filesystem is mounted, show filesystem details
    if(state->mounted) {
        printf("Mounted Filesystem (Partition %u):\n", state->current_partition);
        printf("  Block size: %u bytes (log2: %u)\n", 1U << state->fs.sb.log2_block_size, state->fs.sb.log2_block_size);
        printf("  Total blocks: %u\n", state->fs.sb.total_blocks);
        printf("  Bitmap start: block %u\n", state->fs.sb.bitmap_start);
        printf("  Bitmap blocks: %u\n", state->fs.sb.bitmap_blocks);
        printf("  Root directory: block %u (%u blocks)\n", state->fs.sb.root_dir_block, state->fs.sb.root_dir_blocks);
        printf("  Current directory: %s\n", state->current_dir);
        printf("\n");
    }

    return 0;
}

// Partitions command - list all partitions in image
int cmd_partitions(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv;

    if(!state->image_file) {
        printf("Error: No image file open. Use 'mount <image_file>' first.\n");
        return -1;
    }

    // Setup I/O structure
    mlfs_io_t io = {
        .ctx = state->image_file,
        .read = file_io_read,
        .write = file_io_write,
        .sector_size = 512
    };

    // Read partition table
    mlpt_t pt;
    int result = mlfs_read_mlpt(&io, &pt);
    if(result != 0) {
        printf("Error: Failed to read partition table (error %d)\n", result);
        return -1;
    }

    printf("Partition Table Information:\n");
    printf("============================\n");
    printf("Magic:     0x%08X\n", pt.magic);
    printf("Version:   %u.%u.%u\n", pt.major, pt.minor, pt.patch);
    printf("Count:     %u partitions\n\n", pt.count);

    if(pt.count == 0) {
        printf("No partitions found.\n");
        return 0;
    }

    for(uint16_t i = 0; i < pt.count; i++) {
        printf("Partition %u:", i);
        if(state->mounted && i == state->current_partition) {
            printf(" [MOUNTED]");
        }
        printf("\n");
        printf("  Type:        %u", pt.entries[i].type);
        if(pt.entries[i].type == 1) {
            printf(" (MLFS)");
        }
        printf("\n");
        printf("  Start LBA:   %u\n", pt.entries[i].start_lba);
        printf("  Block Count: %u\n", pt.entries[i].block_count);
        printf("  Block Size:  %u bytes (log2: %u)\n", 
               1U << pt.entries[i].log2_block_size, pt.entries[i].log2_block_size);
        printf("  Name:        %.14s\n", pt.entries[i].name);
        
        // Calculate total size
        uint64_t partition_size = (uint64_t)pt.entries[i].block_count * (1U << pt.entries[i].log2_block_size);
        if(partition_size < 1024 * 1024) {
            printf("  Size:        %.1f KB\n", partition_size / 1024.0);
        } else if(partition_size < 1024 * 1024 * 1024) {
            printf("  Size:        %.1f MB\n", partition_size / (1024.0 * 1024.0));
        } else {
            printf("  Size:        %.1f GB\n", partition_size / (1024.0 * 1024.0 * 1024.0));
        }
        
        if(i < pt.count - 1) printf("\n");
    }

    return 0;
}

// Partition command - switch to a different partition
int cmd_partition(cli_state_t *state, int argc, char **argv)
{
    if(argc != 2) {
        printf("Usage: partition <number>\n");
        printf("Switch to mount a different partition in the current image.\n");
        return -1;
    }

    if(!state->image_file) {
        printf("Error: No image file open. Use 'mount <image_file>' first.\n");
        return -1;
    }

    // Parse partition number
    int part_num = atoi(argv[1]);
    if(part_num < 0 || part_num > 65535) {
        printf("Error: Invalid partition number '%s' (must be 0-65535)\n", argv[1]);
        return -1;
    }
    uint16_t partition_number = (uint16_t)part_num;

    // Check if already mounted
    if(state->mounted && partition_number == state->current_partition) {
        printf("Partition %u is already mounted.\n", partition_number);
        return 0;
    }

    // Try to mount the new partition
    int result = mlfs_mount(&state->io, partition_number, &state->fs);
    if(result != 0) {
        printf("Error: Failed to mount partition %u (error %d)\n", partition_number, result);
        printf("The partition might not contain a valid MLFS filesystem or may be corrupted.\n");
        printf("Use 'partitions' to list available partitions.\n");
        return -1;
    }

    // Success
    state->current_partition = partition_number;
    state->mounted = 1;
    
    // Reset current working directory to root
    init_cli_state_cwd(state);

    printf("Successfully switched to partition %u\n", partition_number);
    printf("Block size: %u bytes, Total blocks: %u\n", 1U << state->fs.sb.log2_block_size, state->fs.sb.total_blocks);

    return 0;
}

// Make partition command - add a new partition to the image
int cmd_mkpart(cli_state_t *state, int argc, char **argv)
{
    if(argc != 5) {
        printf("Usage: mkpart <start_lba> <size_mb> <block_size> <name>\n");
        printf("  start_lba:   Starting LBA sector for the partition\n");
        printf("  size_mb:     Size of partition in megabytes\n");
        printf("  block_size:  Block size in bytes (512, 1024, 2048, 4096, etc.)\n");
        printf("  name:        Partition name (up to 13 characters)\n");
        printf("\nExample: mkpart 1 32 4096 main\n");
        return -1;
    }

    if(!state->image_file) {
        printf("Error: No image file open. Use 'format <image_file>' to create an image first.\n");
        return -1;
    }

    // Parse parameters
    uint32_t start_lba = atoi(argv[1]);
    uint32_t size_mb = atoi(argv[2]);
    uint32_t block_size = atoi(argv[3]);
    const char *name = argv[4];

    // Validate parameters
    if(start_lba == 0) {
        printf("Error: start_lba must be non-zero (sector 0 is reserved for partition table)\n");
        return -1;
    }

    if(size_mb < 1 || size_mb > 2048) {
        printf("Error: Size must be between 1 and 2048 MB\n");
        return -1;
    }

    if(strlen(name) > 13) {
        printf("Error: Partition name must be 13 characters or less\n");
        return -1;
    }

    // Find log2 of block size
    uint8_t log2_block_size = 0;
    uint32_t bs = block_size;
    while(bs > 1) {
        bs >>= 1;
        log2_block_size++;
    }

    if((1U << log2_block_size) != block_size) {
        printf("Error: Block size must be a power of 2\n");
        return -1;
    }

    if(log2_block_size < 9 || log2_block_size > 16) {
        printf("Error: Block size must be between 512 and 65536 bytes\n");
        return -1;
    }

    // Calculate block count from size in MB
    uint64_t size_bytes = (uint64_t)size_mb * 1024 * 1024;
    uint32_t block_count = size_bytes / block_size;

    if(block_count == 0) {
        printf("Error: Partition too small for given block size\n");
        return -1;
    }

    printf("Creating partition '%s': %u MB, %u blocks of %u bytes, starting at LBA %u\n",
           name, size_mb, block_count, block_size, start_lba);

    // Add the partition
    int result = mlfs_add_partition(&state->io, start_lba, block_count, log2_block_size, name);
    if(result != 0) {
        switch(result) {
            case -95: printf("Error: Partition overlaps with existing partition\n"); break;
            case -96: printf("Error: Block size not aligned to sector size\n"); break;
            case -97: printf("Error: Too many partitions (maximum %d)\n", MLPT_MAX_PARTS); break;
            case -98: printf("Error: Invalid partition name\n"); break;
            case -99: printf("Error: Invalid block size\n"); break;
            default: printf("Error: Failed to create partition (error %d)\n", result); break;
        }
        return -1;
    }

    printf("Successfully created partition '%s'\n", name);
    printf("Use 'partitions' to see all partitions\n");
    printf("Use 'mkfs <partition_number>' to format the partition with MLFS filesystem\n");

    return 0;
}

// Make filesystem command - format a partition with MLFS
int cmd_mkfs(cli_state_t *state, int argc, char **argv)
{
    if(argc != 2) {
        printf("Usage: mkfs <partition>\n");
        printf("  partition: Partition number to format with MLFS filesystem\n");
        printf("\nExample: mkfs 0\n");
        return -1;
    }

    if(!state->image_file) {
        printf("Error: No image file open. Use 'format <image_file>' to create an image first.\n");
        return -1;
    }

    // Parse partition number
    int part_num = atoi(argv[1]);
    if(part_num < 0 || part_num > 65535) {
        printf("Error: Invalid partition number '%s' (must be 0-65535)\n", argv[1]);
        return -1;
    }
    uint16_t partition_number = (uint16_t)part_num;

    printf("Formatting partition %u with MLFS filesystem...\n", partition_number);

    // Format the partition
    mlfs_t fs;
    int result = mlfs_mkfs(&state->io, partition_number, &fs);
    if(result != 0) {
        switch(result) {
            case -3: printf("Error: Partition %u does not exist\n", partition_number); break;
            case -4: printf("Error: Partition %u is not an MLFS partition\n", partition_number); break;
            case -5: printf("Error: Block size not compatible with sector size\n"); break;
            case -6: printf("Error: Out of memory\n"); break;
            default: printf("Error: Failed to format partition (error %d)\n", result); break;
        }
        return -1;
    }

    printf("Successfully formatted partition %u with MLFS filesystem\n", partition_number);
    printf("Block size: %u bytes, Total blocks: %u\n", 1U << fs.sb.log2_block_size, fs.sb.total_blocks);
    printf("Use 'mount <image_file> %u' to mount and use this partition\n", partition_number);

    return 0;
}

// Open command - open existing image file for partition operations
int cmd_open(cli_state_t *state, int argc, char **argv)
{
    if(argc != 2) {
        printf("Usage: open <image_file>\n");
        printf("Open an existing image file for partition operations (without mounting a filesystem).\n");
        return -1;
    }

    if(state->image_file) {
        printf("Error: Image file '%s' is already open. Use 'close' first.\n", state->image_path);
        return -1;
    }

    const char *filename = argv[1];

    // Open the image file
    FILE *file = fopen(filename, "r+b");
    if(!file) {
        perror("Failed to open image file");
        return -1;
    }

    // Setup I/O structure  
    state->image_file = file;
    state->io.ctx = file;
    state->io.read = file_io_read;
    state->io.write = file_io_write;
    state->io.sector_size = 512;
    state->mounted = 0; // File is open but no filesystem mounted

    // Store the image path
    strncpy(state->image_path, filename, sizeof(state->image_path) - 1);
    state->image_path[sizeof(state->image_path) - 1] = '\0';

    printf("Opened image file '%s' for partition operations\n", filename);
    printf("Use 'partitions' to list existing partitions\n");
    printf("Use 'mkpart' to create new partitions\n");
    printf("Use 'mkfs <partition>' to format partitions\n");
    printf("Use 'mount %s <partition>' to mount and use a partition\n", filename);

    return 0;
}

// Close command - close image file
int cmd_close(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv; // Suppress unused warnings

    if(!state->image_file) {
        printf("No image file is open.\n");
        return 0;
    }

    // Unmount filesystem if mounted
    if(state->mounted) {
        state->mounted = 0;
        printf("Unmounted filesystem from '%s'\n", state->image_path);
    }

    // Close image file
    fclose(state->image_file);
    state->image_file = NULL;
    printf("Closed image file '%s'\n", state->image_path);
    state->image_path[0] = '\0';

    return 0;
}

// Quit command
int cmd_quit(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv; // Suppress unused warnings

    if(state->image_file) {
        cmd_close(state, 0, NULL);
    }

    printf("Goodbye!\n");
    return 1; // Signal to exit main loop
}

// Initialize CLI state current working directory
void init_cli_state_cwd(cli_state_t *state)
{
    strcpy(state->current_dir, "/");
}

// Resolve a path relative to current working directory
char* resolve_path(cli_state_t *state, const char *path, char *resolved, size_t resolved_size)
{
    if(!path || !resolved || resolved_size < 2) {
        return NULL;
    }

    // If path is absolute, use it as-is (but just the filename for now)
    if(path[0] == '/') {
        // For now, only support root directory files
        if(strcmp(path, "/") == 0) {
            strncpy(resolved, "/", resolved_size - 1);
            resolved[resolved_size - 1] = '\0';
        } else {
            // Extract just the filename (no subdirectories yet)
            const char *filename = strrchr(path, '/');
            if(filename && strlen(filename) > 1) {
                strncpy(resolved, filename + 1, resolved_size - 1);
                resolved[resolved_size - 1] = '\0';
            } else {
                return NULL;
            }
        }
        return resolved;
    }

    // For relative paths, check current directory
    if(strcmp(state->current_dir, "/") == 0) {
        // We're in root, so relative path is just the filename
        strncpy(resolved, path, resolved_size - 1);
        resolved[resolved_size - 1] = '\0';
    } else {
        // We're in a subdirectory - construct relative path with length check
        size_t current_len = strlen(state->current_dir);
        size_t path_len = strlen(path);
        
        if(current_len + 1 + path_len >= resolved_size) {
            // Path would be too long
            return NULL;
        }
        
        // Manually construct path to avoid snprintf warnings
        strcpy(resolved, state->current_dir);
        strcat(resolved, "/");
        strcat(resolved, path);
    }

    return resolved;
}

// Change directory command
int cmd_cd(cli_state_t *state, int argc, char **argv)
{
    if(!check_mounted(state))
        return -1;

    const char *target_dir = "/";
    if(argc >= 2) {
        target_dir = argv[1];
    }

    // Handle special cases
    if(strcmp(target_dir, ".") == 0) {
        // Stay in current directory
        return 0;
    }

    if(strcmp(target_dir, "..") == 0) {
        // Go to parent directory
        if(strcmp(state->current_dir, "/") == 0) {
            // Already in root, can't go higher
            return 0;
        }
        
        // Find the last '/' and truncate there
        char *last_slash = strrchr(state->current_dir, '/');
        if(last_slash && last_slash != state->current_dir) {
            *last_slash = '\0';
        } else {
            // We're one level down from root
            strcpy(state->current_dir, "/");
        }
        return 0;
    }

    if(strcmp(target_dir, "/") == 0) {
        // Go to root
        strcpy(state->current_dir, "/");
        return 0;
    }

    // For other directories, first check if it exists
    char resolved_path[256];
    if(!resolve_path(state, target_dir, resolved_path, sizeof(resolved_path))) {
        printf("Error: Invalid path '%s'\n", target_dir);
        return -1;
    }

    // Try to read the directory to verify it exists
    mlfs_dentry_t entries[1];
    uint32_t count;
    int result = mlfs_read_directory(&state->fs, resolved_path, entries, 1, &count);
    
    if(result != 0) {
        if(result == -2) {
            printf("Error: '%s' is not a directory\n", target_dir);
        } else {
            printf("Error: Directory '%s' not found\n", target_dir);
        }
        return -1;
    }

    // Directory exists, update current directory
    if(target_dir[0] == '/') {
        // Absolute path
        strncpy(state->current_dir, target_dir, sizeof(state->current_dir) - 1);
        state->current_dir[sizeof(state->current_dir) - 1] = '\0';
    } else {
        // Relative path - construct full path from current directory
        if(strcmp(state->current_dir, "/") == 0) {
            snprintf(state->current_dir, sizeof(state->current_dir), "/%s", target_dir);
        } else {
            // Append to current path
            size_t current_len = strlen(state->current_dir);
            if(current_len + 1 + strlen(target_dir) < sizeof(state->current_dir)) {
                strcat(state->current_dir, "/");
                strcat(state->current_dir, target_dir);
            } else {
                printf("Error: Path too long\n");
                return -1;
            }
        }
    }

    return 0;
}

// Print working directory command
int cmd_pwd(cli_state_t *state, int argc, char **argv)
{
    (void)argc;
    (void)argv; // Suppress unused warnings

    if(!check_mounted(state))
        return -1;

    printf("%s\n", state->current_dir);
    return 0;
}
