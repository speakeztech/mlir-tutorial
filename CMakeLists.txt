cmake_minimum_required(VERSION 3.20.0)

project(mlir-tutorial LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17 CACHE STRING "C++ standard to conform to")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_DEPS ON)

# Windows/MSYS2 specific configurations
if(WIN32)
    message(STATUS "Configuring for Windows with MSYS2/MinGW64")

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

        # Auto-detect MLIR/LLVM if not specified
        if(NOT DEFINED MLIR_DIR AND EXISTS "${MSYS2_ROOT}/mingw64/lib/cmake/mlir")
            set(MLIR_DIR "${MSYS2_ROOT}/mingw64/lib/cmake/mlir" CACHE PATH "Path to MLIRConfig.cmake")
        endif()

        if(NOT DEFINED LLVM_DIR AND EXISTS "${MSYS2_ROOT}/mingw64/lib/cmake/llvm")
            set(LLVM_DIR "${MSYS2_ROOT}/mingw64/lib/cmake/llvm" CACHE PATH "Path to LLVMConfig.cmake")
        endif()
    endif()
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

# Optional: or-tools dependency (only needed for specific tutorials)
# Comment out if you encounter download issues
option(ENABLE_ORTOOLS "Enable or-tools dependency" ON)

if(ENABLE_ORTOOLS)
    message(STATUS "Fetching or-tools...")
    include(FetchContent)
    FetchContent_Declare(
      or-tools
      GIT_REPOSITORY https://github.com/google/or-tools.git
      GIT_TAG        v9.11
    )
    FetchContent_MakeAvailable(or-tools)
    message(STATUS "Done fetching or-tools")
else()
    message(STATUS "or-tools disabled (set ENABLE_ORTOOLS=ON to enable)")
endif()

add_subdirectory(tests)
add_subdirectory(tools)
add_subdirectory(lib)
