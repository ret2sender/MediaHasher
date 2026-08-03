# MediaHash - multi-algorithm file hashing core library.
#
# Copyright (c) 2026 Etienne Fleurant
# SPDX-License-Identifier: MIT
#
# Part of the MediaHash core library, released under the MIT License.
# See MediaHash/LICENSE for the full license text.

add_executable(mediahash_tests
        main.cpp
)

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
target_link_libraries(mediahash_tests PRIVATE MediaHash)
target_compile_features(mediahash_tests PRIVATE cxx_std_20)

add_test(NAME MediaHashTests COMMAND mediahash_tests)
