cmake_minimum_required(VERSION 3.16)
project(bios)

# Include the cmoc build macro
include(${CMAKE_SOURCE_DIR}/../cmake/cmoc.cmake)

set(SRCS_FILES
    "src/init.asm"
    "src/config.asm"
    "src/bios_vectors.asm"
    "src/mlfs.asm"
    "driver/compactflash.asm"
    "driver/serial_xr88c92.asm"
    "driver/mmu.asm"
    "driver/parallel_6522.asm"
    "driver/irq.asm"
    "driver/bios_c_shim.asm"
)

# Build the C test project using the macro
build_cmoc_project(
    ${PROJECT_NAME}
    ${SRCS_FILES}
    "libbios"
    STACK "0xC000"
    STACK_SIZE "1024"
    INCLUDE_DIR "${CMAKE_SOURCE_DIR}/driver/" "${CMAKE_SOURCE_DIR}/include/"
    INTERMEDIATE
)
