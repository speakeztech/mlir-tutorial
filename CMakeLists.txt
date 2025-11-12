cmake_minimum_required(VERSION 3.20.0)

project(mlir-tutorial LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17 CACHE STRING "C++ standard to conform to")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_DEPS ON)

# Windows/MSYS2 specific configurations
if(WIN32)
    message(STATUS "Configuring for Windows with MSYS2/CLANG64")

    # Detect MSYS2 installation
    if(NOT DEFINED MSYS2_ROOT)
        if(EXISTS "C:/msys64")
            set(MSYS2_ROOT "C:/msys64")
        elseif(EXISTS "D:/msys64")
            set(MSYS2_ROOT "D:/msys64")
        else()
            message(WARNING "MSYS2 not found in standard locations. Set MSYS2_ROOT manually.")
        endif()
    endif()

    if(MSYS2_ROOT)
        message(STATUS "Found MSYS2 at: ${MSYS2_ROOT}")

        # Auto-detect MLIR/LLVM from CLANG64 environment
        if(NOT DEFINED MLIR_DIR AND EXISTS "${MSYS2_ROOT}/clang64/lib/cmake/mlir")
            set(MLIR_DIR "${MSYS2_ROOT}/clang64/lib/cmake/mlir" CACHE PATH "Path to MLIRConfig.cmake")
        endif()

        if(NOT DEFINED LLVM_DIR AND EXISTS "${MSYS2_ROOT}/clang64/lib/cmake/llvm")
            set(LLVM_DIR "${MSYS2_ROOT}/clang64/lib/cmake/llvm" CACHE PATH "Path to LLVMConfig.cmake")
        endif()
    endif()

    # Use Clang and LLD linker (avoids GNU ld library ordering issues)
    set(CMAKE_C_COMPILER "${MSYS2_ROOT}/clang64/bin/clang.exe")
    set(CMAKE_CXX_COMPILER "${MSYS2_ROOT}/clang64/bin/clang++.exe")
    set(CMAKE_LINKER "${MSYS2_ROOT}/clang64/bin/ld.lld.exe")

    # Use LLD linker flags
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=lld")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fuse-ld=lld")

    message(STATUS "Using Clang/LLD toolchain from CLANG64 environment")
endif()

find_package(MLIR REQUIRED CONFIG)

message(STATUS "Using MLIRConfig.cmake in: ${MLIR_DIR}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")
message(STATUS "MLIR Include Dirs: ${MLIR_INCLUDE_DIRS}")
message(STATUS "LLVM Include Dirs: ${LLVM_INCLUDE_DIRS}")

set(MLIR_BINARY_DIR ${CMAKE_BINARY_DIR})

include(AddLLVM)
include(TableGen)

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
include(AddMLIR)
include_directories(${LLVM_INCLUDE_DIRS})
include_directories(${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR})
include_directories(${PROJECT_BINARY_DIR})

# or-tools is NO LONGER REQUIRED - tutorial 12 now uses a simple greedy algorithm
# instead of the ILP solver, removing the dependency on or-tools entirely.
# This was done to simplify the build process and remove unnecessary dependencies.
# The greedy algorithm teaches the same MLIR dataflow analysis concepts.
message(STATUS "or-tools dependency removed - tutorial 12 uses simplified algorithm")

add_subdirectory(tests)
add_subdirectory(tools)
add_subdirectory(lib)
