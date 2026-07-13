/****************************** test_filesystem.c ***************************/
// MLFS Core Filesystem Tests using Check framework

#include "test_common.h"

// Test fixtures
static mlfs_ramdisk_t test_disk;
static mlfs_io_t test_io;

// Setup function for filesystem tests
void setup_filesystem_test(void)
{
    const uint32_t sector_size = 512;
    const uint32_t disk_bytes = 32 * 1024 * 1024u; // 32MB test disk
    const uint32_t sectors = disk_bytes / sector_size;

    test_disk.sector_size = sector_size;
    test_disk.sectors = sectors;
    test_disk.mem = (uint8_t *)calloc(1, disk_bytes);
    ck_assert_ptr_ne(test_disk.mem, NULL);

    test_io.ctx = &test_disk;
    test_io.read = sim_read;
    test_io.write = sim_write;
    test_io.sector_size = sector_size;
}

// Teardown function for filesystem tests
void teardown_filesystem_test(void)
{
    if(test_disk.mem) {
        free(test_disk.mem);
        test_disk.mem = NULL;
    }
}

// Test fixed on-disk structure sizes used by the bootloader and kernel module
START_TEST(test_ondisk_structure_sizes)
{
    ck_assert_int_eq(sizeof(mlpt_entry_t), 24);
    ck_assert_int_eq(sizeof(mlpt_t), 512);
    ck_assert_int_eq(sizeof(mlfs_extent_t), 8);
    ck_assert_int_eq(sizeof(mlfs_dentry_t), 128);
    ck_assert_int_eq(sizeof(mlfs_superblock_t), 512);
}
END_TEST

// Test basic mkfs operation
START_TEST(test_mkfs_basic)
{
    // Create a single partition first
    uint32_t start_lba = 1;
    uint32_t sectors_total = 32768; // 16MB
    uint8_t log2_block_size = 12; // 4KB blocks
    
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, start_lba, sectors_total, log2_block_size));
    
    // Format the filesystem
    mlfs_t fs;
    int result = mlfs_mkfs(&test_io, 0, &fs);
    ck_assert_mlfs_ok(result);
    
    // Verify superblock was created correctly
    ck_assert_int_eq(fs.sb.magic, 0x4D4C4653u); // 'MLFS'
    ck_assert_int_eq(fs.sb.major, MLFS_VERSION_MAJOR);
    ck_assert_int_eq(fs.sb.minor, MLFS_VERSION_MINOR);
    ck_assert_int_eq(fs.sb.patch, MLFS_VERSION_PATCH);
    ck_assert_int_eq(fs.sb.log2_block_size, log2_block_size);
    
    // Check that basic filesystem structures were allocated
    ck_assert_int_gt(fs.sb.total_blocks, 0);
    ck_assert_int_eq(fs.sb.bitmap_start, 1);
    ck_assert_int_gt(fs.sb.bitmap_blocks, 0);
    ck_assert_int_gt(fs.sb.root_dir_block, fs.sb.bitmap_start);
    ck_assert_int_eq(fs.sb.root_dir_blocks, 2);

    uint32_t used_blocks = 0;
    uint32_t free_blocks = 0;
    ck_assert_mlfs_ok(mlfs_get_block_stats(&fs, &used_blocks, &free_blocks));
    ck_assert_int_eq(used_blocks, 1 + fs.sb.bitmap_blocks + fs.sb.root_dir_blocks);
    ck_assert_int_eq(free_blocks, fs.sb.total_blocks - used_blocks);
}
END_TEST

// Test mkfs with different block sizes
START_TEST(test_mkfs_different_block_sizes)
{
    // Test with 1KB blocks
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 10));
    mlfs_t fs1;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs1));
    ck_assert_int_eq(fs1.sb.log2_block_size, 10);
    ck_assert_int_eq(fs1.bytes_per_block, 1024);
    
    // Reset disk and test with 2KB blocks
    memset(test_disk.mem, 0, test_disk.sectors * test_disk.sector_size);
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 11));
    mlfs_t fs2;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs2));
    ck_assert_int_eq(fs2.sb.log2_block_size, 11);
    ck_assert_int_eq(fs2.bytes_per_block, 2048);
    
    // Reset disk and test with 8KB blocks
    memset(test_disk.mem, 0, test_disk.sectors * test_disk.sector_size);
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 13));
    mlfs_t fs3;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs3));
    ck_assert_int_eq(fs3.sb.log2_block_size, 13);
    ck_assert_int_eq(fs3.bytes_per_block, 8192);
}
END_TEST

