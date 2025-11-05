# CMakeLists.txt for MLFS tests using Check framework
cmake_minimum_required(VERSION 3.16)

# Enable testing
enable_testing()

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the main project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Find Check framework
find_package(PkgConfig REQUIRED)
pkg_check_modules(CHECK check)

if(NOT CHECK_FOUND)
    message(WARNING "Check framework not found. Please install libcheck-dev or check-devel package.")
    message(STATUS "On Ubuntu/Debian: sudo apt-get install libcheck-dev")
    message(STATUS "On RHEL/CentOS: sudo yum install check-devel")
    message(STATUS "On macOS: brew install check")
    message(FATAL_ERROR "Check framework is required for testing")
endif()

# Add include directory for test_common.h
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Create test common library
add_library(test_common STATIC test_common.c test_common.h)
target_link_libraries(test_common PRIVATE mlfs ${CHECK_LIBRARIES})
target_include_directories(test_common PRIVATE ${CHECK_INCLUDE_DIRS})
target_compile_options(test_common PRIVATE ${CHECK_CFLAGS_OTHER})

# Create test executables
add_executable(test_basic test_basic.c)
add_executable(test_directories test_directories.c)
add_executable(test_partitions test_partitions.c)
add_executable(test_filesystem test_filesystem.c)

# Link test executables with the mlfs library, test_common, and Check
target_link_libraries(test_basic PRIVATE mlfs test_common ${CHECK_LIBRARIES})
target_link_libraries(test_directories PRIVATE mlfs test_common ${CHECK_LIBRARIES})
target_link_libraries(test_partitions PRIVATE mlfs test_common ${CHECK_LIBRARIES})
target_link_libraries(test_filesystem PRIVATE mlfs test_common ${CHECK_LIBRARIES})

# Add Check include directories and compile flags
target_include_directories(test_basic PRIVATE ${CHECK_INCLUDE_DIRS})
target_include_directories(test_directories PRIVATE ${CHECK_INCLUDE_DIRS})
target_include_directories(test_partitions PRIVATE ${CHECK_INCLUDE_DIRS})
target_include_directories(test_filesystem PRIVATE ${CHECK_INCLUDE_DIRS})
target_compile_options(test_basic PRIVATE ${CHECK_CFLAGS_OTHER})
target_compile_options(test_directories PRIVATE ${CHECK_CFLAGS_OTHER})
target_compile_options(test_partitions PRIVATE ${CHECK_CFLAGS_OTHER})
target_compile_options(test_filesystem PRIVATE ${CHECK_CFLAGS_OTHER})

# Add tests to CTest
add_test(NAME BasicOperations COMMAND test_basic)
add_test(NAME DirectoryOperations COMMAND test_directories)
add_test(NAME PartitionOperations COMMAND test_partitions)
add_test(NAME FilesystemOperations COMMAND test_filesystem)

# Set test properties
set_tests_properties(BasicOperations PROPERTIES
    TIMEOUT 30
    LABELS "unit;filesystem"
)

set_tests_properties(DirectoryOperations PROPERTIES  
    TIMEOUT 30
    LABELS "unit;filesystem;directories"
)

set_tests_properties(PartitionOperations PROPERTIES
    TIMEOUT 30
    LABELS "unit;partition;low-level"
)

set_tests_properties(FilesystemOperations PROPERTIES
    TIMEOUT 30
    LABELS "unit;filesystem;core"
)

# Add a combined test target for convenience
add_custom_target(run_all_tests
    COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure --verbose
    DEPENDS test_basic test_directories test_partitions test_filesystem
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Running all MLFS tests"
)

# Install test executables (optional)
install(TARGETS test_basic test_directories test_partitions test_filesystem test_common
    RUNTIME DESTINATION bin/tests
    ARCHIVE DESTINATION lib/tests
    OPTIONAL
)
