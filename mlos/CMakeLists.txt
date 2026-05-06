cmake_minimum_required(VERSION 3.16)
project(mlos)

set(FORMAT "ihex")
set(BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")

set(MLOS_SRC
    src/kernel.asm
    src/memory_manager.asm
    src/syscall_dispatch.asm
    src/syscall_c_shim.asm
)

add_custom_command(
    OUTPUT ${BUILD_DIR}/mlos.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -Iinclude -o ${BUILD_DIR}/mlos.${FORMAT} ${MLOS_SRC}
    DEPENDS ${MLOS_SRC} include/mlos.inc include/syscall.inc
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building MLOS skeleton"
    VERBATIM
)

add_custom_target(mlos-build ALL
    DEPENDS ${BUILD_DIR}/mlos.${FORMAT}
)
