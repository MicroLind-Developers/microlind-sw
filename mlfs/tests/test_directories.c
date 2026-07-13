/****************************** test_directories.c **************************/
// MLFS directory operation tests using Check framework: create, read, delete directories and files
#include "test_common.h"
#include <stdbool.h>

START_TEST(test_directory_creation)
{
    // Test directory creation
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "documents", 1));
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "images", 1));
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "projects", 2));

    // Test reading root directory
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 3);

    // Verify all entries are directories
    for(uint32_t i = 0; i < count; i++) {
        ck_assert_int_eq(entries[i].flags & 1, 1); // bit0=dir
    }
}
END_TEST

START_TEST(test_mixed_entries)
{
    // Create mixed content
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "testdir", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "readme.txt", 1));
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "emptydir", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "config.ini", 1));

    // Test reading root directory
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 4);

    // Count directories and files
    uint32_t dirs = 0, files = 0;
    for(uint32_t i = 0; i < count; i++) {
        if(entries[i].flags & 1)
            dirs++;
        else
            files++;
    }

    ck_assert_int_eq(dirs, 2);  // testdir, emptydir
    ck_assert_int_eq(files, 2); // readme.txt, config.ini

    // Test reading empty directory
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "emptydir", entries, 10, &count));
    ck_assert_int_eq(count, 0);
}
END_TEST

START_TEST(test_file_deletion)
{
    // Create some files
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file1.txt", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file2.txt", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "temp.dat", 1));

    // Write content to files to make sure they're actually allocated
    const char *content = "Test content";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "file1.txt", content, strlen(content), 0), (ssize_t)strlen(content));
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "temp.dat", content, strlen(content), 0), (ssize_t)strlen(content));

    // Verify files exist
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 3);

    // Delete one file
    ck_assert_mlfs_ok(mlfs_delete_file(&g_test_mnt, "temp.dat"));

    // Verify deletion
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 2);

    // Ensure temp.dat is not in the list
    for(uint32_t i = 0; i < count; i++) {
        ck_assert_str_ne(entries[i].name, "temp.dat");
    }

    // Verify remaining files are still accessible
    char buf[64];
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "file1.txt", buf, sizeof(buf) - 1, 0), (ssize_t)strlen(content));

    // Try to access deleted file (should fail)
    ck_assert_int_lt(mlfs_pread_file(&g_test_mnt, "temp.dat", buf, sizeof(buf) - 1, 0), 0);
}
END_TEST

START_TEST(test_directory_deletion)
{
    // Create directories
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "emptydir", 1));
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "keepdir", 1));

    // Verify directories exist
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 2);

    // Delete empty directory
    ck_assert_mlfs_ok(mlfs_delete_directory(&g_test_mnt, "emptydir"));

    // Verify deletion
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 1);

    // Ensure only keepdir remains
    ck_assert_str_eq(entries[0].name, "keepdir");

    // Try to read deleted directory (should fail)
    ck_assert_mlfs_fail(mlfs_read_directory(&g_test_mnt, "emptydir", entries, 10, &count));
}
END_TEST

START_TEST(test_file_rename)
{
    const char *content = "rename keeps file data";
    char buffer[64] = {0};

    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "old.txt", 1));
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "old.txt", content, strlen(content), 0), (ssize_t)strlen(content));

    ck_assert_mlfs_ok(mlfs_rename(&g_test_mnt, "old.txt", "new.txt"));
    ck_assert_mlfs_fail(mlfs_pread_file(&g_test_mnt, "old.txt", buffer, sizeof(buffer) - 1, 0));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "new.txt", buffer, sizeof(buffer) - 1, 0), (ssize_t)strlen(content));
    ck_assert_str_eq(buffer, content);
}
END_TEST

START_TEST(test_directory_rename_and_move)
{
    const char *content = "nested file survives directory move";
    char buffer[64] = {0};

    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "docs", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "docs/readme.txt", 1));
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "docs/readme.txt", content, strlen(content), 0), (ssize_t)strlen(content));

    ck_assert_mlfs_ok(mlfs_rename(&g_test_mnt, "docs", "manuals"));
    ck_assert_mlfs_fail(mlfs_read_directory(&g_test_mnt, "docs", (mlfs_dentry_t[4]){}, 4, &(uint32_t){0}));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "manuals/readme.txt", buffer, sizeof(buffer) - 1, 0), (ssize_t)strlen(content));
    ck_assert_str_eq(buffer, content);

    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "archive", 1));
    ck_assert_mlfs_ok(mlfs_rename(&g_test_mnt, "manuals/readme.txt", "archive/readme.txt"));
    memset(buffer, 0, sizeof(buffer));
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "archive/readme.txt", buffer, sizeof(buffer) - 1, 0), (ssize_t)strlen(content));
    ck_assert_str_eq(buffer, content);
}
END_TEST

START_TEST(test_error_conditions)
{
    // Test operations on non-existent entries
    ck_assert_mlfs_fail(mlfs_delete_file(&g_test_mnt, "nonexistent.txt"));
    ck_assert_mlfs_fail(mlfs_delete_directory(&g_test_mnt, "nosuchdir"));

    // Create test entries for type mismatch tests
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "testdir", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "testfile.txt", 1));

    // Try to delete file as directory and vice versa
    ck_assert_mlfs_fail(mlfs_delete_directory(&g_test_mnt, "testfile.txt")); // Should fail - it's a file
    ck_assert_mlfs_fail(mlfs_delete_file(&g_test_mnt, "testdir"));           // Should fail - it's a directory

    // Test creating files/directories in non-existent parent directories
    ck_assert_int_eq(mlfs_create_directory(&g_test_mnt, "path/with/slashes", 1), -2); // Parent "path" doesn't exist
    ck_assert_int_eq(mlfs_create_empty_file(&g_test_mnt, "path/file.txt", 1), -2);     // Parent "path" doesn't exist
    
    // But subdirectories should work when parent exists
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "parent", 1));                // Create parent
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "parent/subdir", 1));         // Should work now
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "parent/file.txt", 1));      // Should work now
}
END_TEST