// Test mounting formatted filesystem
START_TEST(test_mount_formatted_filesystem)
{
    // Create and format filesystem
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 12));
    mlfs_t fs_format;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs_format));
    
    // Mount the formatted filesystem
    mlfs_t fs_mount;
    int result = mlfs_mount(&test_io, 0, &fs_mount);
    ck_assert_mlfs_ok(result);
    
    // Verify mounted filesystem matches formatted one
    ck_assert_int_eq(fs_mount.sb.magic, fs_format.sb.magic);
    ck_assert_int_eq(fs_mount.sb.major, fs_format.sb.major);
    ck_assert_int_eq(fs_mount.sb.minor, fs_format.sb.minor);
    ck_assert_int_eq(fs_mount.sb.patch, fs_format.sb.patch);
    ck_assert_int_eq(fs_mount.sb.log2_block_size, fs_format.sb.log2_block_size);
    ck_assert_int_eq(fs_mount.sb.total_blocks, fs_format.sb.total_blocks);
    ck_assert_int_eq(fs_mount.sb.bitmap_start, fs_format.sb.bitmap_start);
    ck_assert_int_eq(fs_mount.sb.bitmap_blocks, fs_format.sb.bitmap_blocks);
    ck_assert_int_eq(fs_mount.sb.root_dir_block, fs_format.sb.root_dir_block);
    ck_assert_int_eq(fs_mount.sb.root_dir_blocks, fs_format.sb.root_dir_blocks);
}
END_TEST

// Test mkfs with multiple partitions
START_TEST(test_mkfs_multiple_partitions)
{
    // Create partition table with multiple partitions
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 1, 2048, 12, "part0"));
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 16385, 1024, 11, "part1"));
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 24577, 512, 10, "part2"));
    
    // Format each partition
    mlfs_t fs0, fs1, fs2;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs0));
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 1, &fs1));  
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 2, &fs2));
    
    // Verify each filesystem has correct block size
    ck_assert_int_eq(fs0.sb.log2_block_size, 12);
    ck_assert_int_eq(fs1.sb.log2_block_size, 11);
    ck_assert_int_eq(fs2.sb.log2_block_size, 10);
    
    // Verify each can be mounted independently
    mlfs_t mount0, mount1, mount2;
    ck_assert_mlfs_ok(mlfs_mount(&test_io, 0, &mount0));
    ck_assert_mlfs_ok(mlfs_mount(&test_io, 1, &mount1));
    ck_assert_mlfs_ok(mlfs_mount(&test_io, 2, &mount2));
}
END_TEST

// Test mounting non-existent partition
START_TEST(test_mount_nonexistent_partition)
{
    // Create single partition (index 0)
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 12));
    mlfs_t fs;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs));
    
    // Try to mount partition 1 (doesn't exist)
    mlfs_t mount_fs;
    int result = mlfs_mount(&test_io, 1, &mount_fs);
    ck_assert_int_eq(result, -3); // Partition doesn't exist
    
    // Try to mount partition 99 (way out of range)  
    result = mlfs_mount(&test_io, 99, &mount_fs);
    ck_assert_int_eq(result, -3); // Partition doesn't exist
}
END_TEST

// Test mounting unformatted partition
START_TEST(test_mount_unformatted_partition)
{
    // Create partition but don't format it
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 12));
    
    // Try to mount unformatted partition
    mlfs_t fs;
    int result = mlfs_mount(&test_io, 0, &fs);
    ck_assert_int_eq(result, -10); // Invalid superblock/not formatted
}
END_TEST

// Test mounting wrong partition type
START_TEST(test_mount_wrong_partition_type)
{
    // Create empty partition table and add non-MLFS partition
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    
    // Manually add partition with wrong type
    mlpt_t pt;
    ck_assert_mlfs_ok(mlfs_read_mlpt(&test_io, &pt));
    
    pt.count = 1;
    pt.entries[0].start_lba = 1;
    pt.entries[0].block_count = 1024;
    pt.entries[0].log2_block_size = 12;
    pt.entries[0].type = 2; // Not MLFS type (should be 1)
    strcpy(pt.entries[0].name, "wrong_type");
    
    ck_assert_mlfs_ok(mlfs_write_mlpt(&test_io, &pt));
    
    // Try to format/mount wrong type partition
    mlfs_t fs;
    int result = mlfs_mkfs(&test_io, 0, &fs);
    ck_assert_int_eq(result, -4); // Wrong partition type
    
    result = mlfs_mount(&test_io, 0, &fs);
    ck_assert_int_eq(result, -4); // Wrong partition type
}
END_TEST

