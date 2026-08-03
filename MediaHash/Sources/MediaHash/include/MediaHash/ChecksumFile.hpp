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

/// @file ChecksumFile.hpp
/// @brief Reads and writes algorithm-named companion files for integrity
///        verification.
///
/// A companion file sits alongside the original and contains the file
/// name together with a "<ALGORITHM> hash : <hex>" line that can be used
/// for later verification. The companion extension encodes the algorithm
/// (.blake3, .xxh3, .xxh128, .sha256, .sha1), so discovering which formats already
/// exist for a file is a pure extension lookup. The path and algorithm
/// are immutable after construction - create a new instance for a
/// different file or algorithm.

// C++ 23 note: Replace the std includes below by import std
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "HashAlgorithm.hpp"

namespace MediaHash {

// ---------------------------------------------------------------------------
// ChecksumFile
// ---------------------------------------------------------------------------

/// @brief Reads and writes algorithm-named companion files for a given
///        input file.
///
/// Pure C++ (no Qt dependency) so it can live in the core library alongside
/// FileHasher. The companion file format is:
/// @code
///   File name : <original filename>
///   <ALGORITHM> hash : <lowercase hex digest>
/// @endcode
/// where @c <ALGORITHM> is the display name from HashAlgorithm.hpp
/// ("BLAKE3", "XXH3", "XXH128", "SHA-256", "SHA-1"). The SHA-1 layout is byte
/// identical to the legacy .sha1 format, so files written by earlier
/// versions remain readable.
class ChecksumFile {
public:
    /// @brief Constructs a ChecksumFile for the given original file and
    ///        algorithm.
    ///
    /// @param path      Path to the original file (not the companion file).
    /// @param algorithm Algorithm this companion represents; determines the
    ///                  companion extension and the hash line prefix.
    /// @throws std::invalid_argument If @p path is empty.
    explicit ChecksumFile(std::filesystem::path path, HashAlgorithm algorithm);

    /// @brief Algorithm this companion represents.
    [[nodiscard]] HashAlgorithm algorithm() const noexcept;

    /// @brief Derived path to the companion file (e.g. movie.blake3).
    [[nodiscard]] std::filesystem::path companionPath() const;

    /// @brief Path to the original file associated with this companion.
    [[nodiscard]] const std::filesystem::path& path() const noexcept;

    /// @brief Reads the stored hash from the companion file.
    ///
    /// @return The extracted hash hex string, or @c std::nullopt if the
    ///         companion file does not exist.
    /// @throws std::runtime_error If the companion file exists but contains
    ///                            no recognizable hash line for this
    ///                            algorithm.
    [[nodiscard]] std::optional<std::string> read() const;

    /// @brief Deletes the companion file if it exists.
    ///
    /// Used by the hash file conversion flow to clean up stale companions
    /// after the replacement has been written. A missing companion is a
    /// no-op.
    ///
    /// @throws std::runtime_error If the companion file exists but cannot
    ///                            be removed.
    void remove() const;

    /// @brief Writes a companion file for the original file.
    ///
    /// The generated file contains the original file name and the provided
    /// checksum and can be used for later integrity checks.
    ///
    /// @param checksum Checksum hex string to store.
    /// @throws std::runtime_error If the companion file cannot be opened
    ///                            for writing.
    void write(std::string_view checksum) const;

    /// @brief Discovers which algorithms already have a companion file for
    ///        @p path.
    ///
    /// Pure extension lookup against the known set - no file contents are
    /// read. Results follow the canonical AllAlgorithms order, so callers
    /// get deterministic output.
    ///
    /// @param path Path to the original file (not a companion file).
    /// @return Algorithms whose companion file exists alongside @p path.
    [[nodiscard]] static std::vector<HashAlgorithm> existingAlgorithms(
        const std::filesystem::path& path);

private:
    HashAlgorithm m_algorithm;
    std::filesystem::path m_path;
};

} // namespace MediaHash
