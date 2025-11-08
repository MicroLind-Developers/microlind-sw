# CMakeLists.txt for MLFS CLI application
cmake_minimum_required(VERSION 3.16)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the main project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Find readline library (optional)
find_path(READLINE_INCLUDE_DIR 
    NAMES readline/readline.h
    PATHS /usr/include /usr/local/include /opt/local/include
)
find_library(READLINE_LIBRARY 
    NAMES readline
    PATHS /usr/lib /usr/local/lib /opt/local/lib
)
find_library(HISTORY_LIBRARY 
    NAMES history
    PATHS /usr/lib /usr/local/lib /opt/local/lib
)

if(READLINE_INCLUDE_DIR AND READLINE_LIBRARY)
    message(STATUS "Found readline: ${READLINE_LIBRARY}")
    if(HISTORY_LIBRARY)
        message(STATUS "Found history: ${HISTORY_LIBRARY}")
        set(READLINE_LIBRARIES ${READLINE_LIBRARY} ${HISTORY_LIBRARY})
    else()
        set(READLINE_LIBRARIES ${READLINE_LIBRARY})
    endif()
    set(HAVE_READLINE TRUE)
else()
    message(STATUS "Readline not found - using simple CLI mode")
    message(STATUS "To install readline on Ubuntu/Debian: sudo apt-get install libreadline-dev")
    message(STATUS "To install readline on CentOS/RHEL: sudo yum install readline-devel")
    message(STATUS "To install readline on macOS: brew install readline")
    set(HAVE_READLINE FALSE)
endif()

# Create CLI executable
add_executable(mlfs_cli
    main.c
    cli_commands.c
    file_io.c
)

# Link with the mlfs library
target_link_libraries(mlfs_cli PRIVATE mlfs)

# Add readline if available
if(HAVE_READLINE)
    target_include_directories(mlfs_cli PRIVATE ${READLINE_INCLUDE_DIR})
    target_link_libraries(mlfs_cli PRIVATE ${READLINE_LIBRARIES})
    target_compile_definitions(mlfs_cli PRIVATE HAVE_READLINE=1)
endif()

# Set include directories
target_include_directories(mlfs_cli PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}
)

# Set the output name
set_target_properties(mlfs_cli PROPERTIES OUTPUT_NAME mlfs)

# Install CLI executable
install(TARGETS mlfs_cli
    RUNTIME DESTINATION bin
)

# Register clean target with global property (following project pattern)
set_property(GLOBAL APPEND PROPERTY MICROLIND_CLEAN_TARGETS cli-clean)
add_custom_target(cli-clean
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target clean
    COMMENT "Cleaning CLI targets"
)
