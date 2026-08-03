/*
 * MediaHash - multi-algorithm file hashing core library.
 *
 * Copyright (c) 2026 Etienne Fleurant
 * SPDX-License-Identifier: MIT
 *
 * Part of the MediaHash core library, released under the MIT License.
 * See MediaHash/LICENSE for the full license text.
 */

#pragma once

/// @file MediaHash.hpp
/// @brief MediaHash library - C++20 multi-algorithm file hasher.
///
/// The public API is intentionally minimal: FileHasher::hash for a single
/// digest and FileHasher::hashMulti for computing several digests in one
/// read pass, both with optional cancellation and progress callbacks.
/// Back-ends: the official BLAKE3 C library, xxHash (XXH3 / XXH128), and
/// OpenSSL EVP (SHA-256, SHA-1). The back-end choice is an implementation
/// detail invisible to this header.

// C++ 23 note: Replace the std includes below by import std
#include <filesystem>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

#include "HashAlgorithm.hpp"

namespace MediaHash {

// ---------------------------------------------------------------------------
// Checksum
// ---------------------------------------------------------------------------

/// @brief Holds the result of a hash operation as a lowercase hex string.
struct Checksum {
    std::string hex; ///< Lowercase hexadecimal representation of the hash.

    bool operator==(const Checksum&) const noexcept = default;
};

// ---------------------------------------------------------------------------
// Cancellation
// ---------------------------------------------------------------------------

/// @brief Thrown when the caller signals cancellation via the isCanceled callback.
struct CancellationError : std::runtime_error {
    CancellationError() : std::runtime_error("Hashing was canceled.") {
    }
};

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

/// @brief Called periodically during hashing to report progress.
///
/// Only invoked when the total file size is known and positive; files of
/// unknown size are hashed without progress reporting. Progress is byte
/// based, so it is reported once per chunk regardless of how many digest
/// contexts are being fed.
///
/// @param bytesRead  Bytes processed so far.
/// @param totalBytes Total file size in bytes (always > 0 when invoked).
using ProgressCallback = std::function<void(std::int64_t bytesRead,
                                            std::int64_t totalBytes)>;

/// @brief Polled before each chunk. Return @c true to abort.
///
/// When this callback returns @c true, the hasher throws CancellationError.
using CancelCallback = std::function<bool()>;

// ---------------------------------------------------------------------------
// FileHasher
// ---------------------------------------------------------------------------

/// @brief Stateless utility that computes checksums from files.
struct FileHasher {
    /// @brief Computes a single digest of the file at @p path.
    ///
    /// Convenience wrapper around hashMulti() for the one-algorithm case.
    ///
    /// @param path        Path to the file.
    /// @param algorithm   Hash algorithm to use.
    /// @param chunkSize   Read buffer size in bytes (default: 1 MiB).
    /// @param isCanceled Optional cancel predicate, polled each chunk.
    /// @param onProgress  Optional progress callback, called after each chunk
    ///                    when the file size is known (see ProgressCallback).
    /// @return A Checksum whose hex string is the lowercase digest.
    /// @throws CancellationError  If isCanceled returns @c true mid-hash.
    /// @throws std::invalid_argument If chunkSize is 0.
    /// @throws std::runtime_error If the file cannot be opened/read,
    ///                            or if a digest context fails.
    [[nodiscard]] static Checksum hash(
        const std::filesystem::path& path,
        HashAlgorithm algorithm,
        std::size_t chunkSize = 1024 * 1024,
        const CancelCallback& isCanceled = nullptr,
        const ProgressCallback& onProgress = nullptr);

    /// @brief Computes several digests of the file at @p path in one pass.
    ///
    /// Reads the file exactly once and feeds each chunk into every digest
    /// context in parallel. This is the primary optimization for hash file
    /// conversion: verifying an old companion and producing the new digest
    /// costs a single read of the (potentially very large) media file.
    /// Cancellation is checked before each chunk; progress is reported
    /// after each chunk.
    ///
    /// @param path        Path to the file.
    /// @param algorithms  Algorithms to compute. Must not be empty.
    /// @param chunkSize   Read buffer size in bytes (default: 1 MiB).
    /// @param isCanceled Optional cancel predicate, polled each chunk.
    /// @param onProgress  Optional progress callback, called after each chunk
    ///                    when the file size is known (see ProgressCallback).
    /// @return One Checksum per requested algorithm, in the same order as
    ///         @p algorithms.
    /// @throws CancellationError  If isCanceled returns @c true mid-hash.
    /// @throws std::invalid_argument If chunkSize is 0 or @p algorithms is empty.
    /// @throws std::runtime_error If the file cannot be opened/read,
    ///                            or if a digest context fails.
    [[nodiscard]] static std::vector<Checksum> hashMulti(
        const std::filesystem::path& path,
        const std::vector<HashAlgorithm>& algorithms,
        std::size_t chunkSize = 1024 * 1024,
        const CancelCallback& isCanceled = nullptr,
        const ProgressCallback& onProgress = nullptr);
};

} // namespace MediaHash
