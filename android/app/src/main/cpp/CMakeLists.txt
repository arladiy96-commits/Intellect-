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
# Android Vulkan is built into llama.cpp; no root or external app is needed.
# The GitHub workflow installs *host* glslc and SPIRV-Headers for shader generation,
# while Vulkan_LIBRARY/Vulkan_INCLUDE_DIR point at the Android NDK target sysroot.
if(ANDROID)
    find_program(BABOON_GLSLC NAMES glslc NO_CMAKE_FIND_ROOT_PATH REQUIRED)
    set(Vulkan_GLSLC_EXECUTABLE "${BABOON_GLSLC}" CACHE FILEPATH "Host GLSL compiler" FORCE)
    find_library(BABOON_VULKAN_LIBRARY NAMES vulkan REQUIRED)
    set(Vulkan_LIBRARY "${BABOON_VULKAN_LIBRARY}" CACHE FILEPATH "NDK Vulkan loader" FORCE)
    set(Vulkan_INCLUDE_DIR "${CMAKE_SYSROOT}/usr/include" CACHE PATH "NDK Vulkan headers" FORCE)
    if(DEFINED ENV{BABOON_SPIRV_HEADERS_DIR} AND NOT "$ENV{BABOON_SPIRV_HEADERS_DIR}" STREQUAL "")
        set(SPIRV-Headers_DIR "$ENV{BABOON_SPIRV_HEADERS_DIR}" CACHE PATH "Host SPIR-V package" FORCE)
    endif()
    set(GGML_VULKAN ON CACHE BOOL "Enable GPU Vulkan backend" FORCE)
else()
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
endif()
set(GGML_BACKEND_DL OFF CACHE BOOL "Embed Vulkan and CPU backends" FORCE)
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

# SPIR-V headers are header-only host build dependencies. Do not include the
# host system include directory wholesale in an Android cross compilation.
if(ANDROID AND TARGET ggml-vulkan)
    # Android NDK ships the Vulkan C API but not the Vulkan-Hpp C++ wrapper.
    # The pinned ggml-vulkan backend requires <vulkan/vulkan.hpp>.
    # Use the entire matching set of host Vulkan headers for compilation,
    # copied into an isolated directory so /usr/include is NOT added to the
    # Android target's search path. Linking still uses Android NDK libvulkan.
    if(NOT EXISTS "/usr/include/vulkan/vulkan.hpp")
        message(FATAL_ERROR "Vulkan-Hpp is missing on the build host; install libvulkan-dev")
    endif()
    set(BABOON_VULKAN_HEADERS "${CMAKE_CURRENT_BINARY_DIR}/baboon-vulkan-headers")
    file(MAKE_DIRECTORY "${BABOON_VULKAN_HEADERS}")
    file(COPY "/usr/include/vulkan" DESTINATION "${BABOON_VULKAN_HEADERS}")
    if(EXISTS "/usr/include/vk_video")
        file(COPY "/usr/include/vk_video" DESTINATION "${BABOON_VULKAN_HEADERS}")
    endif()
    target_include_directories(ggml-vulkan BEFORE PRIVATE "${BABOON_VULKAN_HEADERS}")

    if(EXISTS "/usr/include/spirv/unified1/spirv.hpp")
        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/baboon-spirv-headers")
        file(COPY "/usr/include/spirv" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/baboon-spirv-headers")
        target_include_directories(ggml-vulkan PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/baboon-spirv-headers")
    else()
        message(FATAL_ERROR "SPIR-V headers missing. Install spirv-headers on GitHub runner.")
    endif()
endif()
