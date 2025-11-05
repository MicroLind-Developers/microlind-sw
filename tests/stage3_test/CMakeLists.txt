cmake_minimum_required(VERSION 3.16)
project(microlind-stage3-test)

# Set the output format to Intel HEX
set(FORMAT "ihex")
set(BUILD_DIR "${CMAKE_BINARY_DIR}/build")

# Define BIOS source files
set(BIOS_SRC
    ../../bios/init.asm
    ../../bios/mlbios.asm
    ../../driver/serial_xr88c92.asm
    ../../driver/mmu.asm
    ../../driver/rtc.asm
    ../../driver/ps2.asm
    ../../driver/parallel_6522.asm
    ../../driver/irq.asm
    ../../bios/memory.asm
)

# Set include directories
set(BIOS_HEADER "../../driver")

# Create build directory
file(MAKE_DIRECTORY ${BUILD_DIR})

# Custom command to build the BIOS using lwasm
add_custom_command(
    OUTPUT ${BUILD_DIR}/bios.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -I ${BIOS_HEADER} -o ${BUILD_DIR}/bios.${FORMAT} ${BIOS_SRC}
    DEPENDS ${BIOS_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building BIOS with lwasm"
    VERBATIM
)

# Custom target for the serial build
add_custom_target(serial ALL
    DEPENDS ${BUILD_DIR}/bios.${FORMAT}
    COMMENT "Building serial target"
)

# Create a default target that can be built with 'make'
add_custom_target(stage3-test ALL
    DEPENDS ${BUILD_DIR}/bios.${FORMAT}
    COMMENT "Building stage3 test"
)

# Custom target for clean
add_custom_target(clean-build
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DIR}
    COMMENT "Cleaning build directory"
)

# Set the default target
set_target_properties(serial PROPERTIES
    OUTPUT_NAME "bios"
    PREFIX ""
    SUFFIX ".${FORMAT}"
)

# Print build information
message(STATUS "Building microlind stage3 test")
message(STATUS "Output format: ${FORMAT}")
message(STATUS "Build directory: ${BUILD_DIR}")
message(STATUS "BIOS header directory: ${BIOS_HEADER}")
