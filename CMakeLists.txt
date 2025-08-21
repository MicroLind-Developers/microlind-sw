cmake_minimum_required(VERSION 3.16)
project(microlind-sw)

# Enable verbose output to show all compile commands
set(CMAKE_VERBOSE_MAKEFILE ON)

# Generate compile_commands.json for IDE integration
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Set the output format to Intel HEX
set(FORMAT "ihex")
set(BUILD_DIR "${CMAKE_BINARY_DIR}/build")

# Create build directory
file(MAKE_DIRECTORY ${BUILD_DIR})

# Define source files for different tests
set(DRIVER_SRC "driver/serial_6552.asm")

set(IRQ_SRC
    ${DRIVER_SRC}
    tests/stage1_proto_testing/irq_proto_test.asm
    driver/irq.asm
)

set(PARALLEL_SRC
    ${DRIVER_SRC}
    driver/parallel_6522.asm
    tests/stage1_proto_testing/parallel_proto_test.asm
)

set(PS2_SRC
    ${DRIVER_SRC}
    tests/stage1_proto_testing/ps2_proto_test.asm
    driver/ps2.asm
)

# Custom commands for building the prototype tests
add_custom_command(
    OUTPUT ${BUILD_DIR}/irq_test.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -o ${BUILD_DIR}/irq_test.${FORMAT} ${IRQ_SRC}
    DEPENDS ${IRQ_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building IRQ prototype test"
    VERBATIM
)

add_custom_command(
    OUTPUT ${BUILD_DIR}/parallel_test.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -o ${BUILD_DIR}/parallel_test.${FORMAT} ${PARALLEL_SRC}
    DEPENDS ${PARALLEL_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building parallel prototype test"
    VERBATIM
)

add_custom_command(
    OUTPUT ${BUILD_DIR}/ps2_test.${FORMAT}
    COMMAND lwasm -3 -f ${FORMAT} -o ${BUILD_DIR}/ps2_test.${FORMAT} ${PS2_SRC}
    DEPENDS ${PS2_SRC}
    WORKING_DIRECTORY ${BUILD_DIR}
    COMMENT "Building PS2 prototype test"
    VERBATIM
)

# Custom targets for the prototype tests
add_custom_target(irq_proto_test ALL
    DEPENDS ${BUILD_DIR}/irq_test.${FORMAT}
    COMMENT "Building IRQ prototype test"
)

add_custom_target(parallel_proto_test ALL
    DEPENDS ${BUILD_DIR}/parallel_test.${FORMAT}
    COMMENT "Building parallel prototype test"
)

add_custom_target(ps2_proto_test ALL
    DEPENDS ${BUILD_DIR}/ps2_test.${FORMAT}
    COMMENT "Building PS2 prototype test"
)

# Add subdirectories for other test stages
add_subdirectory(tests/stage2_blink)
add_subdirectory(tests/stage2_echo_led_test)
add_subdirectory(tests/stage2_interrupt)
add_subdirectory(tests/stage2_irq_firq_timer_test)
add_subdirectory(tests/stage2_mem_dump)
add_subdirectory(tests/stage2_parallell)
add_subdirectory(tests/stage2_serial)
add_subdirectory(tests/stage2_banking)
add_subdirectory(tests/stage3_test)
add_subdirectory(tests/start_s2)
add_subdirectory(tests/c-test)
add_subdirectory(bios)
add_subdirectory(driver)
add_subdirectory(wozmon)
add_subdirectory(srec)

# Create a default target that will be built when running 'make'
add_custom_target(all-targets ALL
    DEPENDS 
        irq_proto_test
        parallel_proto_test
        ps2_proto_test
        blink-test
        stage3-test
        c-test
        bios-build
        wozmon-build
    COMMENT "Building all microlind targets"
)

# Custom target for clean
add_custom_target(clean-build
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUILD_DIR}
    COMMENT "Cleaning build directory"
)

# Create a global clean target that depends on all project clean targets
get_property(CLEAN_TARGETS GLOBAL PROPERTY MICROLIND_CLEAN_TARGETS)
if(CLEAN_TARGETS)
    add_custom_target(microlind-clean
        DEPENDS ${CLEAN_TARGETS}
        COMMENT "Cleaning all microlind projects"
    )
    # Make the global clean target depend on our microlind-clean
    add_dependencies(clean-build microlind-clean)
endif()

# Print build information
message(STATUS "Building microlind software")
message(STATUS "Output format: ${FORMAT}")
message(STATUS "Build directory: ${BUILD_DIR}")
