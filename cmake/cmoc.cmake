# CMOC Build Macro for Microlind Projects
# This macro provides a standardized way to build C projects using the cmoc compiler

macro(build_cmoc_project PROJECT_NAME SOURCE_FILES OUTPUT_NAME)
    # Set default values for optional parameters
    set(APP_ORIGIN "0xEF00")
    set(APP_DATA "0xC000")
    set(INCLUDE_DIR "../../include")
    set(FORMAT "srec")
    # Parse additional arguments
    set(options INTERMEDIATE DEBUG)
    set(oneValueArgs ORIGIN DATA STACK STACK_SIZE FORMAT)
    set(multiValueArgs INCLUDE_DIR)
    cmake_parse_arguments(CMOC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Use provided values or defaults
    if(CMOC_ORIGIN)
        set(APP_ORIGIN "--org=${CMOC_ORIGIN}")
    else()
        set(APP_ORIGIN "")
    endif()
    if(CMOC_DATA)
        set(APP_DATA "--data=${CMOC_DATA}")
    else()
        set(APP_DATA "")
    endif()
    if(CMOC_INCLUDE_DIR)
        # Convert list of include directories to -I arguments
        set(INCLUDE_ARGS "")
        foreach(dir ${CMOC_INCLUDE_DIR})
            set(INCLUDE_ARGS "${INCLUDE_ARGS} -I ${dir}")
        endforeach()
    else()
        set(INCLUDE_ARGS "")
    endif()
    
    # Build the complete cmoc command as a string
    set(CMOC_CMD "cmoc ${INCLUDE_ARGS} ${APP_ORIGIN} ${APP_DATA} ${STACK} ${STACK_SIZE} ${INTERMEDIATE_DIR} ${INTERMEDIATE_FLAG} ${FORMAT_FLAG} -o ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT_EXT} ${SOURCE_FILES}")
    if(CMOC_FORMAT)
        set(FORMAT_FLAG "--${CMOC_FORMAT}")
        set(FORMAT_EXT "${CMOC_FORMAT}")
    else()
        set(FORMAT_FLAG "--srec")
        set(FORMAT_EXT "srec")
    endif()
    if(CMOC_STACK)
        set(STACK "--initial-s=${CMOC_STACK}")
    else()
        set(STACK "")
    endif()
    if(CMOC_STACK_SIZE)
        set(STACK_SIZE "--stack-space=${CMOC_STACK_SIZE}")
    else()
        set(STACK_SIZE "")
    endif()
    if(CMOC_INTERMEDIATE)
        set(INTERMEDIATE_DIR "--intdir=${CMAKE_CURRENT_BINARY_DIR}")
        set(INTERMEDIATE_FLAG "-i")
    else()
        set(INTERMEDIATE_DIR "")
        set(INTERMEDIATE_FLAG "")
    endif()

    if(CMOC_DEBUG)
        set(DEBUG_FLAG "-d")
    else()
        set(DEBUG_FLAG "")
    endif()

    # Set build directory
    set(BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")
    
    # Create build directory
    file(MAKE_DIRECTORY ${BUILD_DIR})
    
    # Custom command to build the C project using cmoc
    add_custom_command(
        OUTPUT ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT_EXT}
        COMMAND echo "Running: ${CMOC_CMD}"
        COMMAND bash -c "${CMOC_CMD}"
        DEPENDS ${SOURCE_FILES}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "Building ${PROJECT_NAME} with cmoc"
        VERBATIM
    )
    
    # Create a custom target that can be built with 'make'
    add_custom_target(${PROJECT_NAME} ALL
        DEPENDS ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT_EXT}
        COMMENT "Building ${PROJECT_NAME}"
    )
    
    # Custom target for clean
    if(CMOC_INTERMEDIATE)
        add_custom_target(${PROJECT_NAME}-clean
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.${FORMAT_EXT}
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.lst
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.o
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.s
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.link
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.map
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.sym
            COMMENT "Cleaning ${PROJECT_NAME} build artifacts and intermediate files"
        )
    else()
        add_custom_target(${PROJECT_NAME}-clean
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT_EXT}
            COMMENT "Cleaning ${PROJECT_NAME} build artifacts"
        )
    endif()

    # Print build information
    message(STATUS "Building ${PROJECT_NAME}")
    message(STATUS "  Source: ${SOURCE_FILES}")
    message(STATUS "  Output: ${OUTPUT_NAME}.${FORMAT_EXT}")
    message(STATUS "  Format: ${FORMAT_EXT}")
    message(STATUS "  Build directory: ${BUILD_DIR}")
    message(STATUS "  App origin: ${APP_ORIGIN}")
    message(STATUS "  App data: ${APP_DATA}")
    message(STATUS "  Include directories: ${CMOC_INCLUDE_DIR}")
endmacro()
