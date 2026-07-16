cmake_minimum_required(VERSION 3.16)
project(bios NONE)

set(FORMAT "ihex" CACHE STRING "BIOS output format passed to lwasm")
set(BIOS_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/bios.${FORMAT}")

set(BIOS_SOURCES
    src/mlbios.asm
    src/config.asm
    src/mlfs.asm
    driver/compactflash.asm
    driver/serial_xr88c92.asm
    driver/mmu.asm
    driver/parallel_6522.asm
    driver/irq.asm
    src/memory.asm
    src/init.asm
)

set(BIOS_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/driver"
)

set(BIOS_INCLUDE_ARGS)
foreach(dir IN LISTS BIOS_INCLUDE_DIRS)
    list(APPEND BIOS_INCLUDE_ARGS -I "${dir}")
endforeach()
string(JOIN " " BIOS_INCLUDE_ARGS_DISPLAY ${BIOS_INCLUDE_ARGS})
string(JOIN " " BIOS_SOURCES_DISPLAY ${BIOS_SOURCES})

add_custom_command(
    OUTPUT "${BIOS_OUTPUT}"
    COMMAND ${CMAKE_COMMAND} -E echo "Running: lwasm -3 -f ${FORMAT} ${BIOS_INCLUDE_ARGS_DISPLAY} -o ${BIOS_OUTPUT} ${BIOS_SOURCES_DISPLAY}"
    COMMAND lwasm -3 -f "${FORMAT}" ${BIOS_INCLUDE_ARGS} -o "${BIOS_OUTPUT}" ${BIOS_SOURCES}
    DEPENDS ${BIOS_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building BIOS with lwasm"
    VERBATIM
)

add_custom_target(bios ALL
    DEPENDS "${BIOS_OUTPUT}"
    COMMENT "Building BIOS"
)

add_custom_target(bios-build
    DEPENDS "${BIOS_OUTPUT}"
    COMMENT "Building BIOS"
)

add_custom_target(bios-clean
    COMMAND ${CMAKE_COMMAND} -E remove -f "${BIOS_OUTPUT}"
    COMMENT "Cleaning BIOS build artifacts"
)

message(STATUS "Building bios")
message(STATUS "  Sources: ${BIOS_SOURCES}")
message(STATUS "  Output: ${BIOS_OUTPUT}")
message(STATUS "  Format: ${FORMAT}")
message(STATUS "  Build directory: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "  Include directories: ${BIOS_INCLUDE_DIRS}")
