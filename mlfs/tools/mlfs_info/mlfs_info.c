/****************************** mlfs_info.c *****************************/
// MLFS Filesystem Information and Analysis Tool
// Parses MLFS image files and displays detailed filesystem information

#include "mlfs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
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

static uint16_t get_be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static uint32_t get_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) |
           ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) |
           (uint32_t)p[3];
}

static void decode_mlpt_sector(const uint8_t sector[512], mlpt_t *pt)
{
    memset(pt, 0, sizeof(*pt));
    pt->magic = get_be32(sector + 0);
    pt->major = sector[4];
    pt->minor = sector[5];
    pt->patch = sector[6];
    pt->count = get_be16(sector + 7);

    for(uint16_t i = 0; i < MLPT_MAX_PARTS; ++i) {
        const uint8_t *entry = sector + 9 + (i * sizeof(mlpt_entry_t));
        pt->entries[i].start_lba = get_be32(entry + 0);
        pt->entries[i].block_count = get_be32(entry + 4);
        pt->entries[i].type = entry[8];
        pt->entries[i].log2_block_size = entry[9];
        memcpy(pt->entries[i].name, entry + 10, sizeof(pt->entries[i].name));
    }
}

static int read_mlpt_for_diagnostics(FILE *file, mlpt_t *pt)
{
    uint8_t sector[512];
    long current_pos = ftell(file);
    if(info_file_read(file, 0, 1, sector) != 0) {
        if(current_pos >= 0) {
            fseek(file, current_pos, SEEK_SET);
        }
        return -1;
    }
    if(current_pos >= 0) {
        fseek(file, current_pos, SEEK_SET);
    }

    decode_mlpt_sector(sector, pt);
    if(pt->magic != MLPT_MAGIC) {
        return -2;
    }
    if(pt->major != MLPT_VERSION_MAJOR ||
       pt->minor != MLPT_VERSION_MINOR ||
       pt->patch != MLPT_VERSION_PATCH) {
        return -3;
    }
    return 0;
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

// Read actual bitmap statistics through the public MLFS API
int analyze_bitmap(mlfs_t *fs, uint32_t *used_blocks, uint32_t *free_blocks)
{
    return mlfs_get_block_stats(fs, used_blocks, free_blocks);
}

// Display general information and partition table
int display_general_info(FILE *file, mlpt_t *pt_out)
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
    int pt_status = read_mlpt_for_diagnostics(file, &pt);
    if(pt_out) {
        *pt_out = pt;
    }

    if(pt_status == -1) {
        printf("Partition Table:\n");
        printf("  Error:           Could not read sector 0\n\n");
        return pt_status;
    }

    if(pt.magic == MLPT_MAGIC) {
        printf("Partition Table:\n");
        printf("  Magic:           0x%08X\n", pt.magic);
        printf("  Version:         %u.%u.%u\n", pt.major, pt.minor, pt.patch);
        if(pt_status == -3) {
            printf("  Warning:         Unsupported MLPT version for this build; expected %u.%u.%u\n",
                   MLPT_VERSION_MAJOR,
                   MLPT_VERSION_MINOR,
                   MLPT_VERSION_PATCH);
        }
        printf("  Partitions:      %u\n", pt.count);
        
        // Display all partitions
        uint16_t display_count = pt.count > MLPT_MAX_PARTS ? MLPT_MAX_PARTS : pt.count;
        if(pt.count > MLPT_MAX_PARTS) {
            printf("  Warning:         Partition count exceeds MLPT_MAX_PARTS (%u); showing first %u\n",
                   MLPT_MAX_PARTS,
                   display_count);
        }
        for(uint16_t i = 0; i < display_count; i++) {
            printf("  Partition %u:\n", i);
            printf("    Type:          %u", pt.entries[i].type);
            if(pt.entries[i].type == 1) {
                printf(" (MLFS)");
            }
            printf("\n");
            printf("    Start LBA:     %u\n", pt.entries[i].start_lba);
            printf("    Block Count:   %u blocks", pt.entries[i].block_count);
            
            char size_str[16];
            uint64_t block_size = pt.entries[i].log2_block_size < 32 ? (1ULL << pt.entries[i].log2_block_size) : 0;
            format_size((uint64_t)pt.entries[i].block_count * block_size, size_str, sizeof(size_str));
            printf(" (%s)\n", size_str);
            if(block_size > 0) {
                printf("    Block Size:    %" PRIu64 " bytes (log2: %u)\n", block_size, pt.entries[i].log2_block_size);
            } else {
                printf("    Block Size:    invalid (log2: %u)\n", pt.entries[i].log2_block_size);
            }
            printf("    Name:          %.14s\n", pt.entries[i].name);
            
            // Calculate end LBA
            uint64_t sectors_per_block = block_size / 512;
            uint64_t sectors_used = (uint64_t)pt.entries[i].block_count * sectors_per_block;
            uint64_t end_lba = (sectors_used == 0) ? pt.entries[i].start_lba : (uint64_t)pt.entries[i].start_lba + sectors_used - 1;
            printf("    End LBA:       %" PRIu64 "\n", end_lba);
            printf("    Sectors Used:  %" PRIu64 "\n", sectors_used);
            
            if(i < display_count - 1) printf("\n");
        }
        printf("\n");
    } else {
        printf("Partition Table:\n");
        printf("  Magic:           0x%08X\n", pt.magic);
        printf("  Error:           Sector 0 does not contain an MLPT header\n\n");
    }

    return pt_status;
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
    mlpt_t pt;
    int pt_status = display_general_info(file, &pt);
    
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
        fflush(stdout);
        if(pt_status == -3) {
            fprintf(stderr,
                    "Error: The image has MLPT version %u.%u.%u, but this tool expects %u.%u.%u.\n",
                    pt.major,
                    pt.minor,
                    pt.patch,
                    MLPT_VERSION_MAJOR,
                    MLPT_VERSION_MINOR,
                    MLPT_VERSION_PATCH);
            fprintf(stderr, "The partition table was decoded for display, but this build will not mount incompatible MLPT versions.\n");
        } else if(pt_status != 0) {
            fprintf(stderr, "Error: Could not read a compatible MLPT partition table (error %d).\n", pt_status);
        }
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
    
    // Block allocation statistics
    printf("Block Allocation:\n");
    uint32_t used_blocks, free_blocks;
    int stats_result = analyze_bitmap(&fs, &used_blocks, &free_blocks);
    if(stats_result != 0) {
        printf("  Error:           Could not read allocation bitmap (error %d)\n", stats_result);
        printf("\n");
        fclose(file);
        return 1;
    }
    
    char used_size_str[16], free_size_str[16];
    format_size((uint64_t)used_blocks * (1U << fs.sb.log2_block_size), used_size_str, sizeof(used_size_str));
    format_size((uint64_t)free_blocks * (1U << fs.sb.log2_block_size), free_size_str, sizeof(free_size_str));
    
    printf("  Used Blocks:     %u (%s)\n", used_blocks, used_size_str);
    printf("  Free Blocks:     %u (%s)\n", free_blocks, free_size_str);
    printf("  Total Capacity:  %u blocks", fs.sb.total_blocks);
    
    char total_capacity_str[16];
    format_size((uint64_t)fs.sb.total_blocks * (1U << fs.sb.log2_block_size), total_capacity_str, sizeof(total_capacity_str));
    printf(" (%s)\n", total_capacity_str);
    
    printf("\n");
    
    // Display directory tree only when the root directory has entries.
    mlfs_dentry_t root_probe[1];
    uint32_t root_count = 0;
    int root_result = mlfs_read_directory(&fs, "/", root_probe, 1, &root_count);
    bool displayed_directory = false;
    if(root_result != 0) {
        printf("Directory Structure:\n");
        printf("===================\n");
        display_directory_tree(&fs, "/", 0, "", 1);
        displayed_directory = true;
    } else if(root_count > 0) {
        printf("Directory Structure:\n");
        printf("===================\n");
        display_directory_tree(&fs, "/", 0, "", 1);
        displayed_directory = true;
    }
    
    printf("%sAnalysis complete.\n", displayed_directory ? "\n" : "");
    
    fclose(file);
    return 0;
}
