/****************************** mlfs_info.c *****************************/
// MLFS Filesystem Information and Analysis Tool
// Parses MLFS image files and displays detailed filesystem information

#include "mlfs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>

// File I/O functions for reading disk images
int info_file_read(void *ctx, uint64_t lba, uint32_t count, void *buf)
{
    FILE *file = (FILE *)ctx;
    if(!file) return -1;
    
    uint64_t offset = lba * 512;
    if(fseek(file, offset, SEEK_SET) != 0) return -1;
    
    size_t bytes_to_read = count * 512;
    size_t bytes_read = fread(buf, 1, bytes_to_read, file);
    if(bytes_read != bytes_to_read) {
        if(feof(file)) {
            memset((uint8_t *)buf + bytes_read, 0, bytes_to_read - bytes_read);
        } else {
            return -1;
        }
    }
    return 0;
}

// Dummy write function (read-only tool)
int info_file_write(void *ctx, uint64_t lba, uint32_t count, const void *buf)
{
    (void)ctx; (void)lba; (void)count; (void)buf;
    return -1; // Read-only
}

// Format timestamp for display
void format_timestamp(uint32_t timestamp, char *buffer, size_t size)
{
    if(timestamp == 0) {
        strncpy(buffer, "Never", size - 1);
        buffer[size - 1] = '\0';
        return;
    }
    
    time_t time = (time_t)timestamp;
    struct tm *tm_info = localtime(&time);
    if(tm_info) {
        strftime(buffer, size, "%Y-%m-%d %H:%M:%S", tm_info);
    } else {
        snprintf(buffer, size, "%u", timestamp);
    }
}

// Format file size for display
void format_size(uint64_t size, char *buffer, size_t buf_size)
{
    if(size < 1024) {
        snprintf(buffer, buf_size, "%lu B", size);
    } else if(size < 1024 * 1024) {
        snprintf(buffer, buf_size, "%.1f KB", size / 1024.0);
    } else if(size < 1024 * 1024 * 1024) {
        snprintf(buffer, buf_size, "%.1f MB", size / (1024.0 * 1024.0));
    } else {
        snprintf(buffer, buf_size, "%.1f GB", size / (1024.0 * 1024.0 * 1024.0));
    }
}

// Display directory tree recursively
void display_directory_tree(mlfs_t *fs, const char *path, int depth, const char *prefix, int is_last)
{
    (void)is_last; // Suppress unused parameter warning
    mlfs_dentry_t entries[256];
    uint32_t count;
    
    int result = mlfs_read_directory(fs, path, entries, 256, &count);
    if(result != 0) {
        printf("%s└── [ERROR: Cannot read directory '%s' (error %d)]\n", prefix, path, result);
        return;
    }
    
    for(uint32_t i = 0; i < count; i++) {
        const char *entry_prefix = (i == count - 1) ? "└── " : "├── ";
        char time_str[32];
        char size_str[16];
        
        format_timestamp(entries[i].mtime, time_str, sizeof(time_str));
        format_size(entries[i].size_bytes, size_str, sizeof(size_str));
        
        printf("%s%s", prefix, entry_prefix);
        
        if(entries[i].flags & 1) {
            // Directory
            printf("📁 %s/ (%s, %s)\n", entries[i].name, size_str, time_str);
            
            // Recurse into subdirectory if not too deep
            if(depth < 10) {
                char new_path[512];
                char new_prefix[512];
                
                // Build new path with length check
                if(strcmp(path, "/") == 0) {
                    size_t name_len = strlen(entries[i].name);
                    if(1 + name_len >= sizeof(new_path)) {
                        printf("%s    [... path too long, truncated]\n", prefix);
                        continue;
                    }
                    strcpy(new_path, "/");
                    strcat(new_path, entries[i].name);
                } else {
                    size_t path_len = strlen(path);
                    size_t name_len = strlen(entries[i].name);
                    if(path_len + 1 + name_len >= sizeof(new_path)) {
                        printf("%s    [... path too long, truncated]\n", prefix);
                        continue;
                    }
                    strcpy(new_path, path);
                    strcat(new_path, "/");
                    strcat(new_path, entries[i].name);
                }
                
                // Build new prefix with length check
                const char *next_prefix = (i == count - 1) ? "    " : "│   ";
                size_t prefix_len = strlen(prefix);
                size_t next_len = strlen(next_prefix);
                if(prefix_len + next_len >= sizeof(new_prefix)) {
                    printf("%s    [... prefix too long, truncated]\n", prefix);
                    continue;
                }
                strcpy(new_prefix, prefix);
                strcat(new_prefix, next_prefix);
                
                display_directory_tree(fs, new_path, depth + 1, new_prefix, i == count - 1);
            } else {
                printf("%s    [... directory too deep, truncated]\n", prefix);
            }
        } else {
            // File
            printf("📄 %s (%s, %s)\n", entries[i].name, size_str, time_str);
        }
    }
}

