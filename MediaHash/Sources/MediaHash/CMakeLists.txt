# MediaHash - multi-algorithm file hashing core library.
#
# Copyright (c) 2026 Etienne Fleurant
# SPDX-License-Identifier: MIT
#
# Part of the MediaHash core library, released under the MIT License.
# See MediaHash/LICENSE for the full license text.

add_library(MediaHash STATIC
        ChecksumFile.cpp
        MediaHash.cpp
)

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

# Public include directory. Consumers get this automatically via target linkage.
target_include_directories(MediaHash
        PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

# OpenSSL::Crypto is PUBLIC so any target linking MediaHash also gets it.
# BLAKE3 and xxHash are PRIVATE: no public header exposes their types, and
# CMake still propagates them to consumers of this static library through
# $<LINK_ONLY:...> for the final link. The MEDIAHASH_*_TARGET variables are
# resolved in the top-level CMakeLists.txt (config-name differences between
# Homebrew, Conan, and upstream are handled there).
target_link_libraries(MediaHash
        PUBLIC OpenSSL::Crypto
        PRIVATE
        ${MEDIAHASH_BLAKE3_TARGET}
        ${MEDIAHASH_XXHASH_TARGET}
)

target_compile_features(MediaHash PUBLIC cxx_std_20)

# Warnings (errors in Debug builds only).
target_compile_options(MediaHash PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:
        -Wall -Wextra -Wpedantic
        $<$<CONFIG:Debug>:-Werror>
        >
)
