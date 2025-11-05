# CMakeLists.txt for MLFS tools
cmake_minimum_required(VERSION 3.16)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the main project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Create mlfs_info utility
add_executable(mlfs_info
    mlfs_info.c
)

# Link with the mlfs library
target_link_libraries(mlfs_info PRIVATE mlfs)

# Set include directories
target_include_directories(mlfs_info PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}
)

# Install tool
install(TARGETS mlfs_info
    RUNTIME DESTINATION bin
)

# Register clean target with global property (following project pattern)
set_property(GLOBAL APPEND PROPERTY MICROLIND_CLEAN_TARGETS tools-clean)
add_custom_target(tools-clean
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target clean
    COMMENT "Cleaning tools targets"
)
