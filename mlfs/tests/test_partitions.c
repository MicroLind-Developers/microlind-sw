/****************************** test_partitions.c ***************************/
// MLFS Partition Table Tests using Check framework

#include "test_common.h"

// Test fixtures
static mlfs_ramdisk_t test_disk;
static mlfs_io_t test_io;

// Setup function for partition table tests
void setup_partition_test(void)
{
    const uint32_t sector_size = 512;
    const uint32_t disk_bytes = 16 * 1024 * 1024u; // 16MB test disk
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

// Teardown function for partition table tests
void teardown_partition_test(void)
{
    if(test_disk.mem) {
        free(test_disk.mem);
        test_disk.mem = NULL;
    }
}

// Test creating empty partition table
START_TEST(test_make_empty_partition_table)
{
    int result = mlfs_make_empty_partition_table(&test_io);
    ck_assert_mlfs_ok(result);

    // Verify we can read the partition table back
    mlpt_t pt;
    result = mlfs_read_mlpt(&test_io, &pt);
    ck_assert_mlfs_ok(result);
    
    // Check partition table structure
    ck_assert_int_eq(pt.magic, 0x4D4C5054u); // 'MLPT'
    ck_assert_int_eq(pt.major, 0);
    ck_assert_int_eq(pt.minor, 1);
    ck_assert_int_eq(pt.patch, 0);
    ck_assert_int_eq(pt.count, 0); // No partitions initially
}
END_TEST

// Test adding single partition
START_TEST(test_add_single_partition)
{
    // Create empty partition table first
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    
    // Add a partition
    uint32_t start_lba = 1;
    uint32_t block_count = 1024; // 4MB at 4KB blocks
    uint8_t log2_block_size = 12; // 4KB blocks
    const char *name = "test_part";
    
    int result = mlfs_add_partition(&test_io, start_lba, block_count, log2_block_size, name);
    ck_assert_mlfs_ok(result);
    
    // Verify partition was added
    mlpt_t pt;
    ck_assert_mlfs_ok(mlfs_read_mlpt(&test_io, &pt));
    ck_assert_int_eq(pt.count, 1);
    
    mlpt_entry_t *entry = &pt.entries[0];
    ck_assert_int_eq(entry->start_lba, start_lba);
    ck_assert_int_eq(entry->block_count, block_count);
    ck_assert_int_eq(entry->log2_block_size, log2_block_size);
    ck_assert_int_eq(entry->type, 1); // MLFS type
    ck_assert_str_eq(entry->name, name);
}
END_TEST

// Test adding multiple partitions
START_TEST(test_add_multiple_partitions)
{
    // Create empty partition table
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    
    // Add first partition
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 1, 512, 12, "main"));
    
    // Add second partition (non-overlapping)
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 8193, 256, 11, "backup"));
    
    // Add third partition
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 16385, 128, 10, "logs"));
    
    // Verify all partitions
    mlpt_t pt;
    ck_assert_mlfs_ok(mlfs_read_mlpt(&test_io, &pt));
    ck_assert_int_eq(pt.count, 3);
    
    // Check partition details
    ck_assert_str_eq(pt.entries[0].name, "main");
    ck_assert_int_eq(pt.entries[0].start_lba, 1);
    ck_assert_int_eq(pt.entries[0].block_count, 512);
    
    ck_assert_str_eq(pt.entries[1].name, "backup");
    ck_assert_int_eq(pt.entries[1].start_lba, 8193);
    ck_assert_int_eq(pt.entries[1].block_count, 256);
    
    ck_assert_str_eq(pt.entries[2].name, "logs");
    ck_assert_int_eq(pt.entries[2].start_lba, 16385);
    ck_assert_int_eq(pt.entries[2].block_count, 128);
}
END_TEST

// Test partition overlap detection
START_TEST(test_partition_overlap_detection)
{
    // Create empty partition table and add first partition
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    ck_assert_mlfs_ok(mlfs_add_partition(&test_io, 1, 1024, 12, "first"));
    
    // Try to add overlapping partition (should fail)
    // First partition uses LBAs 1-8192 (1024 blocks * 8 sectors/block)
    int result = mlfs_add_partition(&test_io, 4096, 512, 12, "overlap");
    ck_assert_int_ne(result, 0); // Should fail due to overlap
    
    // Try to add partition that starts before first ends (should fail)
    result = mlfs_add_partition(&test_io, 8192, 256, 12, "early");
    ck_assert_int_ne(result, 0); // Should fail due to overlap
    
    // Add non-overlapping partition (should succeed)
    result = mlfs_add_partition(&test_io, 8193, 256, 12, "after");
    ck_assert_mlfs_ok(result);
}
END_TEST

