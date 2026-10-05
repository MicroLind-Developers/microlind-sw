/* Build boot fixtures using the production host library, not a duplicate encoder. */
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include "mlfs.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int read_sectors(void *context, uint64_t lba, uint32_t count, void *buffer)
{
    FILE *file = context;
    return fseeko(file, (off_t)(lba * 512), SEEK_SET) ||
           fread(buffer, 512, count, file) != count ? -1 : 0;
}

static int write_sectors(void *context, uint64_t lba, uint32_t count, const void *buffer)
{
    FILE *file = context;
    return fseeko(file, (off_t)(lba * 512), SEEK_SET) ||
           fwrite(buffer, 512, count, file) != count ? -1 : 0;
}

static int add_diagnostic(mlfs_t *fs, const char *path)
{
    FILE *file = fopen(path, "rb");
    if (!file || fseeko(file, 0, SEEK_END)) return 1;
    off_t size = ftello(file);
    if (size < 1 || size > 65535 || fseeko(file, 0, SEEK_SET)) return 1;
    unsigned char *data = malloc((size_t)size);
    if (!data || fread(data, 1, (size_t)size, file) != (size_t)size) return 1;
    fclose(file);
    uint32_t blocks = (uint32_t)((size + fs->bytes_per_block - 1) / fs->bytes_per_block);
    int failed = mlfs_create_empty_file(fs, "fsdiag.mlp", blocks) ||
                 mlfs_pwrite_file(fs, "fsdiag.mlp", data, (size_t)size, 0) != size;
    free(data);
    return failed;
}

int main(int argc, char **argv)
{
    if (argc < 5 || argc > 8) return 1; /* Optional data, test blocks, diagnostic. */
    unsigned log2 = (unsigned)strtoul(argv[2], NULL, 0);
    unsigned slot = (unsigned)strtoul(argv[4], NULL, 0);
    if (log2 < 9 || log2 > 16 || slot > 7) return 1;
    FILE *module = fopen(argv[3], "rb");
    if (!module || fseeko(module, 0, SEEK_END)) return 1;
    off_t length = ftello(module);
    if (length < 1 || length > 65535 || fseeko(module, 0, SEEK_SET)) return 1;
    unsigned char *payload = malloc((size_t)length);
    if (!payload || fread(payload, 1, (size_t)length, module) != (size_t)length) return 1;
    fclose(module);
    unsigned char *data = NULL;
    size_t data_length = 0;
    uint32_t diagnostic_blocks = argc >= 7 ? (uint32_t)strtoul(argv[6], NULL, 0) : 32;
    if (diagnostic_blocks < 8 || diagnostic_blocks > 8192) return 1;
    if (argc >= 6) {
        FILE *input = fopen(argv[5], "rb");
        if (!input || fseeko(input, 0, SEEK_END)) return 1;
        off_t size = ftello(input);
        if (size < 1 || size > 1048576 || fseeko(input, 0, SEEK_SET)) return 1;
        data_length = (size_t)size;
        data = malloc(data_length);
        if (!data || fread(data, 1, data_length, input) != data_length) return 1;
        fclose(input);
    }
    FILE *disk = fopen(argv[1], "w+b");
    if (!disk) return 1;
    uint32_t primary_blocks = 96;
    if (data) {
        uint32_t wanted = (uint32_t)((data_length * 2 + (1u << log2) - 1) >> log2) + 32;
        if (wanted > primary_blocks) primary_blocks = wanted;
    }
    uint32_t sectors = 1 + (primary_blocks << (log2 - 9));
    uint32_t total_sectors = sectors + (data ? (diagnostic_blocks << (log2 - 9)) : 0);
    if (ftruncate(fileno(disk), (off_t)total_sectors * 512)) return 1;
    mlfs_io_t io = {disk, read_sectors, write_sectors, 512};
    mlfs_t fs;
    /* The library takes the partition's sector count, excluding its start LBA. */
    if (mlfs_make_single_partition(&io, 1, sectors - 1, (uint8_t)log2) ||
        mlfs_mkfs(&io, 0, &fs)) return 1;
    for (unsigned i = 0; i < slot; ++i) {
        char name[24];
        snprintf(name, sizeof name, "unused%u", i);
        if (mlfs_create_empty_file(&fs, name, 1)) return 1;
    }
    uint32_t blocks = ((uint32_t)length + (1u << log2) - 1) >> log2;
    if (mlfs_create_empty_file(&fs, "biosfs.mlp", blocks) ||
        mlfs_pwrite_file(&fs, "biosfs.mlp", payload, (size_t)length, 0) != length) return 1;
    free(payload);
    if (data) {
        blocks = (uint32_t)((data_length + (1u << log2) - 1) >> log2);
        if (mlfs_create_empty_file(&fs, "data.bin", blocks) ||
            mlfs_pwrite_file(&fs, "data.bin", data, data_length, 0) != (ssize_t)data_length ||
            mlfs_create_directory(&fs, "docs", 1) ||
            mlfs_create_directory(&fs, "docs/sub", 1) ||
            mlfs_create_empty_file(&fs, "docs/sub/data.bin", blocks) ||
            mlfs_pwrite_file(&fs, "docs/sub/data.bin", data, data_length, 0) != (ssize_t)data_length) return 1;
        if (argc == 8 && add_diagnostic(&fs, argv[7])) return 1;
        if (mlfs_add_partition(&io, sectors, diagnostic_blocks, (uint8_t)log2, "diagnostics") ||
            mlfs_mkfs(&io, 1, &fs) ||
            mlfs_create_empty_file(&fs, "other.txt", 1) ||
            mlfs_pwrite_file(&fs, "other.txt", "partition1", 10, 0) != 10) return 1;
        free(data);
    }
    return fclose(disk) ? 1 : 0;
}
