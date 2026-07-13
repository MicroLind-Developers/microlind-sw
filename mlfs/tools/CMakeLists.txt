# CMakeLists.txt for MLFS tools
cmake_minimum_required(VERSION 3.16)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the main project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Add tool subdirectories
add_subdirectory(cli)
add_subdirectory(mlfs_info)
add_subdirectory(mlfs_blockdev)
add_subdirectory(mlfs_commander)

# Register clean target with global property (following project pattern)
set_property(GLOBAL APPEND PROPERTY MICROLIND_CLEAN_TARGETS tools-clean)
add_custom_target(tools-clean
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target clean
    COMMENT "Cleaning tools targets"
)