START_TEST(test_directory_contents_validation)
{
    // Create test structure
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "testdir", 1));
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "file.txt", 1));

    // Read directory and validate entry properties
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_eq(count, 2);

    // Find and validate each entry
    mlfs_dentry_t *dir_entry = NULL, *file_entry = NULL;
    for(uint32_t i = 0; i < count; i++) {
        if(strcmp(entries[i].name, "testdir") == 0) {
            dir_entry = &entries[i];
        } else if(strcmp(entries[i].name, "file.txt") == 0) {
            file_entry = &entries[i];
        }
    }

    // Validate directory entry
    ck_assert_ptr_ne(dir_entry, NULL);
    ck_assert_int_eq(dir_entry->in_use, 1);
    ck_assert_int_eq(dir_entry->flags & 1, 1); // Directory flag
    ck_assert_int_eq(dir_entry->extents_used, 1);

    // Validate file entry
    ck_assert_ptr_ne(file_entry, NULL);
    ck_assert_int_eq(file_entry->in_use, 1);
    ck_assert_int_eq(file_entry->flags & 2, 2); // File flag
    ck_assert_int_eq(file_entry->extents_used, 1);
}
END_TEST

START_TEST(test_directory_overflow)
{
    // Test behavior when directory gets full
    // Create many files to test directory capacity
    char filename[32];
    const uint32_t max_files = 50; // Should be enough to test limits

    uint32_t created = 0;
    for(uint32_t i = 0; i < max_files; i++) {
        snprintf(filename, sizeof(filename), "file_%03u.txt", i);
        int result = mlfs_create_empty_file(&g_test_mnt, filename, 1);
        if(result == 0) {
            created++;
        } else {
            // Directory full or other error
            break;
        }
    }

    // Should have created at least a reasonable number of files
    ck_assert_int_ge(created, 10);

    // Verify we can read the directory
    mlfs_dentry_t entries[100];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 100, &count));
    ck_assert_int_eq(count, created);
}
END_TEST

// Test edge case file operations that should hit the num_components == 0 branch in mlfs_resolve_path
START_TEST(test_root_directory_access)  
{
    // Test 1: Try to write to an empty path (should trigger mlfs_resolve_path with empty string)
    // This should hit the num_components == 0 branch since mlfs_pwrite_file calls mlfs_resolve_path
    const char *data = "test data";
    ssize_t result = mlfs_pwrite_file(&g_test_mnt, "", data, strlen(data), 0);
    // This should fail (you can't write to root as a file), but it should trigger the path resolution
    ck_assert_int_eq(result, -5); // Invalid filename (empty)
    
    // Test 2: Try to read from an empty path 
    char buffer[100];
    result = mlfs_pread_file(&g_test_mnt, "", buffer, sizeof(buffer), 0);
    ck_assert_int_eq(result, -5); // Invalid filename (empty)
    
    // Test 3: Try to create a file with "/" path (should also trigger the branch)
    result = mlfs_create_empty_file(&g_test_mnt, "/", 1);
    ck_assert_int_ne(result, 0); // Should fail, but path resolution should happen
    
    // Test 4: Try to delete a file with empty path
    result = mlfs_delete_file(&g_test_mnt, "");
    ck_assert_int_eq(result, -5); // Invalid filename (empty)
    
    // Also test normal root directory reading (this works via special case)
    mlfs_dentry_t entries[10];
    uint32_t count;
    ck_assert_mlfs_ok(mlfs_create_directory(&g_test_mnt, "rootdir", 1));
    ck_assert_mlfs_ok(mlfs_read_directory(&g_test_mnt, "/", entries, 10, &count));
    ck_assert_int_ge(count, 1); // Should have at least one directory
}
END_TEST

Suite *directory_suite(void)
{
    Suite *s;
    TCase *tc_creation;
    TCase *tc_deletion;
    TCase *tc_rename;
    TCase *tc_errors;
    TCase *tc_advanced;

    s = suite_create("Directory Operations");

    // Directory creation and listing tests
    tc_creation = tcase_create("Creation");
    tcase_add_checked_fixture(tc_creation, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_creation, test_directory_creation);
    tcase_add_test(tc_creation, test_mixed_entries);
    tcase_add_test(tc_creation, test_directory_contents_validation);
    tcase_add_test(tc_creation, test_root_directory_access);
    suite_add_tcase(s, tc_creation);

    // Deletion tests
    tc_deletion = tcase_create("Deletion");
    tcase_add_checked_fixture(tc_deletion, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_deletion, test_file_deletion);
    tcase_add_test(tc_deletion, test_directory_deletion);
    suite_add_tcase(s, tc_deletion);

    // Rename tests
    tc_rename = tcase_create("Rename");
    tcase_add_checked_fixture(tc_rename, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_rename, test_file_rename);
    tcase_add_test(tc_rename, test_directory_rename_and_move);
    suite_add_tcase(s, tc_rename);

    // Error condition tests
    tc_errors = tcase_create("Errors");
    tcase_add_checked_fixture(tc_errors, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_errors, test_error_conditions);
    suite_add_tcase(s, tc_errors);

    // Advanced/stress tests
    tc_advanced = tcase_create("Advanced");
    tcase_add_checked_fixture(tc_advanced, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_advanced, test_directory_overflow);
    suite_add_tcase(s, tc_advanced);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = directory_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
