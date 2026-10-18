cmake_minimum_required(VERSION 3.22.1)
project(moy_ai_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# The POCO X8 Pro Max / Dimensity 9500s implements ARMv9 and supports
# ARMv8.2 dot-product + FP16. Optimize GGML CPU kernels only, rather than
# raising the ABI baseline of every library in the APK.
if(ANDROID AND (ANDROID_ABI STREQUAL "arm64-v8a" OR CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a"))
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

if (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp source missing. Use the manual Build APK workflow to fetch it.")
endif()
add_subdirectory(llama.cpp "${CMAKE_CURRENT_BINARY_DIR}/llama-source")
add_library(moy_ai_native SHARED llama_bridge.cpp)
target_link_libraries(moy_ai_native PRIVATE llama log)
target_compile_options(moy_ai_native PRIVATE -O2 -fexceptions -frtti)
