cmake_minimum_required(VERSION 3.16)

# Set project name and language
project(mlfs LANGUAGES C)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the original Makefile
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Set default build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "RelWithDebInfo" "MinSizeRel")
endif()

# Code coverage option
option(ENABLE_COVERAGE "Enable code coverage analysis" OFF)

# Configure code coverage if enabled
if(ENABLE_COVERAGE)
    # Check for GCC or Clang
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        message(STATUS "Code coverage enabled")
        
        # Add coverage compiler flags
        set(COVERAGE_FLAGS "-fprofile-arcs -ftest-coverage --coverage")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${COVERAGE_FLAGS}")
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${COVERAGE_FLAGS}")
        
        # Force Debug build type for better coverage analysis
        if(NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
            message(STATUS "Forcing Debug build type for coverage analysis")
            set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Build type" FORCE)
        endif()
        
        # Find required tools
        find_program(GCOV_PATH gcov)
        find_program(LCOV_PATH lcov)
        find_program(GENHTML_PATH genhtml)
        
        if(NOT GCOV_PATH)
            message(WARNING "gcov not found! Coverage reports may not work.")
        endif()
        
        if(NOT LCOV_PATH)
            message(WARNING "lcov not found! Install with: sudo apt-get install lcov")
        endif()
        
        if(NOT GENHTML_PATH)
            message(WARNING "genhtml not found! Install with: sudo apt-get install lcov")
        endif()
        
    else()
        message(FATAL_ERROR "Code coverage requires GCC or Clang compiler")
    endif()
endif()

# Add library subdirectory (contains lib/src/ and lib/include/)
add_subdirectory(lib)

# Enable testing support
enable_testing()

# Add tests subdirectory
add_subdirectory(tests)

# Add tools subdirectory
add_subdirectory(tools)

# Add convenience target for running all tests
add_custom_target(mlfs-check
    COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure --verbose
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Running all MLFS tests"
    DEPENDS test_basic test_directories test_partitions test_filesystem
)

# Coverage targets (only available when coverage is enabled)
if(ENABLE_COVERAGE AND LCOV_PATH AND GENHTML_PATH)
    
    # Coverage output directory
    set(COVERAGE_OUTPUT_DIR ${CMAKE_BINARY_DIR}/coverage)
    set(COVERAGE_INFO_FILE ${COVERAGE_OUTPUT_DIR}/coverage.info)
    set(COVERAGE_CLEANED_FILE ${COVERAGE_OUTPUT_DIR}/coverage_cleaned.info)
    
    # Create coverage output directory
    file(MAKE_DIRECTORY ${COVERAGE_OUTPUT_DIR})
    
    # Coverage target: clean old data, run tests, collect coverage
    add_custom_target(coverage
        COMMAND ${CMAKE_COMMAND} -E echo "Cleaning old coverage data..."
        COMMAND ${LCOV_PATH} --directory ${CMAKE_BINARY_DIR} --zerocounters || true
        
        COMMAND ${CMAKE_COMMAND} -E echo "Running tests for coverage..."
        COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure
        
        COMMAND ${CMAKE_COMMAND} -E echo "Collecting coverage data..."
        COMMAND ${LCOV_PATH} --directory ${CMAKE_BINARY_DIR} --capture --output-file ${COVERAGE_INFO_FILE} --rc geninfo_unexecuted_blocks=1 --ignore-errors gcov,source,graph
        
        COMMAND ${CMAKE_COMMAND} -E echo "Filtering coverage data..."
        COMMAND ${LCOV_PATH} --remove ${COVERAGE_INFO_FILE} 
            '*/tests/*' 
            '*/cli/*' 
            '*/tools/*'
            '*/build/*'
            '/usr/include/*'
            '/usr/lib/*'
            --ignore-errors unused,source
            --output-file ${COVERAGE_CLEANED_FILE}
        
        COMMAND ${CMAKE_COMMAND} -E echo "Coverage data collected in ${COVERAGE_CLEANED_FILE}"
        COMMAND ${LCOV_PATH} --list ${COVERAGE_CLEANED_FILE} || true
        
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        DEPENDS mlfs-check
        COMMENT "Generating code coverage report"
    )
    
    # HTML coverage report target
    add_custom_target(coverage-html
        COMMAND ${CMAKE_COMMAND} -E echo "Generating HTML coverage report..."
        COMMAND ${GENHTML_PATH} 
            ${COVERAGE_CLEANED_FILE} 
            --output-directory ${COVERAGE_OUTPUT_DIR}/html
            --title "MLFS Code Coverage"
            --show-details
            --legend
            --demangle-cpp
            --ignore-errors source
        
        COMMAND ${CMAKE_COMMAND} -E echo "HTML coverage report generated in ${COVERAGE_OUTPUT_DIR}/html/index.html"
        COMMAND ${CMAKE_COMMAND} -E echo "Open with: firefox ${COVERAGE_OUTPUT_DIR}/html/index.html"
        
        DEPENDS coverage
        COMMENT "Generating HTML coverage report"
    )
    
    # Coverage summary target (text report)
    add_custom_target(coverage-summary
        COMMAND ${CMAKE_COMMAND} -E echo "Coverage Summary:"
        COMMAND ${LCOV_PATH} --summary ${COVERAGE_CLEANED_FILE}
        
        DEPENDS coverage
        COMMENT "Displaying coverage summary"
    )
    
    # Clean coverage data target
    add_custom_target(coverage-clean
        COMMAND ${CMAKE_COMMAND} -E echo "Cleaning coverage data..."
        COMMAND ${LCOV_PATH} --directory ${CMAKE_BINARY_DIR} --zerocounters
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${COVERAGE_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${COVERAGE_OUTPUT_DIR}
        
        COMMENT "Cleaning coverage data"
    )
    
    # Combined target for full coverage analysis
    add_custom_target(coverage-report
        DEPENDS coverage-html coverage-summary
        COMMENT "Complete coverage analysis with HTML report and summary"
    )
    
    message(STATUS "Coverage targets available:")
    message(STATUS "  coverage         - Run tests and collect coverage data")
    message(STATUS "  coverage-html    - Generate HTML coverage report")
    message(STATUS "  coverage-summary - Display coverage summary")
    message(STATUS "  coverage-report  - Generate both HTML report and summary")
    message(STATUS "  coverage-clean   - Clean coverage data")
    message(STATUS "")
    message(STATUS "Quick start: ./run_coverage.sh")
    message(STATUS "Documentation: COVERAGE.md, examples/coverage_example.md")
    
endif()

# Library install targets are handled in lib/CMakeLists.txt

# Register clean target with global property (following project pattern)
set_property(GLOBAL APPEND PROPERTY MICROLIND_CLEAN_TARGETS mlfs-clean)
add_custom_target(mlfs-clean
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target clean
    COMMENT "Cleaning mlfs targets"
)
