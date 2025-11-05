# CMakeLists.txt for MLFS library
cmake_minimum_required(VERSION 3.16)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Set compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

# Create mlfs library target
add_library(mlfs STATIC
    src/mlfs.c
    include/mlfs.h
    include/mlfs_types.h
)

# Set include directories for the library
target_include_directories(mlfs PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Install library and headers
install(TARGETS mlfs
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(FILES 
    include/mlfs.h 
    include/mlfs_types.h
    DESTINATION include
)
