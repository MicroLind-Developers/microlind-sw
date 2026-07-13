# MLFS Tests

This directory contains the test suite for the MLFS (MicroLind File System) library, implemented using the Check unit testing framework and organized with CMake's CTest integration.

## Test Organization

- **`test_common.h`** - Common test utilities, Check framework helpers, and setup/teardown functions
- **`test_basic.c`** - Basic filesystem operations (mkfs, mount, file I/O) using Check test cases
- **`test_directories.c`** - Directory operations (create, read, rename, delete directories and files) using Check test cases
- **`test_partitions.c`** - Partition table management (create, add, validate partitions) using Check test cases
- **`test_filesystem.c`** - Core filesystem operations (mkfs, mount with validation and error handling) using Check test cases

## Check Framework Features

This test suite uses the Check C unit testing framework which provides:
- **Structured test organization** with test suites and test cases
- **Setup/teardown fixtures** for consistent test environments  
- **Rich assertion library** with descriptive failure messages
- **Test result reporting** with detailed output and statistics
- **Integration with CTest** for seamless CMake integration

## Prerequisites

The MLFS test suite requires the Check C unit testing framework. See `INSTALL_CHECK.md` for installation instructions.

## Running Tests

### Build and Run All Tests
```bash
mkdir build && cd build
cmake ..
make
ctest --output-on-failure --verbose
```

### Alternative: Use the convenience target
```bash
make check
```

### Code Coverage Analysis
```bash
# Build with coverage enabled
mkdir build && cd build
cmake -DENABLE_COVERAGE=ON ..
make

# Run coverage analysis
make coverage-report

# View results
firefox coverage/html/index.html  # HTML report
make coverage-summary            # Text summary
```

See [COVERAGE.md](../COVERAGE.md) for detailed coverage analysis documentation.

### Run Individual Tests
```bash
# Run only basic tests
ctest -R BasicOperations --verbose

# Run only directory tests  
ctest -R DirectoryOperations --verbose

# Run only partition tests
ctest -R PartitionOperations --verbose

# Run only filesystem tests
ctest -R FilesystemOperations --verbose

# Run tests with specific labels
ctest -L filesystem --verbose   # Basic and directory tests
ctest -L partition --verbose     # Partition table tests
ctest -L core --verbose         # Core filesystem tests
```

### Run Test Executables Directly
```bash
./tests/test_basic
./tests/test_directories
./tests/test_partitions
./tests/test_filesystem
```

## Test Features

- **Check framework**: Professional C unit testing with structured test organization
- **RAM-based testing**: All tests use in-memory "disks" for fast, isolated testing
- **Multiple block sizes**: Basic tests run with 512B, 4KB, and 64KB block sizes
- **Test fixtures**: Automatic setup/teardown for consistent test environments
- **Rich assertions**: Check's comprehensive assertion library (ck_assert_int_eq, ck_assert_str_eq, etc.)
- **Comprehensive coverage**: Tests partition management, filesystem creation, mounting, file/directory operations, error conditions
- **Error condition testing**: Validates proper error handling
- **Detailed reporting**: Check provides detailed test results and failure information
- **CTest integration**: Full integration with CMake's testing framework

## Adding New Tests

1. Create a new test file (e.g., `test_performance.c`)
2. Include `test_common.h` for utilities and Check framework
3. Add the test to `CMakeLists.txt`:
   ```cmake
   add_executable(test_performance test_performance.c)
   target_link_libraries(test_performance PRIVATE mlfs ${CHECK_LIBRARIES})
   target_include_directories(test_performance PRIVATE ${CHECK_INCLUDE_DIRS})
   target_compile_options(test_performance PRIVATE ${CHECK_CFLAGS_OTHER})
   add_test(NAME PerformanceTests COMMAND test_performance)
   ```

## Test Structure

Each test file follows the Check framework pattern:
```c
#include "test_common.h"

START_TEST(test_specific_feature)
{
    // Test logic using Check assertions
    ck_assert_mlfs_ok(mlfs_create_empty_file(&g_test_mnt, "test.txt", 1));
    
    const char *data = "test data";
    ck_assert_int_eq(mlfs_pwrite_file(&g_test_mnt, "test.txt", data, strlen(data), 0), strlen(data));
    
    char buf[64];
    ck_assert_int_eq(mlfs_pread_file(&g_test_mnt, "test.txt", buf, sizeof(buf), 0), strlen(data));
    ck_assert_str_eq(buf, data);
}
END_TEST

Suite *performance_suite(void) {
    Suite *s = suite_create("Performance Tests");
    TCase *tc_core = tcase_create("Core");
    
    // Use fixtures for automatic setup/teardown
    tcase_add_checked_fixture(tc_core, setup_mlfs_test, teardown_mlfs_test);
    tcase_add_test(tc_core, test_specific_feature);
    suite_add_tcase(s, tc_core);
    
    return s;
}

int main(void) {
    int number_failed;
    Suite *s = performance_suite();
    SRunner *sr = srunner_create(s);
    
    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);
    
    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
```

## Check Assertion Reference

Common Check assertions used in the tests:
- `ck_assert_int_eq(a, b)` - Assert integers are equal
- `ck_assert_str_eq(a, b)` - Assert strings are equal  
- `ck_assert_ptr_ne(p, NULL)` - Assert pointer is not NULL
- `ck_assert_mlfs_ok(call)` - Assert MLFS function returns 0 (success)
- `ck_assert_mlfs_fail(call)` - Assert MLFS function returns non-zero (failure)
