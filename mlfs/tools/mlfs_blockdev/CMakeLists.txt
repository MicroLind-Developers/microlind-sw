# CMakeLists.txt for mlfs_blockdev utility
cmake_minimum_required(VERSION 3.16)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags to match the main project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Create mlfs_blockdev utility
add_executable(mlfs_blockdev
    mlfs_blockdev.c
)

# Link with the mlfs library
target_link_libraries(mlfs_blockdev PRIVATE mlfs)

# Set include directories  
target_include_directories(mlfs_blockdev PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}
)

# Install tool
install(TARGETS mlfs_blockdev
    RUNTIME DESTINATION bin
)

