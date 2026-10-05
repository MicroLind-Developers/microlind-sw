cmake_minimum_required(VERSION 3.16)
project(bios NONE)

find_program(LWASM_EXECUTABLE lwasm)
if(NOT LWASM_EXECUTABLE)
    message(FATAL_ERROR "lwasm is required to assemble the BIOS")
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(FORMAT "ihex" CACHE STRING "BIOS output format passed to lwasm")
set(BIOS_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/bios.${FORMAT}")
set(BIOS_CHECK_IMAGE "${CMAKE_CURRENT_BINARY_DIR}/bios.ihex")
set(BIOS_SYMBOLS "${CMAKE_CURRENT_BINARY_DIR}/bios.sym")
set(BIOS_LISTING "${CMAKE_CURRENT_BINARY_DIR}/bios.lst")
set(BIOS_STAMP "${CMAKE_CURRENT_BINARY_DIR}/bios-${FORMAT}.verified")
file(GLOB BIOS_SOURCES CONFIGURE_DEPENDS src/*.asm driver/*.asm include/*.inc)
list(APPEND BIOS_SOURCES ../mlfs/lib/include/mlfs_types.inc)
set(BIOS_TOOLS tools/check_rom.py tools/image_formats.py)

set(BIOS_FORMAT_COMMAND)
set(BIOS_BYPRODUCTS "${BIOS_CHECK_IMAGE}" "${BIOS_SYMBOLS}" "${BIOS_LISTING}")
if(NOT FORMAT STREQUAL "ihex")
    list(APPEND BIOS_BYPRODUCTS "${BIOS_OUTPUT}")
    set(BIOS_FORMAT_COMMAND COMMAND "${LWASM_EXECUTABLE}" -3 -f "${FORMAT}"
        -Iinclude -Idriver -Isrc -o "${BIOS_OUTPUT}" src/bios.asm)
endif()
add_custom_command(
    OUTPUT "${BIOS_STAMP}"
    BYPRODUCTS ${BIOS_BYPRODUCTS}
    COMMAND "${LWASM_EXECUTABLE}" -3 -f ihex -Iinclude -Idriver -Isrc
        "--list=${BIOS_LISTING}" "--symbol-dump=${BIOS_SYMBOLS}"
        -o "${BIOS_CHECK_IMAGE}" src/bios.asm
    COMMAND "${Python3_EXECUTABLE}" tools/check_rom.py "${BIOS_CHECK_IMAGE}"
        --symbols "${BIOS_SYMBOLS}"
    ${BIOS_FORMAT_COMMAND}
    COMMAND "${CMAKE_COMMAND}" -E touch "${BIOS_STAMP}"
    DEPENDS ${BIOS_SOURCES} ${BIOS_TOOLS} resources/petscii-swe.bin
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building and validating BIOS ROM"
    VERBATIM
)
add_custom_target(bios ALL DEPENDS "${BIOS_STAMP}")
add_custom_target(bios-build DEPENDS "${BIOS_STAMP}")
file(GLOB FS_SOURCES CONFIGURE_DEPENDS modules/filesystem/*.asm include/*.inc)
set(FS_MODULE "${CMAKE_CURRENT_BINARY_DIR}/biosfs.mlp")
add_custom_command(
    OUTPUT "${FS_MODULE}"
    BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/biosfs.ihex"
        "${CMAKE_CURRENT_BINARY_DIR}/biosfs.sym" "${CMAKE_CURRENT_BINARY_DIR}/biosfs.lst"
    COMMAND "${LWASM_EXECUTABLE}" -3 -f ihex -Imodules/filesystem
        "--list=${CMAKE_CURRENT_BINARY_DIR}/biosfs.lst"
        "--symbol-dump=${CMAKE_CURRENT_BINARY_DIR}/biosfs.sym"
        -o "${CMAKE_CURRENT_BINARY_DIR}/biosfs.ihex" modules/filesystem/filesystem.asm
    COMMAND "${Python3_EXECUTABLE}" tools/pack_module.py
        "${CMAKE_CURRENT_BINARY_DIR}/biosfs.ihex" "${FS_MODULE}"
        --kind filesystem --memory-size 0x8000
    COMMAND "${Python3_EXECUTABLE}" tools/check_filesystem.py "${FS_MODULE}"
        --symbols "${CMAKE_CURRENT_BINARY_DIR}/biosfs.sym"
    DEPENDS ${FS_SOURCES} ../mlfs/lib/include/mlfs_types.inc tools/pack_module.py
        tools/module_format.py tools/image_formats.py tools/check_filesystem.py tools/check_rom.py
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    VERBATIM
)
add_custom_target(bios-filesystem ALL DEPENDS "${FS_MODULE}")
find_program(TETRIS_HOST_CC NAMES cc gcc clang)
if(NOT TETRIS_HOST_CC)
    message(FATAL_ERROR "A host C compiler is required for the Tetris rules checks")
endif()
set(TETRIS_RULES_HOST "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules_host")
add_custom_command(OUTPUT "${TETRIS_RULES_HOST}"
    COMMAND "${TETRIS_HOST_CC}" -std=c99 -Wall -Wextra -Werror -Imodules/tetris
        tests/tetris_rules.c modules/tetris/game.c -o "${TETRIS_RULES_HOST}"
    DEPENDS tests/tetris_rules.c modules/tetris/game.c modules/tetris/game.h
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VERBATIM)
add_custom_target(bios-tetris-rules-host ALL DEPENDS "${TETRIS_RULES_HOST}")
set(TETRIS_IO_HOST "${CMAKE_CURRENT_BINARY_DIR}/tetris_io_host")
add_custom_command(OUTPUT "${TETRIS_IO_HOST}"
    COMMAND "${TETRIS_HOST_CC}" -std=c99 -Wall -Wextra -Werror -Imodules/tetris
        tests/tetris_io.c modules/tetris/controls.c modules/tetris/save.c -o "${TETRIS_IO_HOST}"
    DEPENDS tests/tetris_io.c modules/tetris/controls.c modules/tetris/controls.h
        modules/tetris/save.c modules/tetris/save.h modules/tetris/game.h
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VERBATIM)
add_custom_target(bios-tetris-io-host ALL DEPENDS "${TETRIS_IO_HOST}")
find_program(CMOC_EXECUTABLE cmoc)
set(FS_DIAGNOSTIC_ARGS)
if(CMOC_EXECUTABLE)
    set(FS_DIAGNOSTIC "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.mlp")
    add_custom_command(
        OUTPUT "${FS_DIAGNOSTIC}"
        BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.srec"
            "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex"
            "${CMAKE_CURRENT_BINARY_DIR}/filesystem_c_shim.o"
            "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
        COMMAND "${LWASM_EXECUTABLE}" -f obj -o "${CMAKE_CURRENT_BINARY_DIR}/filesystem_c_shim.o"
            modules/filesystem/filesystem_c_shim.asm
        COMMAND "${LWASM_EXECUTABLE}" -f obj -o "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
            modules/diagnostic/serial_shim.asm
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target --srec --org=0420 --limit=4000 --no-relocate
            -Iinclude -o "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.srec" modules/diagnostic/diagnostic.c
            "${CMAKE_CURRENT_BINARY_DIR}/filesystem_c_shim.o"
            "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
        COMMAND "${LWASM_EXECUTABLE}" -3 -f ihex -o "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex"
            modules/diagnostic/entry.asm
        COMMAND "${Python3_EXECUTABLE}" tools/pack_module.py
            "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.srec" "${FS_DIAGNOSTIC}"
            --overlay "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex" --kind application --memory-size 0x3C00
        DEPENDS modules/diagnostic/diagnostic.c modules/diagnostic/entry.asm
            modules/diagnostic/serial_shim.asm modules/filesystem/filesystem_c_shim.asm
            include/filesystem.h include/filesystem.inc include/module.inc tools/pack_module.py
            tools/module_format.py tools/image_formats.py
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        VERBATIM)
    add_custom_target(bios-fsdiag ALL DEPENDS "${FS_DIAGNOSTIC}")
    list(APPEND FS_DIAGNOSTIC_ARGS --diagnostic "${FS_DIAGNOSTIC}")
    set(TETRIS_RULES_MODULE "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.mlp")
    add_custom_command(OUTPUT "${TETRIS_RULES_MODULE}"
        BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/tetris_game.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.srec"
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target -DTETRIS_TARGET
            -Iinclude -Imodules/tetris -c -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_game.o"
            modules/tetris/game.c
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target --srec --org=0420 --limit=4000
            --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris
            -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.srec" tests/tetris_rules.c
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_game.o" "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
        COMMAND "${Python3_EXECUTABLE}" tools/pack_module.py
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.srec" "${TETRIS_RULES_MODULE}"
            --overlay "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex" --kind application --memory-size 0x3C00
        DEPENDS tests/tetris_rules.c modules/tetris/game.c modules/tetris/game.h
            include/integer.h "${FS_DIAGNOSTIC}" tools/pack_module.py
            tools/module_format.py tools/image_formats.py
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VERBATIM)
    add_custom_target(bios-tetris-rules ALL DEPENDS "${TETRIS_RULES_MODULE}")
    add_dependencies(bios-tetris-rules bios-fsdiag)
    set(TETRIS_MODULE "${CMAKE_CURRENT_BINARY_DIR}/tetris.mlp")
    add_custom_command(OUTPUT "${TETRIS_MODULE}"
        BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/tetris.srec"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris.map" "${CMAKE_CURRENT_BINARY_DIR}/tetris.link"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_controls.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_save.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_platform.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_entry.ihex"
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target -DTETRIS_TARGET
            -Iinclude -Imodules/tetris -c -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_controls.o"
            modules/tetris/controls.c
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target -DTETRIS_TARGET
            -Iinclude -Imodules/tetris -c -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_save.o"
            modules/tetris/save.c
        COMMAND "${LWASM_EXECUTABLE}" -3 -f obj -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_platform.o"
            modules/tetris/platform.asm
        COMMAND "${LWASM_EXECUTABLE}" -3 -f ihex -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_entry.ihex"
            modules/tetris/entry.asm
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target --srec --org=0500 --limit=4000
            --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris --intermediate
            "--intdir=${CMAKE_CURRENT_BINARY_DIR}" -o "${CMAKE_CURRENT_BINARY_DIR}/tetris.srec"
            modules/tetris/application.c "${CMAKE_CURRENT_BINARY_DIR}/tetris_game.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_controls.o" "${CMAKE_CURRENT_BINARY_DIR}/tetris_save.o"
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_platform.o" "${CMAKE_CURRENT_BINARY_DIR}/filesystem_c_shim.o"
        COMMAND "${Python3_EXECUTABLE}" tools/pack_module.py
            "${CMAKE_CURRENT_BINARY_DIR}/tetris.srec" "${TETRIS_MODULE}"
            --overlay "${CMAKE_CURRENT_BINARY_DIR}/tetris_entry.ihex" --kind application --memory-size 0x3C00
        DEPENDS "${TETRIS_RULES_MODULE}" modules/tetris/application.c
            modules/tetris/controls.c modules/tetris/controls.h modules/tetris/save.c modules/tetris/save.h
            modules/tetris/platform.asm modules/tetris/platform.h modules/tetris/entry.asm
            modules/tetris/game.h include/module.inc include/filesystem.h include/filesystem.inc
            include/io.inc include/memory.inc tools/pack_module.py tools/module_format.py tools/image_formats.py
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VERBATIM)
    add_custom_target(bios-tetris ALL DEPENDS "${TETRIS_MODULE}")
    add_dependencies(bios-tetris bios-tetris-rules)
    set(TETRIS_IO_MODULE "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.mlp")
    add_custom_command(OUTPUT "${TETRIS_IO_MODULE}"
        BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.srec"
        COMMAND "${CMOC_EXECUTABLE}" -Werror --void-target --srec --org=0420 --limit=4000
            --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris
            -o "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.srec" tests/tetris_io.c
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_controls.o" "${CMAKE_CURRENT_BINARY_DIR}/tetris_save.o"
            "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
        COMMAND "${Python3_EXECUTABLE}" tools/pack_module.py
            "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.srec" "${TETRIS_IO_MODULE}"
            --overlay "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex" --kind application --memory-size 0x3C00
        DEPENDS "${TETRIS_MODULE}" tests/tetris_io.c modules/tetris/controls.h modules/tetris/save.h
            tools/pack_module.py tools/module_format.py tools/image_formats.py
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" VERBATIM)
    add_custom_target(bios-tetris-io ALL DEPENDS "${TETRIS_IO_MODULE}")
    add_dependencies(bios-tetris-io bios-tetris)
endif()
add_custom_target(bios-clean
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${BIOS_OUTPUT}" "${BIOS_CHECK_IMAGE}"
        "${BIOS_STAMP}" "${BIOS_SYMBOLS}" "${BIOS_LISTING}" "${FS_MODULE}"
        "${CMAKE_CURRENT_BINARY_DIR}/biosfs.ihex" "${CMAKE_CURRENT_BINARY_DIR}/biosfs.sym"
        "${CMAKE_CURRENT_BINARY_DIR}/biosfs.lst" "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.mlp"
        "${CMAKE_CURRENT_BINARY_DIR}/fsdiag.srec" "${CMAKE_CURRENT_BINARY_DIR}/fsdiag_entry.ihex"
        "${CMAKE_CURRENT_BINARY_DIR}/filesystem_c_shim.o" "${CMAKE_CURRENT_BINARY_DIR}/diagnostic_serial.o"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris.mlp" "${CMAKE_CURRENT_BINARY_DIR}/tetris.srec"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris.map" "${CMAKE_CURRENT_BINARY_DIR}/tetris.link"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_entry.ihex" "${CMAKE_CURRENT_BINARY_DIR}/tetris_platform.o"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_game.o" "${CMAKE_CURRENT_BINARY_DIR}/tetris_controls.o"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_save.o" "${CMAKE_CURRENT_BINARY_DIR}/application.o"
        "${CMAKE_CURRENT_BINARY_DIR}/application.s" "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules_host"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.mlp" "${CMAKE_CURRENT_BINARY_DIR}/tetris_rules.srec"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_io_host" "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.mlp"
        "${CMAKE_CURRENT_BINARY_DIR}/tetris_io.srec")

enable_testing()
add_test(NAME bios-tetris-rules-host COMMAND "${TETRIS_RULES_HOST}")
add_test(NAME bios-tetris-io-host COMMAND "${TETRIS_IO_HOST}")
add_test(NAME bios-tools
    COMMAND "${Python3_EXECUTABLE}" -m unittest discover -s tests -v
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
add_test(NAME bios-rom
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/check_rom.py"
        "${BIOS_CHECK_IMAGE}" --symbols "${BIOS_SYMBOLS}")

set(SIMULATOR_EXECUTABLE "" CACHE FILEPATH "Optional microlind-sim CLI for BIOS integration tests")
if(SIMULATOR_EXECUTABLE)
    if(CMOC_EXECUTABLE)
        add_test(NAME bios-tetris-target
            COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/test_tetris.py"
                --simulator "${SIMULATOR_EXECUTABLE}" --rom "${BIOS_CHECK_IMAGE}"
                --symbols "${BIOS_SYMBOLS}" --filesystem "${FS_MODULE}"
                --rules "${TETRIS_RULES_MODULE}" --io-tests "${TETRIS_IO_MODULE}"
                --game "${TETRIS_MODULE}" --game-map "${CMAKE_CURRENT_BINARY_DIR}/tetris.map"
                --diagnostic "${FS_DIAGNOSTIC}" --cc "${TETRIS_HOST_CC}")
        set_tests_properties(bios-tetris-target PROPERTIES FIXTURES_REQUIRED simulator-sex)
    endif()
    add_test(NAME bios-simulator-sex
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/diagnose_simulator.py"
            --simulator "${SIMULATOR_EXECUTABLE}" --rom "${BIOS_CHECK_IMAGE}"
            --symbols "${BIOS_SYMBOLS}" --assembler "${LWASM_EXECUTABLE}")
    set_tests_properties(bios-simulator-sex PROPERTIES FIXTURES_SETUP simulator-sex)
    add_test(NAME bios-simulator
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/test_simulator.py"
            --simulator "${SIMULATOR_EXECUTABLE}" --rom "${BIOS_CHECK_IMAGE}"
            --symbols "${BIOS_SYMBOLS}" --assembler "${LWASM_EXECUTABLE}")
    add_test(NAME bios-filesystem
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/test_filesystem.py"
            --simulator "${SIMULATOR_EXECUTABLE}" --rom "${BIOS_CHECK_IMAGE}"
            --symbols "${BIOS_SYMBOLS}" --filesystem "${FS_MODULE}"
            --assembler "${LWASM_EXECUTABLE}" ${FS_DIAGNOSTIC_ARGS})
    set_tests_properties(bios-filesystem PROPERTIES FIXTURES_REQUIRED simulator-sex)
endif()
