/****************************** test_common.c ********************************/
// Common test utilities implementation for MLFS tests using Check framework
#include "test_common.h"

// Global test fixtures
mlfs_ramdisk_t g_test_ramdisk;
mlfs_io_t g_test_io;
mlfs_t g_test_fs;
mlfs_t g_test_mnt;

// Setup function called before each test
void setup_mlfs_test(void)
{
    memset(&g_test_ramdisk, 0, sizeof(g_test_ramdisk));
    memset(&g_test_io, 0, sizeof(g_test_io));
    memset(&g_test_fs, 0, sizeof(g_test_fs));
    memset(&g_test_mnt, 0, sizeof(g_test_mnt));

    // Setup with 4KB blocks by default
    ck_assert_mlfs_ok(setup_test_filesystem(&g_test_ramdisk, &g_test_io, &g_test_fs, 12));
    ck_assert_mlfs_ok(mlfs_mount(&g_test_io, 0, &g_test_mnt));
}

// Teardown function called after each test
void teardown_mlfs_test(void)
{
    //cleanup_test_filesystem(&g_test_ramdisk);
}
