cmake_minimum_required(VERSION 3.20)
project(mlos NONE)
find_program(MLOS_MAKE NAMES gmake make REQUIRED)
set(MLOS_SIMULATOR "${CMAKE_CURRENT_SOURCE_DIR}/../../microlind-sim/build/microlind-sim-cli" CACHE FILEPATH "MLOS simulator CLI")
add_custom_target(mlos-build ALL
    COMMAND ${MLOS_MAKE} -C ${CMAKE_CURRENT_SOURCE_DIR} BUILD=${CMAKE_CURRENT_BINARY_DIR}/target SIMULATOR=${MLOS_SIMULATOR} all
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/target/mlos.ihex
    VERBATIM)
add_custom_target(mlos-test
    COMMAND ${MLOS_MAKE} -C ${CMAKE_CURRENT_SOURCE_DIR} BUILD=${CMAKE_CURRENT_BINARY_DIR}/target SIMULATOR=${MLOS_SIMULATOR} test
    VERBATIM)

add_custom_target(mlos-runtime
    DEPENDS mlos-build)
add_custom_target(mlos-acceptance
    COMMAND ${MLOS_MAKE} -C ${CMAKE_CURRENT_SOURCE_DIR} BUILD=${CMAKE_CURRENT_BINARY_DIR}/target SIMULATOR=${MLOS_SIMULATOR} acceptance runtime-check
    VERBATIM)
