/*
 * MediaHash - multi-algorithm file hashing core library.
 *
 * Copyright (c) 2026 Etienne Fleurant
 * SPDX-License-Identifier: MIT
 *
 * Part of the MediaHash core library, released under the MIT License.
 * See MediaHash/LICENSE for the full license text.
 */

/// @file main.cpp
/// @brief MediaHashCLI - companion command-line application.
///
/// Computes the hash of a single file and prints the result.
/// Usage: @c mediahash /path/to/file.mkv [algorithm] [chunkSizeMiB]
/// where @c algorithm is one of blake3 (default), xxh3, xxh128, sha256, sha1.
/// @c mediahash @c --version prints the core library version and exits.

#include "MediaHash/MediaHash.hpp"

// Defined by the build system from the core library's PROJECT_VERSION
// (see MediaHashCLI/CMakeLists.txt). The fallback keeps out-of-tree
// builds compiling while making the misconfiguration obvious.
#ifndef MEDIAHASH_VERSION_STR
#define MEDIAHASH_VERSION_STR "0.0.0-unversioned"
#endif

// C++ 23 note: Replace the std includes below by import std module.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string_view>

int main(int argc, char* argv[]) { // NOLINT - No const on main argc
    if (argc < 2) {
        std::fputs("Usage: mediahash /path/to/file.mkv [algorithm] [chunkSizeMiB]\n"
                   "       mediahash --version\n"
                   "  algorithm: blake3 (default) | xxh3 | xxh128 | sha256 | sha1\n",
                   stderr);
        return EXIT_FAILURE;
    }

    // Version query - reports the core library version, which evolves
    // independently of the MediaHasher application version.
    if (std::string_view{argv[1]} == "--version") {
        std::puts("mediahash " MEDIAHASH_VERSION_STR);
        return EXIT_SUCCESS;
    }

    const std::filesystem::path filePath{argv[1]};

    // Optional algorithm (default BLAKE3).
    MediaHash::HashAlgorithm algorithm = MediaHash::HashAlgorithm::Blake3;
    if (argc >= 3) {
        const auto parsed = MediaHash::algorithmFromKey(argv[2]); // NOLINT - used directly in if branch
        if (!parsed.has_value()) {
            std::fprintf(stderr,
                         "Unknown algorithm '%s'. "
                         "Expected blake3, xxh3, xxh128, sha256, or sha1.\n",
                         argv[2]);
            return EXIT_FAILURE;
        }
        algorithm = parsed.value();
    }

    // Optional chunk size in MiB (default 1) - mainly for benchmarking
    // I/O chunk sizes against different storage types.
    std::size_t chunkSize = 1024 * 1024;
    if (argc >= 4) {
        const long chunkMiB = std::strtol(argv[3], nullptr, 10);
        if (chunkMiB <= 0 || chunkMiB > 1024) {
            std::fputs("chunkSizeMiB must be between 1 and 1024.\n", stderr);
            return EXIT_FAILURE;
        }
        chunkSize = static_cast<std::size_t>(chunkMiB) * 1024 * 1024;
    }

    try {
        // Throttle progress printing - flushing stdout once per chunk
        // (every MiB) is wasteful on fast storage. A final 100% line is
        // printed unconditionally after hashing completes.
        constexpr auto printInterval = std::chrono::milliseconds(50);
        auto lastPrint = std::chrono::steady_clock::now() - printInterval;

        // Ignoring struct binding warning, since checksum.hex is more
        // descriptive than a bare hex.
        const auto checksum = MediaHash::FileHasher::hash( // NOLINT
            filePath,
            algorithm,
            chunkSize,
            /*isCanceled=*/nullptr,
            /*onProgress=*/
            [&lastPrint, printInterval](const std::int64_t bytesRead,
                                        const std::int64_t totalBytes) {
                const auto now = std::chrono::steady_clock::now();
                if (now - lastPrint < printInterval)
                    return;
                lastPrint = now;

                const double pct = static_cast<double>(bytesRead)
                                   / static_cast<double>(totalBytes) * 100.0;
                std::printf("\rHashing progress : %.1f%%", pct);
                std::fflush(stdout);
            });

        const std::string_view algorithmName = MediaHash::name(algorithm);
        std::printf("\rHashing progress : 100.0%%\n");
        std::printf("%.*s: %s\n",
                    static_cast<int>(algorithmName.size()), algorithmName.data(),
                    checksum.hex.c_str());

    } catch (const MediaHash::CancellationError& e) {
        std::fprintf(stderr, "\nCanceled: %s\n", e.what());
        return EXIT_FAILURE;

    } catch (const std::exception& e) {
        std::fprintf(stderr, "Error: %s\n", e.what());
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
