cmake_minimum_required(VERSION 3.16)
project(microlind-stage2-blink)

# Set the output format to Intel HEX
set(FORMAT "ihex")
set(BUILD_DIR "${CMAKE_BINARY_DIR}/build")

# Define source files
set(BLINK_SRC "blink.asm")

# Create build directory
file(MAKE_DIRECTORY ${BUILD_DIR})

# Custom command to build the blink test using lwasm
add_custom_command(
    OUTPUT ${BUILD_DIR}/blink.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -o ${BUILD_DIR}/blink.${FORMAT} ${BLINK_SRC}
    DEPENDS ${BLINK_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building blink test with lwasm"
    VERBATIM
)

# Custom target for the blink build
add_custom_target(blink ALL
    DEPENDS ${BUILD_DIR}/blink.${FORMAT}
    COMMENT "Building blink test"
)

# Create a default target that can be built with 'make'
add_custom_target(blink-test ALL
    DEPENDS ${BUILD_DIR}/blink.${FORMAT}
    COMMENT "Building blink test"
)

# Custom target for clean
add_custom_target(clean-build
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DIR}
    COMMENT "Cleaning build directory"
)

# Print build information
message(STATUS "Building microlind stage2 blink test")
message(STATUS "Output format: ${FORMAT}")
message(STATUS "Build directory: ${BUILD_DIR}")