// Calculate estimated bitmap statistics (simplified - no access to internal bitmap reading)
void analyze_bitmap(mlfs_t *fs, uint32_t *used_blocks, uint32_t *free_blocks)
{
    // Since we can't access mlfs_read_block (internal API), we'll estimate based on filesystem structure
    // This is a simplified analysis that shows the theoretical capacity
    
    // Calculate minimum used blocks (system blocks + root directory)
    uint32_t system_blocks = 1 + fs->sb.bitmap_blocks + fs->sb.root_dir_blocks; // superblock + bitmap + root dir
    
    // For a more accurate estimate, we could count directory entries, but for now use a conservative estimate
    // In a real implementation, this would require access to the bitmap or directory traversal with size counting
    *used_blocks = system_blocks; // Minimum used blocks (conservative estimate)
    *free_blocks = (fs->sb.total_blocks > system_blocks) ? (fs->sb.total_blocks - system_blocks) : 0;
    
    // Note: This is a simplified analysis. For accurate block usage, 
    // the bitmap would need to be read using internal MLFS functions.
}

// Display general information and partition table
void display_general_info(FILE *file)
{
    printf("MLFS Filesystem Information\n");
    printf("===========================\n\n");
    
    // General Information
    printf("General Information:\n");
    
    // Get file size
    long current_pos = ftell(file);
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, current_pos, SEEK_SET); // Restore original position
    
    char file_size_str[16];
    format_size((uint64_t)file_size, file_size_str, sizeof(file_size_str));
    printf("  Image File Size: %ld bytes (%s)\n", file_size, file_size_str);
    
    // Calculate number of 512-byte sectors
    uint64_t total_sectors = (uint64_t)file_size / 512;
    printf("  Total Sectors:   %lu (512 bytes each)\n", total_sectors);
    printf("\n");
    
    // Partition Table Information
    mlpt_t pt;
    mlfs_io_t io = {
        .ctx = file,
        .read = info_file_read,
        .write = info_file_write,
        .sector_size = 512
    };
    
    if(mlfs_read_mlpt(&io, &pt) == 0) {
        printf("Partition Table:\n");
        printf("  Magic:           0x%08X\n", pt.magic);
        printf("  Version:         %u.%u.%u\n", pt.major, pt.minor, pt.patch);
        printf("  Partitions:      %u\n", pt.count);
        
        // Display all partitions
        for(uint16_t i = 0; i < pt.count; i++) {
            printf("  Partition %u:\n", i);
            printf("    Type:          %u", pt.entries[i].type);
            if(pt.entries[i].type == 1) {
                printf(" (MLFS)");
            }
            printf("\n");
            printf("    Start LBA:     %u\n", pt.entries[i].start_lba);
            printf("    Block Count:   %u blocks", pt.entries[i].block_count);
            
            char size_str[16];
            format_size((uint64_t)pt.entries[i].block_count * (1U << pt.entries[i].log2_block_size), size_str, sizeof(size_str));
            printf(" (%s)\n", size_str);
            printf("    Block Size:    %u bytes (log2: %u)\n", 1U << pt.entries[i].log2_block_size, pt.entries[i].log2_block_size);
            printf("    Name:          %.14s\n", pt.entries[i].name);
            
            // Calculate end LBA
            uint32_t sectors_per_block = (1U << pt.entries[i].log2_block_size) / 512;
            uint32_t end_lba = pt.entries[i].start_lba + (pt.entries[i].block_count * sectors_per_block) - 1;
            printf("    End LBA:       %u\n", end_lba);
            printf("    Sectors Used:  %u\n", pt.entries[i].block_count * sectors_per_block);
            
            if(i < pt.count - 1) printf("\n");
        }
        printf("\n");
    }
}

