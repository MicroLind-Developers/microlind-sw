# CMOC Build Macro for Microlind Projects
# This macro provides a standardized way to build C projects using the cmoc compiler

function(build_cmoc_project PROJECT_NAME SOURCE_FILES OUTPUT_NAME)
    # Set default values for optional parameters
    set(FORMAT "srec")
    # Parse additional arguments
    set(options INTERMEDIATE DEBUG)
    set(oneValueArgs ORIGIN DATA STACK STACK_SIZE FORMAT)
    set(multiValueArgs INCLUDE_DIR)
    cmake_parse_arguments(CMOC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(CMOC_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown build_cmoc_project arguments: ${CMOC_UNPARSED_ARGUMENTS}")
    endif()

    # Set build directory
    set(BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")

    # Use provided values or defaults
    set(CMOC_ARGS)
    foreach(dir IN LISTS CMOC_INCLUDE_DIR)
        list(APPEND CMOC_ARGS -I "${dir}")
    endforeach()

    if(CMOC_ORIGIN)
        list(APPEND CMOC_ARGS "--org=${CMOC_ORIGIN}")
    endif()
    if(CMOC_DATA)
        list(APPEND CMOC_ARGS "--data=${CMOC_DATA}")
    endif()
    if(CMOC_STACK)
        list(APPEND CMOC_ARGS "--initial-s=${CMOC_STACK}")
    endif()
    if(CMOC_STACK_SIZE)
        list(APPEND CMOC_ARGS "--stack-space=${CMOC_STACK_SIZE}")
    endif()
    if(CMOC_INTERMEDIATE)
        list(APPEND CMOC_ARGS "--intdir=${CMAKE_CURRENT_BINARY_DIR}" -i)
    endif()
    if(CMOC_DEBUG)
        list(APPEND CMOC_ARGS -d)
    endif()

    if(CMOC_FORMAT)
        set(FORMAT_EXT "${CMOC_FORMAT}")
    else()
        set(FORMAT_EXT "${FORMAT}")
    endif()

    set(OUTPUT_FILE "${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT_EXT}")
    list(APPEND CMOC_ARGS "--${FORMAT_EXT}" -o "${OUTPUT_FILE}")
    list(APPEND CMOC_ARGS ${SOURCE_FILES})
    string(JOIN " " CMOC_ARGS_DISPLAY ${CMOC_ARGS})

    # Create build directory
    file(MAKE_DIRECTORY "${BUILD_DIR}")

    # Custom command to build the C project using cmoc
    add_custom_command(
        OUTPUT "${OUTPUT_FILE}"
        COMMAND ${CMAKE_COMMAND} -E echo "Running: cmoc ${CMOC_ARGS_DISPLAY}"
        COMMAND cmoc ${CMOC_ARGS}
        DEPENDS ${SOURCE_FILES}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        COMMENT "Building ${PROJECT_NAME} with cmoc"
        VERBATIM
    )
    
    # Create a custom target that can be built with 'make'
    add_custom_target(${PROJECT_NAME} ALL
        DEPENDS "${OUTPUT_FILE}"
        COMMENT "Building ${PROJECT_NAME}"
    )
    
    # Custom target for clean
    if(CMOC_INTERMEDIATE)
        add_custom_target(${PROJECT_NAME}-clean
            COMMAND ${CMAKE_COMMAND} -E remove -f "${OUTPUT_FILE}"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.lst"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.o"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.s"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.link"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.map"
            COMMAND ${CMAKE_COMMAND} -E remove -f "${BUILD_DIR}/${OUTPUT_NAME}.sym"
            COMMENT "Cleaning ${PROJECT_NAME} build artifacts and intermediate files"
        )
    else()
        add_custom_target(${PROJECT_NAME}-clean
            COMMAND ${CMAKE_COMMAND} -E remove -f "${OUTPUT_FILE}"
            COMMENT "Cleaning ${PROJECT_NAME} build artifacts"
        )
    endif()

    # Print build information
    message(STATUS "Building ${PROJECT_NAME}")
    message(STATUS "  Source: ${SOURCE_FILES}")
    message(STATUS "  Output: ${OUTPUT_FILE}")
    message(STATUS "  Format: ${FORMAT_EXT}")
    message(STATUS "  Build directory: ${BUILD_DIR}")
    message(STATUS "  App origin: ${CMOC_ORIGIN}")
    message(STATUS "  App data: ${CMOC_DATA}")
    message(STATUS "  Include directories: ${CMOC_INCLUDE_DIR}")
endfunction()
