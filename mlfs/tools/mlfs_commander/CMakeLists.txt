# CMakeLists.txt for MLFS Commander
cmake_minimum_required(VERSION 3.16)

project(mlfs_commander LANGUAGES C CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(STATUS "MLFS Commander is Linux-only for now; skipping target.")
    return()
endif()

find_package(Qt6 QUIET COMPONENTS Widgets)
if(NOT Qt6_FOUND)
    message(WARNING "Qt6 Widgets was not found; skipping MLFS Commander target.")
    return()
endif()

if(NOT TARGET mlfs)
    add_subdirectory(
        ${CMAKE_CURRENT_LIST_DIR}/../../lib
        ${CMAKE_CURRENT_BINARY_DIR}/mlfs_lib
    )
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
include(CTest)

add_executable(${PROJECT_NAME}
    src/main.cpp
    src/ui/MainWindow.cpp
    src/ui/MainWindow.h
    src/backend/FileBlockDevice.cpp
    src/backend/FileBlockDevice.h
    src/backend/MlfsImageBackend.cpp
    src/backend/MlfsImageBackend.h
    src/model/DirectoryEntry.h
    src/model/PartitionInfo.h
    src/support/OperationResult.h
)

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    mlfs
    Qt6::Widgets
)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(BUILD_TESTING)
    add_executable(mlfs_commander_backend_tests
        tests/test_backend.cpp
        src/backend/FileBlockDevice.cpp
        src/backend/FileBlockDevice.h
        src/backend/MlfsImageBackend.cpp
        src/backend/MlfsImageBackend.h
        src/model/DirectoryEntry.h
        src/model/PartitionInfo.h
        src/support/OperationResult.h
    )

    target_include_directories(mlfs_commander_backend_tests PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    target_link_libraries(mlfs_commander_backend_tests PRIVATE
        mlfs
        Qt6::Core
    )

    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(mlfs_commander_backend_tests PRIVATE -Wall -Wextra -Wpedantic)
    endif()

    add_test(NAME MlfsCommanderBackend COMMAND mlfs_commander_backend_tests)
endif()

install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)