// Main function
int main(int argc, char **argv)
{
    if(argc < 2 || argc > 3) {
        printf("MLFS Filesystem Information Tool\n");
        printf("================================\n");
        printf("Usage: %s <mlfs_image_file> [partition_number]\n", argv[0]);
        printf("\nArguments:\n");
        printf("  mlfs_image_file   Path to the MLFS image file\n");
        printf("  partition_number  Partition to analyze (optional)\n");
        printf("\nBehavior:\n");
        printf("  Without partition_number: Shows general image info and partition table\n");
        printf("  With partition_number:    Additionally shows filesystem details and directory tree\n");
        printf("\nThis tool analyzes MLFS filesystem images and displays:\n");
        printf("  - General image file information (always)\n");
        printf("  - Partition table information (always)\n");
        printf("  - Superblock details (only when partition specified)\n");
        printf("  - Block allocation statistics (only when partition specified)\n");
        printf("  - Complete directory tree structure (only when partition specified)\n");
        return 1;
    }
    
    const char *image_path = argv[1];
    bool analyze_partition = (argc == 3); // Only analyze partition if explicitly specified
    uint16_t partition_number = 0;
    
    // Parse partition number if provided
    if(analyze_partition) {
        int part_num = atoi(argv[2]);
        if(part_num < 0 || part_num > 65535) {
            fprintf(stderr, "Error: Invalid partition number '%s' (must be 0-65535)\n", argv[2]);
            return 1;
        }
        partition_number = (uint16_t)part_num;
    }
    
    // Open image file
    FILE *file = fopen(image_path, "rb");
    if(!file) {
        fprintf(stderr, "Error: Cannot open image file '%s'\n", image_path);
        perror("fopen");
        return 1;
    }
    
    if(analyze_partition) {
        printf("Analyzing MLFS image: %s (partition %u)\n\n", image_path, partition_number);
    } else {
        printf("Analyzing MLFS image: %s (partition table overview)\n\n", image_path);
    }
    
    // Setup I/O
    mlfs_io_t io = {
        .ctx = file,
        .read = info_file_read,
        .write = info_file_write,
        .sector_size = 512
    };
    
    // Always display general and partition table information
    display_general_info(file);
    
    // Only analyze specific partition if requested
    if(!analyze_partition) {
        printf("Use '%s %s <partition_number>' to analyze a specific partition's filesystem and directory structure.\n", argv[0], image_path);
        fclose(file);  
        return 0;
    }
    
    // Try to mount the specified partition
    mlfs_t fs;
    int result = mlfs_mount(&io, partition_number, &fs);
    if(result != 0) {
        fprintf(stderr, "Error: Failed to mount MLFS partition %u (error %d)\n", partition_number, result);
        fprintf(stderr, "This partition may not contain a valid MLFS filesystem or may be corrupted.\n");
        fprintf(stderr, "Note: Partition table information above may still be valid.\n");
        fclose(file);
        return 1;
    }
    
    // Display partition-specific filesystem information
    printf("Partition %u Filesystem Details:\n", partition_number);
    printf("================================\n\n");
    
    // Superblock Information
    printf("Superblock:\n");
    printf("  Magic:           0x%08X\n", fs.sb.magic);
    printf("  Version:         %u.%u.%u\n", fs.sb.major, fs.sb.minor, fs.sb.patch);
    printf("  Block Size:      %u bytes (log2: %u)\n", 1U << fs.sb.log2_block_size, fs.sb.log2_block_size);
    printf("  Total Blocks:    %u", fs.sb.total_blocks);
    
    char total_size_str[16];
    format_size((uint64_t)fs.sb.total_blocks * (1U << fs.sb.log2_block_size), total_size_str, sizeof(total_size_str));
    printf(" (%s)\n", total_size_str);
    
    printf("  Bitmap Start:    block %u\n", fs.sb.bitmap_start);
    printf("  Bitmap Blocks:   %u", fs.sb.bitmap_blocks);
    
    char bitmap_size_str[16];
    format_size((uint64_t)fs.sb.bitmap_blocks * (1U << fs.sb.log2_block_size), bitmap_size_str, sizeof(bitmap_size_str));
    printf(" (%s)\n", bitmap_size_str);
    
    printf("  Root Directory:  block %u, %u blocks", fs.sb.root_dir_block, fs.sb.root_dir_blocks);
    
    char root_size_str[16];
    format_size((uint64_t)fs.sb.root_dir_blocks * (1U << fs.sb.log2_block_size), root_size_str, sizeof(root_size_str));
    printf(" (%s)\n", root_size_str);
    
    // UUID
    printf("  UUID:            ");
    for(int i = 0; i < 16; i++) {
        printf("%02x", ((uint8_t*)fs.sb.uuid)[i]);
        if(i == 3 || i == 5 || i == 7 || i == 9) printf("-");
    }
    printf("\n\n");
    
    // Block allocation statistics (estimated)
    printf("Block Allocation (Estimated):\n");
    uint32_t used_blocks, free_blocks;
    analyze_bitmap(&fs, &used_blocks, &free_blocks);
    
    char used_size_str[16], free_size_str[16];
    format_size((uint64_t)used_blocks * (1U << fs.sb.log2_block_size), used_size_str, sizeof(used_size_str));
    format_size((uint64_t)free_blocks * (1U << fs.sb.log2_block_size), free_size_str, sizeof(free_size_str));
    
    printf("  Min Used Blocks: %u (%s) [system blocks only]\n", used_blocks, used_size_str);
    printf("  Max Free Blocks: %u (%s)\n", free_blocks, free_size_str);
    printf("  Total Capacity:  %u blocks", fs.sb.total_blocks);
    
    char total_capacity_str[16];
    format_size((uint64_t)fs.sb.total_blocks * (1U << fs.sb.log2_block_size), total_capacity_str, sizeof(total_capacity_str));
    printf(" (%s)\n", total_capacity_str);
    
    printf("  Note: Actual usage may be higher (bitmap not accessible via public API)\n");
    printf("\n");
    
    // Display directory tree
    printf("Directory Structure:\n");
    printf("===================\n");
    display_directory_tree(&fs, "/", 0, "", 1);
    
    printf("\nAnalysis complete.\n");
    
    fclose(file);
    return 0;
}