// Test filesystem error handling
START_TEST(test_filesystem_error_handling)
{
    // Test with NULL parameters
    mlfs_t fs;
    
    int result = mlfs_mkfs(NULL, 0, &fs);
    ck_assert_int_ne(result, 0);
    
    result = mlfs_mkfs(&test_io, 0, NULL);
    ck_assert_int_ne(result, 0);
    
    result = mlfs_mount(NULL, 0, &fs);
    ck_assert_int_ne(result, 0);
    
    result = mlfs_mount(&test_io, 0, NULL);
    ck_assert_int_ne(result, 0);
}
END_TEST

// Test superblock validation
START_TEST(test_superblock_validation)
{
    // Create and format filesystem
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, 16384, 12));
    mlfs_t fs;
    ck_assert_mlfs_ok(mlfs_mkfs(&test_io, 0, &fs));
    
    // Verify superblock checksum validation by corrupting it
    // Read the superblock directly from disk
    uint8_t sector[512];
    ck_assert_mlfs_ok(test_io.read(test_io.ctx, 1, 1, sector)); // LBA 1 = partition start
    
    // Corrupt magic number
    uint32_t *magic = (uint32_t*)sector;
    *magic = 0xDEADBEEF;
    ck_assert_mlfs_ok(test_io.write(test_io.ctx, 1, 1, sector)); // Write corrupted sector
    
    // Try to mount corrupted filesystem
    mlfs_t mount_fs;
    int result = mlfs_mount(&test_io, 0, &mount_fs);
    ck_assert_int_eq(result, -10); // Invalid superblock
}
END_TEST

// Test filesystem with minimal disk space
START_TEST(test_minimal_filesystem)
{
    // Create very small partition (minimum viable size)
    // Need at least: 1 superblock + 1 bitmap + 2 root dir blocks = 4 blocks minimum
    uint32_t min_sectors = 4 * 8; // 4 blocks * 8 sectors per 4KB block
    ck_assert_mlfs_ok(mlfs_make_single_partition(&test_io, 1, min_sectors, 12));
    
    mlfs_t fs;
    int result = mlfs_mkfs(&test_io, 0, &fs);
    ck_assert_mlfs_ok(result);
    
    // Verify it can be mounted
    mlfs_t mount_fs;
    ck_assert_mlfs_ok(mlfs_mount(&test_io, 0, &mount_fs));
    
    // Verify basic structure
    ck_assert_int_eq(mount_fs.sb.total_blocks, 4);
    ck_assert_int_eq(mount_fs.sb.bitmap_blocks, 1);
    ck_assert_int_eq(mount_fs.sb.root_dir_blocks, 2);
}
END_TEST

// Main test suite
Suite *filesystem_suite(void)
{
    Suite *s;
    TCase *tc_mkfs, *tc_mount, *tc_multi, *tc_errors, *tc_validation;

    s = suite_create("Filesystem Operations");

    // mkfs tests  
    tc_mkfs = tcase_create("Format");
    tcase_add_checked_fixture(tc_mkfs, setup_filesystem_test, teardown_filesystem_test);
    tcase_add_test(tc_mkfs, test_mkfs_basic);
    tcase_add_test(tc_mkfs, test_mkfs_different_block_sizes);
    tcase_add_test(tc_mkfs, test_minimal_filesystem);
    suite_add_tcase(s, tc_mkfs);

    // mount tests
    tc_mount = tcase_create("Mount");
    tcase_add_checked_fixture(tc_mount, setup_filesystem_test, teardown_filesystem_test);
    tcase_add_test(tc_mount, test_mount_formatted_filesystem);
    tcase_add_test(tc_mount, test_mount_nonexistent_partition);
    tcase_add_test(tc_mount, test_mount_unformatted_partition);
    tcase_add_test(tc_mount, test_mount_wrong_partition_type);
    suite_add_tcase(s, tc_mount);

    // multi-partition tests
    tc_multi = tcase_create("Multi-Partition");
    tcase_add_checked_fixture(tc_multi, setup_filesystem_test, teardown_filesystem_test);
    tcase_add_test(tc_multi, test_mkfs_multiple_partitions);
    suite_add_tcase(s, tc_multi);

    // validation tests
    tc_validation = tcase_create("Validation");
    tcase_add_checked_fixture(tc_validation, setup_filesystem_test, teardown_filesystem_test);
    tcase_add_test(tc_validation, test_ondisk_structure_sizes);
    tcase_add_test(tc_validation, test_superblock_validation);
    suite_add_tcase(s, tc_validation);

    // error handling tests
    tc_errors = tcase_create("Error Handling");
    tcase_add_checked_fixture(tc_errors, setup_filesystem_test, teardown_filesystem_test);
    tcase_add_test(tc_errors, test_filesystem_error_handling);
    suite_add_tcase(s, tc_errors);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = filesystem_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
