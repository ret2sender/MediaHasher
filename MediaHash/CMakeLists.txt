# MediaHash - multi-algorithm file hashing core library.
#
# Copyright (c) 2026 Etienne Fleurant
# SPDX-License-Identifier: MIT
#
# Part of the MediaHash core library, released under the MIT License.
# See MediaHash/LICENSE for the full license text.

cmake_minimum_required(VERSION 4.1)
project(MediaHash VERSION 1.1.0 LANGUAGES CXX)

# ---------------------------------------------------------------------------
# Global C++ standard
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# OpenSSL - Homebrew (Apple Silicon) hint
#
# Homebrew intentionally does not symlink OpenSSL into /usr/local to avoid
# clashing with Apple's LibreSSL. We tell CMake exactly where to look.
#
# Apple Silicon : /opt/homebrew/opt/openssl@3
# Intel Mac     : /usr/local/opt/openssl@3  (change if needed)
#
# You can override this at configure time:
#   cmake -DOPENSSL_ROOT_DIR=$(brew --prefix openssl@3) ..
# ---------------------------------------------------------------------------
if(APPLE AND NOT DEFINED OPENSSL_ROOT_DIR)
    set(OPENSSL_ROOT_DIR "/opt/homebrew/opt/openssl@3")
endif()

find_package(OpenSSL 3.0 REQUIRED)

message(STATUS "OpenSSL version : ${OPENSSL_VERSION}")
message(STATUS "OpenSSL include : ${OPENSSL_INCLUDE_DIR}")
message(STATUS "OpenSSL libs    : ${OPENSSL_LIBRARIES}")

# ---------------------------------------------------------------------------
# BLAKE3 + xxHash
#
# macOS   : brew install blake3 xxhash
# Windows : Conan packages blake3/x.y.z and xxhash/x.y.z (CMakeDeps)
#
# The CMake package/target names differ between the official upstream
# configs, Conan-generated configs, and Homebrew installs (xxHash's
# Homebrew formula ships no CMake config at all - pkg-config only), so
# each dependency is resolved in three steps: try the known config
# names, adopt whichever imported target appeared, and fall back to a
# manual find_path/find_library imported target. The resolved target
# name is exported in a MEDIAHASH_*_TARGET variable consumed by
# Sources/MediaHash/CMakeLists.txt.
# ---------------------------------------------------------------------------

# --- BLAKE3 ----------------------------------------------------------------
set(MEDIAHASH_BLAKE3_TARGET "")

find_package(blake3 CONFIG QUIET)   # Upstream + Homebrew config name.
if(NOT TARGET BLAKE3::blake3 AND NOT TARGET blake3::blake3)
    find_package(BLAKE3 CONFIG QUIET) # Some Conan generations use this name.
endif()

if(TARGET BLAKE3::blake3)
    set(MEDIAHASH_BLAKE3_TARGET BLAKE3::blake3)
elseif(TARGET blake3::blake3)
    set(MEDIAHASH_BLAKE3_TARGET blake3::blake3)
else()
    find_path(BLAKE3_INCLUDE_DIR blake3.h
            HINTS /opt/homebrew/include /usr/local/include
    )
    find_library(BLAKE3_LIBRARY NAMES blake3
            HINTS /opt/homebrew/lib /usr/local/lib
    )
    if(BLAKE3_INCLUDE_DIR AND BLAKE3_LIBRARY)
        add_library(MediaHashDeps::blake3 UNKNOWN IMPORTED)
        set_target_properties(MediaHashDeps::blake3 PROPERTIES
                IMPORTED_LOCATION "${BLAKE3_LIBRARY}"
                INTERFACE_INCLUDE_DIRECTORIES "${BLAKE3_INCLUDE_DIR}"
        )
        set(MEDIAHASH_BLAKE3_TARGET MediaHashDeps::blake3)
    endif()
endif()

if(NOT MEDIAHASH_BLAKE3_TARGET)
    message(FATAL_ERROR "BLAKE3 not found. "
            "macOS: brew install blake3 - Windows: add blake3 to the Conan profile.")
endif()
message(STATUS "BLAKE3 target   : ${MEDIAHASH_BLAKE3_TARGET}")

# --- xxHash ----------------------------------------------------------------
set(MEDIAHASH_XXHASH_TARGET "")

find_package(xxHash CONFIG QUIET)   # Upstream cmake_unofficial + Conan name.
if(NOT TARGET xxHash::xxhash AND NOT TARGET xxhash::xxhash)
    find_package(xxhash CONFIG QUIET)
endif()

if(TARGET xxHash::xxhash)
    set(MEDIAHASH_XXHASH_TARGET xxHash::xxhash)
elseif(TARGET xxhash::xxhash)
    set(MEDIAHASH_XXHASH_TARGET xxhash::xxhash)
else()
    # Homebrew's xxhash formula installs headers + dylib without a CMake
    # config, so a manual imported target is the expected path on macOS.
    find_path(XXHASH_INCLUDE_DIR xxhash.h
            HINTS /opt/homebrew/include /usr/local/include
    )
    find_library(XXHASH_LIBRARY NAMES xxhash xxHash
            HINTS /opt/homebrew/lib /usr/local/lib
    )
    if(XXHASH_INCLUDE_DIR AND XXHASH_LIBRARY)
        add_library(MediaHashDeps::xxhash UNKNOWN IMPORTED)
        set_target_properties(MediaHashDeps::xxhash PROPERTIES
                IMPORTED_LOCATION "${XXHASH_LIBRARY}"
                INTERFACE_INCLUDE_DIRECTORIES "${XXHASH_INCLUDE_DIR}"
        )
        set(MEDIAHASH_XXHASH_TARGET MediaHashDeps::xxhash)
    endif()
endif()

if(NOT MEDIAHASH_XXHASH_TARGET)
    message(FATAL_ERROR "xxHash not found. "
            "macOS: brew install xxhash - Windows: add xxhash to the Conan profile.")
endif()
message(STATUS "xxHash target   : ${MEDIAHASH_XXHASH_TARGET}")

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
add_subdirectory(Sources/MediaHash)
add_subdirectory(Sources/MediaHashCLI)

# ---------------------------------------------------------------------------
# Tests
#
# Built only when MediaHash is the top-level project (opened standalone in
# the IDE), so app builds pulling this in via add_subdirectory stay lean.
# Override with -DMEDIAHASH_BUILD_TESTS=ON/OFF.
# ---------------------------------------------------------------------------
option(MEDIAHASH_BUILD_TESTS "Build MediaHash unit tests" ${PROJECT_IS_TOP_LEVEL})

if(MEDIAHASH_BUILD_TESTS)
    enable_testing()
    add_subdirectory(Sources/MediaHashTests)
endif()
