/****************************** test_basic.c *********************************/
// Basic MLFS tests using Check framework: mkfs/mount, file creation, read/write operations
#include "test_common.h"

// Test fixtures are now defined in test_common.c

START_TEST(test_basic_operations_512b)
{
    // Clean up default setup and create 512-byte block filesystem
    cleanup_test_filesystem(&g_test_ramdisk);

    mlfs_ramdisk_t rd = {0};
    mlfs_io_t io = {0};
    mlfs_t fs, mnt;

    ck_assert_mlfs_ok(setup_test_filesystem(&rd, &io, &fs, 9)); // 512 bytes
    ck_assert_mlfs_ok(mlfs_mount(&io, 0, &mnt));

    // Create a file and write to it
    ck_assert_mlfs_ok(mlfs_create_empty_file(&mnt, "hello.txt", 2));
    const char *msg = "MicroLind MLFS test!";
    ck_assert_int_eq(mlfs_pwrite_file(&mnt, "hello.txt", msg, strlen(msg), 0), (ssize_t)strlen(msg));

    // Read the file back
    char buf[64] = {0};
    ck_assert_int_eq(mlfs_pread_file(&mnt, "hello.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg));
    ck_assert_str_eq(buf, msg);

    // Verify superblock reflects correct block size
    ck_assert_int_eq(mnt.sb.log2_block_size, 9);

    cleanup_test_filesystem(&rd);
}
END_TEST

START_TEST(test_basic_operations_4kb)
{
    // Use default 4KB setup

    // Create a file and write to it
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "hello.txt", 2));
    const char *msg = "MicroLind MLFS test!";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "hello.txt", msg, strlen(msg), 0), (ssize_t)strlen(msg));

    // Read the file back
    char buf[64] = {0};
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "hello.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg));
    ck_assert_str_eq(buf, msg);

    // Verify superblock reflects correct block size
    ck_assert_int_eq(g_test_mnt.sb.log2_block_size, 12);
}
END_TEST

START_TEST(test_basic_operations_64kb)
{
    // Clean up default setup and create 64KB block filesystem
    cleanup_test_filesystem(&g_test_ramdisk);

    mlfs_ramdisk_t rd = {0};
    mlfs_io_t io = {0};
    mlfs_t fs, mnt;

    ck_assert_mlfs_ok(setup_test_filesystem(&rd, &io, &fs, 16)); // 65536 bytes
    ck_assert_mlfs_ok(mlfs_mount(&io, 0, &mnt));

    // Create a file and write to it
    ck_assert_mlfs_ok(mlfs_create_empty_file(&mnt, "hello.txt", 2));
    const char *msg = "MicroLind MLFS test!";
    ck_assert_int_eq(mlfs_pwrite_file(&mnt, "hello.txt", msg, strlen(msg), 0), (ssize_t)strlen(msg));

    // Read the file back
    char buf[64] = {0};
    ck_assert_int_eq(mlfs_pread_file(&mnt, "hello.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg));
    ck_assert_str_eq(buf, msg);

    // Verify superblock reflects correct block size
    ck_assert_int_eq(mnt.sb.log2_block_size, 16);

    cleanup_test_filesystem(&rd);
}
END_TEST

START_TEST(test_multiple_files)
{
    // Create multiple files
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file1.txt", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file2.txt", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file3.txt", 2));

    // Write different content to each file
    const char *msg1 = "Content of file 1";
    const char *msg2 = "This is file number 2";
    const char *msg3 = "File 3 has longer content that spans multiple lines\nand includes newlines for testing.";

    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "file1.txt", msg1, strlen(msg1), 0), (ssize_t)strlen(msg1));
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "file2.txt", msg2, strlen(msg2), 0), (ssize_t)strlen(msg2));
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "file3.txt", msg3, strlen(msg3), 0), (ssize_t)strlen(msg3));

    // Read back and verify each file
    char buf[256];

    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "file1.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg1));
    ck_assert_str_eq(buf, msg1);

    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "file2.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg2));
    ck_assert_str_eq(buf, msg2);

    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "file3.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(msg3));
    ck_assert_str_eq(buf, msg3);
}
END_TEST

START_TEST(test_partial_io)
{
    // Create a file and write initial content
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "partial.txt", 2));
    const char *initial = "Hello World!";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "partial.txt", initial, strlen(initial), 0), (ssize_t)strlen(initial));

    // Test 1: Overwrite part of the content (middle portion)
    const char *replacement = "MLFS";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "partial.txt", replacement, strlen(replacement), 6), (ssize_t)strlen(replacement));

    // Read back and verify - should be "Hello MLFSd!" (original "World!" becomes "MLFSd!")
    char buf[64] = {0};
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "partial.txt", buf, sizeof(buf) - 1, 0), 12);
    ck_assert_str_eq(buf, "Hello MLFSd!");

    // Test 2: Overwrite with longer replacement 
    const char *replacement2 = "MLFS!"; // 5 characters to replace "World"
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "partial.txt", replacement2, strlen(replacement2), 6), (ssize_t)strlen(replacement2));

    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "partial.txt", buf, sizeof(buf) - 1, 0), 12);
    ck_assert_str_eq(buf, "Hello MLFS!!"); // Note: two exclamation marks!

    // Test 3: Partial reads
    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "partial.txt", buf, 5, 0), 5);
    buf[5] = '\0';
    ck_assert_str_eq(buf, "Hello");

    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "partial.txt", buf, 5, 6), 5);
    buf[5] = '\0';
    ck_assert_str_eq(buf, "MLFS!");

    // Test 4: Read past end of file
    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "partial.txt", buf, 20, 5), 7); // Should read 7 bytes (from pos 5 to end of 12-byte file)

    // Test 5: Create a new file with exact expected content (for completeness)
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "clean.txt", 1));
    const char *clean_content = "Hello MLFS!";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "clean.txt", clean_content, strlen(clean_content), 0), (ssize_t)strlen(clean_content));
    
    memset(buf, 0, sizeof(buf));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "clean.txt", buf, sizeof(buf) - 1, 0), 11);
    ck_assert_str_eq(buf, "Hello MLFS!");
}
END_TEST

START_TEST(test_file_errors)
{
    // Test reading non-existent file
    char buf[64];
    ck_assert_int_lt(mlfs_pread_file(&g_test_mnt, "nonexistent.txt", buf, sizeof(buf), 0), 0);

    // Test writing to non-existent file
    const char *data = "test";
    ck_assert_int_lt(mlfs_pwrite_file(&g_test_mnt, "nonexistent.txt", data, strlen(data), 0), 0);
}
END_TEST

Suite *basic_suite(void)
{
    Suite *s;
    TCase *tc_core;
    TCase *tc_blocksizes;

    s = suite_create("Basic MLFS Operations");

    // Core test case with setup/teardown
    tc_core = tcase_create("Core");
    tcase_add_checked_fixture(tc_core, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_core, test_basic_operations_4kb);
    tcase_add_test(tc_core, test_multiple_files);
    tcase_add_test(tc_core, test_partial_io);
    tcase_add_test(tc_core, test_file_errors);
    suite_add_tcase(s, tc_core);

    // Block size tests (no setup/teardown since they manage their own filesystems)
    tc_blocksizes = tcase_create("BlockSizes");
    tcase_add_test(tc_blocksizes, test_basic_operations_512b);
    tcase_add_test(tc_blocksizes, test_basic_operations_64kb);
    suite_add_tcase(s, tc_blocksizes);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = basic_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}