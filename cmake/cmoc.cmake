# CMOC Build Macro for Microlind Projects
# This macro provides a standardized way to build C projects using the cmoc compiler

macro(build_cmoc_project PROJECT_NAME SOURCE_FILE OUTPUT_NAME)
    # Set default values for optional parameters
    set(APP_ORIGIN "0xEF00")
    set(APP_DATA "0xC000")
    set(INCLUDE_DIR "../../include")
    set(FORMAT "srec")
    # Parse additional arguments
    set(options INTERMEDIATE DEBUG)
    set(oneValueArgs ORIGIN DATA STACK STACK_SIZE INCLUDE_DIR FORMAT)
    set(multiValueArgs)
    cmake_parse_arguments(CMOC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Use provided values or defaults
    if(CMOC_ORIGIN)
        set(APP_ORIGIN ${CMOC_ORIGIN})
    endif()
    if(CMOC_DATA)
        set(APP_DATA ${CMOC_DATA})
    endif()
    if(CMOC_INCLUDE_DIR)
        set(INCLUDE_DIR ${CMOC_INCLUDE_DIR})
    endif()
    if(CMOC_FORMAT)
        set(FORMAT ${CMOC_FORMAT})
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
        OUTPUT ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT}
        COMMAND cmoc -I ${INCLUDE_DIR} --org=${APP_ORIGIN} --data=${APP_DATA} ${STACK} ${STACK_SIZE} ${INTERMEDIATE_DIR} ${INTERMEDIATE_FLAG} --${FORMAT} -o ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT} ${SOURCE_FILE}
        DEPENDS ${SOURCE_FILE}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "Building ${PROJECT_NAME} with cmoc"
        VERBATIM
    )
    
    # Create a custom target that can be built with 'make'
    add_custom_target(${PROJECT_NAME} ALL
        DEPENDS ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT}
        COMMENT "Building ${PROJECT_NAME}"
    )
    
    # Custom target for clean
    if(CMOC_INTERMEDIATE)
        add_custom_target(${PROJECT_NAME}-clean
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/*.${FORMAT}
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
            COMMAND ${CMAKE_COMMAND} -E remove -f ${BUILD_DIR}/${OUTPUT_NAME}.${FORMAT}
            COMMENT "Cleaning ${PROJECT_NAME} build artifacts"
        )
    endif()

    # Print build information
    message(STATUS "Building ${PROJECT_NAME}")
    message(STATUS "  Source: ${SOURCE_FILE}")
    message(STATUS "  Output: ${OUTPUT_NAME}.${FORMAT}")
    message(STATUS "  Format: ${FORMAT}")
    message(STATUS "  Build directory: ${BUILD_DIR}")
    message(STATUS "  App origin: ${APP_ORIGIN}")
    message(STATUS "  App data: ${APP_DATA}")
    message(STATUS "  Include directory: ${INCLUDE_DIR}")
endmacro()
