/****************************** file_io.c ***********************************/
// File I/O layer for MLFS CLI - handles reading/writing disk image files
#include "cli_commands.h"

// Read sectors from disk image file
int file_io_read(void *ctx, uint64_t lba, uint32_t count, void *buf)
{
    FILE *file = (FILE *)ctx;
    if(!file)
        return -1;

    // Calculate byte offset (LBA * 512 bytes per sector)
    uint64_t offset = lba * 512;
    size_t bytes_to_read = count * 512;

    // Seek to position
    if(fseek(file, offset, SEEK_SET) != 0) {
        perror("fseek");
        return -1;
    }

    // Read data
    size_t bytes_read = fread(buf, 1, bytes_to_read, file);
    if(bytes_read != bytes_to_read) {
        if(feof(file)) {
            // If we hit EOF, zero-fill the remaining buffer
            memset((uint8_t *)buf + bytes_read, 0, bytes_to_read - bytes_read);
        } else {
            perror("fread");
            return -1;
        }
    }

    return 0;
}

// Write sectors to disk image file
int file_io_write(void *ctx, uint64_t lba, uint32_t count, const void *buf)
{
    FILE *file = (FILE *)ctx;
    if(!file)
        return -1;

    // Calculate byte offset (LBA * 512 bytes per sector)
    uint64_t offset = lba * 512;
    size_t bytes_to_write = count * 512;

    // Seek to position
    if(fseek(file, offset, SEEK_SET) != 0) {
        perror("fseek");
        return -1;
    }

    // Write data
    size_t bytes_written = fwrite(buf, 1, bytes_to_write, file);
    if(bytes_written != bytes_to_write) {
        perror("fwrite");
        return -1;
    }

    // Flush to ensure data is written
    if(fflush(file) != 0) {
        perror("fflush");
        return -1;
    }

    return 0;
}
