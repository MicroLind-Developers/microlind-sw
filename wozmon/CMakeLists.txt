cmake_minimum_required(VERSION 3.16)
project(microlind-wozmon)

# Set the output format to Intel HEX
set(FORMAT "ihex")
set(BUILD_DIR "${CMAKE_BINARY_DIR}/build")

# Define BIOS source files
set(BIOS_SRC
    ../driver/init.asm
    ../driver/serial_xr88c92.asm
    ../driver/parallel_6522.asm
    ../driver/mmu.asm
    ../driver/led.asm
    wozmon6309.asm
)

# Create build directory
file(MAKE_DIRECTORY ${BUILD_DIR})

# Custom command to build the wozmon BIOS using lwasm
add_custom_command(
    OUTPUT ${BUILD_DIR}/bios.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -o ${BUILD_DIR}/bios.${FORMAT} ${BIOS_SRC}
    DEPENDS ${BIOS_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building wozmon BIOS with lwasm"
    VERBATIM
)

# Custom target for the bios build
add_custom_target(bios ALL
    DEPENDS ${BUILD_DIR}/bios.${FORMAT}
    COMMENT "Building wozmon BIOS"
)

# Create a default target that can be built with 'make'
add_custom_target(wozmon-build ALL
    DEPENDS ${BUILD_DIR}/bios.${FORMAT}
    COMMENT "Building wozmon"
)

# Custom target for clean
add_custom_target(clean-build
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DIR}
    COMMENT "Cleaning build directory"
)

# Print build information
message(STATUS "Building microlind wozmon")
message(STATUS "Output format: ${FORMAT}")
message(STATUS "Build directory: ${BUILD_DIR}")
