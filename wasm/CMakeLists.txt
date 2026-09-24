cmake_minimum_required(VERSION 3.20)
project(stlc_runtime LANGUAGES C CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
  message(FATAL_ERROR "Configure with emcmake.")
endif()

# Use Lean's unmodified runtime inside one Emscripten thread.
# No compiler, kernel, native plugins, GMP, or allocator dependency is needed.
set(USE_MIMALLOC OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(LEAN_IS_STAGE0 "#define LEAN_IS_STAGE0 0")
# BuildWasm supplies the compiler's version header and source revision.
if(NOT EXISTS "${CMAKE_BINARY_DIR}/include/lean/version.h" OR NOT GIT_SHA1)
  message(FATAL_ERROR "Run the Lean build driver to prepare compiler metadata.")
endif()
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/include/lean")
configure_file("${LEAN_SOURCE}/src/config.h.in" "include/lean/config.h" @ONLY)
configure_file("${LEAN_SOURCE}/src/githash.h.in" "include/githash.h" @ONLY)
include_directories("${CMAKE_BINARY_DIR}/include" "${LEAN_SOURCE}/src/include" "${LEAN_SOURCE}/src" "${LIBUV_SOURCE}/include")
add_compile_definitions(LEAN_EMSCRIPTEN LEAN_MULTI_THREAD NDEBUG)
add_compile_options(-O2 -flto -fwasm-exceptions -ffunction-sections -fdata-sections)
# The pure interpreter never uses the asynchronous networking/event-loop API.
# Compile the runtime's top-level sources, including its normal allocator,
# bignums, closures, IO initialization, mutexes, and thread support. Emscripten
# supplies its single-thread libc; no pthread workers or SharedArrayBuffer are used.
file(GLOB runtime_sources CONFIGURE_DEPENDS "${LEAN_SOURCE}/src/runtime/*.cpp")
add_library(leanrt STATIC ${runtime_sources})

# Lean's IO initialization/error handling also needs its filesystem support.
# This is the same source selection used by Lean's Emscripten configuration.
# Supply the real LibUV implementation; never suppress undefined symbols.
set(LIBUV_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LIBUV_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${LIBUV_SOURCE}" libuv)
target_sources(uv_a PRIVATE "${LIBUV_SOURCE}/src/unix/no-proctitle.c")
