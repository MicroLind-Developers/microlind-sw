/* Read target-modified images with the production host library. */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include "mlfs.h"
#include <stdio.h>
#include <stdlib.h>

static int read_sectors(void *context, uint64_t lba, uint32_t count, void *buffer)
{
    FILE *file = context;
    return fseeko(file, (off_t)(lba * 512), SEEK_SET) ||
           fread(buffer, 512, count, file) != count ? -1 : 0;
}

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 5) return 1;
    FILE *disk = fopen(argv[1], "rb");
    if (!disk) return 1;
    mlfs_io_t io = {disk, read_sectors, NULL, 512};
    mlfs_t fs;
    uint32_t used, available;
    if (mlfs_mount(&io, (uint16_t)strtoul(argv[2], NULL, 0), &fs) ||
        mlfs_get_block_stats(&fs, &used, &available)) return 1;
    printf("%u %u\n", used, available);
    if (argc == 5) {
        FILE *output = fopen(argv[4], "wb");
        if (!output) return 1;
        unsigned char buffer[4096];
        size_t offset = 0;
        for (;;) {
            ssize_t got = mlfs_pread_file(&fs, argv[3], buffer, sizeof buffer, offset);
            if (got < 0) return 2;
            if (!got) break;
            if (fwrite(buffer, 1, (size_t)got, output) != (size_t)got) return 1;
            offset += (size_t)got;
        }
        if (fclose(output)) return 1;
    } else {
        mlfs_dentry_t *entries = calloc(4096, sizeof *entries);
        uint32_t count;
        if (!entries || mlfs_read_directory(&fs, argv[3], entries, 4096, &count)) return 2;
        for (uint32_t i = 0; i < count; ++i)
            printf("%u %u %u %u %s\n", entries[i].flags, entries[i].size_bytes,
                   entries[i].extents[0].start, entries[i].extents[0].length, entries[i].name);
        free(entries);
    }
    return fclose(disk) ? 1 : 0;
}
