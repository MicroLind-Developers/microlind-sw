cmake_minimum_required(VERSION 3.16)
project(c-test)

# Include the cmoc build macro
include(${CMAKE_SOURCE_DIR}/../../cmake/cmoc.cmake)

# Build the C test project using the macro
build_cmoc_project(
    c-test
    "src/main.c"
    "test"
    ORIGIN "0xEF00"
    DATA "0xC000"
    STACK "0x1000"
    STACK_SIZE "1024"
    INCLUDE_DIR "../../include"
    FORMAT "srec"
    INTERMEDIATE
)
