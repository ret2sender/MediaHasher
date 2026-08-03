# MediaHash - multi-algorithm file hashing core library.
#
# Copyright (c) 2026 Etienne Fleurant
# SPDX-License-Identifier: MIT
#
# Part of the MediaHash core library, released under the MIT License.
# See MediaHash/LICENSE for the full license text.

add_executable(mediahash
        main.cpp
)

# ---------------------------------------------------------------------------
# Version
#
# PROJECT_VERSION here is the *core library* version (declared in
# MediaHash/CMakeLists.txt), deliberately independent of the MediaHasher
# application version - the CLI ships the library, so it reports the
# library's version.
# ---------------------------------------------------------------------------
target_compile_definitions(mediahash PRIVATE
        MEDIAHASH_VERSION_STR="${PROJECT_VERSION}"
)

# Windows: a VERSIONINFO-only resource so mediahash.exe carries the core
# version in Explorer's Properties -> Details. No enable_language(RC)
# needed: CMake auto-enables RC on Windows/MSVC when an .rc source is
# added to a target (the application target relies on the same behavior).
if(WIN32)
    configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/mediahash.rc.in"
            "${CMAKE_CURRENT_BINARY_DIR}/mediahash.rc"
            @ONLY
    )
    target_sources(mediahash PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/mediahash.rc")
endif()

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
target_link_libraries(mediahash PRIVATE MediaHash)
target_compile_features(mediahash PRIVATE cxx_std_20)
