/****************************** test_common.h ********************************/
// Common test utilities for MLFS tests using Check framework
#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include "mlfs.h"
#include <check.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Simple RAM-disk for tests
typedef struct {
    uint8_t *mem;
    uint32_t sectors;
    uint32_t sector_size;
} mlfs_ramdisk_t;

// RAM disk I/O functions
static inline int sim_read(void *ctx, uint64_t lba, uint32_t count, void *buf)
{
    mlfs_ramdisk_t *d = (mlfs_ramdisk_t *)ctx;
    if(lba + count > d->sectors)
        return -1;
    memcpy(buf, d->mem + (size_t)lba * d->sector_size, (size_t)count * d->sector_size);
    return 0;
}

static inline int sim_write(void *ctx, uint64_t lba, uint32_t count, const void *buf)
{
    mlfs_ramdisk_t *d = (mlfs_ramdisk_t *)ctx;
    if(lba + count > d->sectors)
        return -1;
    memcpy(d->mem + (size_t)lba * d->sector_size, buf, (size_t)count * d->sector_size);
    return 0;
}

// Helper function to create and format a test filesystem
static inline int setup_test_filesystem(mlfs_ramdisk_t *rd, mlfs_io_t *io, mlfs_t *fs, uint8_t log2_block)
{
    const uint32_t sector = 512;
    const uint32_t disk_bytes = 64 * 1024 * 1024u;
    const uint32_t sectors = disk_bytes / sector;

    rd->sector_size = sector;
    rd->sectors = sectors;
    rd->mem = (uint8_t *)calloc(1, disk_bytes);
    if(!rd->mem)
        return -1;

    io->ctx = rd;
    io->read = sim_read;
    io->write = sim_write;
    io->sector_size = sector;

    const uint32_t start_lba = 1;
    const uint32_t sectors_total = sectors - start_lba;

    if(mlfs_make_single_partition(io, start_lba, sectors_total, log2_block) != 0)
        return -1;

    if(mlfs_mkfs(io, 0, fs) != 0)
        return -1;

    return 0;
}

// Helper to cleanup test filesystem
static inline void cleanup_test_filesystem(mlfs_ramdisk_t *rd)
{
    if(rd->mem) {
        free(rd->mem);
        rd->mem = NULL;
    }
}

// Global test fixtures (for use in setup/teardown functions)
extern mlfs_ramdisk_t g_test_ramdisk;
extern mlfs_io_t g_test_io;
extern mlfs_t g_test_fs;
extern mlfs_t g_test_mnt;

// Common setup function for Check framework tests
void setup_mlfs_test(void);

// Common teardown function for Check framework tests
void teardown_mlfs_test(void);

// Helper macros for common Check assertions
#define ck_assert_mlfs_ok(call) ck_assert_int_eq(call, 0)
#define ck_assert_mlfs_fail(call) ck_assert_int_ne(call, 0)

#endif // TEST_COMMON_H