// Test partition table limits
START_TEST(test_partition_table_limits)
{
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    
    // Add maximum number of partitions (16)
    for(int i = 0; i < 16; i++) {
        char name[16];
        snprintf(name, sizeof(name), "part%d", i);
        uint32_t start_lba = 1 + i * 100; // Non-overlapping partitions
        int result = mlfs_add_partition(&test_io, start_lba, 10, 9, name); // Small partitions
        ck_assert_mlfs_ok(result);
    }
    
    // Try to add 17th partition (should fail)
    int result = mlfs_add_partition(&test_io, 2000, 10, 9, "too_many");
    ck_assert_int_ne(result, 0); // Should fail - too many partitions
}
END_TEST

// Test invalid partition parameters
START_TEST(test_invalid_partition_parameters)
{
    ck_assert_mlfs_ok(mlfs_make_empty_partition_table(&test_io));
    
    // Test invalid start LBA (0 is reserved for partition table)
    int result = mlfs_add_partition(&test_io, 0, 100, 12, "invalid_start");
    ck_assert_int_ne(result, 0);
    
    // Test zero block count
    result = mlfs_add_partition(&test_io, 1, 0, 12, "zero_blocks");
    ck_assert_int_ne(result, 0);
    
    // Test invalid block size (too small)
    result = mlfs_add_partition(&test_io, 1, 100, 8, "too_small");
    ck_assert_int_ne(result, 0);
    
    // Test invalid block size (too large)
    result = mlfs_add_partition(&test_io, 1, 100, 17, "too_large");
    ck_assert_int_ne(result, 0);
    
    // Test NULL name
    result = mlfs_add_partition(&test_io, 1, 100, 12, NULL);
    ck_assert_int_ne(result, 0);
    
    // Test empty name  
    result = mlfs_add_partition(&test_io, 1, 100, 12, "");
    ck_assert_int_ne(result, 0);
}
END_TEST

// Test legacy single partition function
START_TEST(test_make_single_partition)
{
    uint32_t start_lba = 1;
    uint32_t sectors_total = 16384; // 8MB
    uint8_t log2_block_size = 12; // 4KB blocks
    
    int result = mlfs_make_single_partition(&test_io, start_lba, sectors_total, log2_block_size);
    ck_assert_mlfs_ok(result);
    
    // Verify partition table was created with one partition
    mlpt_t pt;
    ck_assert_mlfs_ok(mlfs_read_mlpt(&test_io, &pt));
    ck_assert_int_eq(pt.count, 1);
    
    mlpt_entry_t *entry = &pt.entries[0];
    ck_assert_int_eq(entry->start_lba, start_lba);
    ck_assert_int_eq(entry->log2_block_size, log2_block_size);
    ck_assert_int_eq(entry->type, 1);
    // Block count should be calculated from sectors_total
    uint32_t sectors_per_block = (1U << log2_block_size) / 512;
    uint32_t expected_blocks = sectors_total / sectors_per_block;
    ck_assert_int_eq(entry->block_count, expected_blocks);
}
END_TEST

// Test partition I/O error handling
START_TEST(test_partition_io_errors)
{
    // Test with NULL I/O context
    int result = mlfs_make_empty_partition_table(NULL);
    ck_assert_int_ne(result, 0);
    
    result = mlfs_add_partition(NULL, 1, 100, 12, "test");
    ck_assert_int_ne(result, 0);
    
    mlpt_t pt;
    result = mlfs_read_mlpt(NULL, &pt);
    ck_assert_int_ne(result, 0);
    
    // Test with NULL output parameter
    result = mlfs_read_mlpt(&test_io, NULL);
    ck_assert_int_ne(result, 0);
}
END_TEST

// Main test suite
Suite *partition_suite(void)
{
    Suite *s;
    TCase *tc_create, *tc_add, *tc_validation, *tc_errors;

    s = suite_create("Partition Operations");

    // Basic partition table creation tests
    tc_create = tcase_create("Creation");
    tcase_add_checked_fixture(tc_create, setup_partition_test, teardown_partition_test);
    tcase_add_test(tc_create, test_make_empty_partition_table);
    tcase_add_test(tc_create, test_make_single_partition);
    suite_add_tcase(s, tc_create);

    // Partition addition tests
    tc_add = tcase_create("Addition");
    tcase_add_checked_fixture(tc_add, setup_partition_test, teardown_partition_test);
    tcase_add_test(tc_add, test_add_single_partition);
    tcase_add_test(tc_add, test_add_multiple_partitions);
    suite_add_tcase(s, tc_add);

    // Validation and limits tests
    tc_validation = tcase_create("Validation");
    tcase_add_checked_fixture(tc_validation, setup_partition_test, teardown_partition_test);
    tcase_add_test(tc_validation, test_partition_overlap_detection);
    tcase_add_test(tc_validation, test_partition_table_limits);
    tcase_add_test(tc_validation, test_invalid_partition_parameters);
    suite_add_tcase(s, tc_validation);

    // Error handling tests
    tc_errors = tcase_create("Error Handling");
    tcase_add_checked_fixture(tc_errors, setup_partition_test, teardown_partition_test);
    tcase_add_test(tc_errors, test_partition_io_errors);
    suite_add_tcase(s, tc_errors);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = partition_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
