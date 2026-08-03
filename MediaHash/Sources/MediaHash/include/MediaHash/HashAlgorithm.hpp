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

/// @file HashAlgorithm.hpp
/// @brief Enumeration of the supported hash algorithms and their metadata.
///
/// Single source of truth for algorithm identity across the whole
/// application: display names (Jobs Log, companion file headers), settings
/// keys (settings.yml values), companion file extensions, and digest sizes
/// all derive from the helpers in this header. Header-only and Qt-free so
/// the UI layer, the core library, the CLI, and the tests all share it.

// C++ 23 note: Replace the std includes below by import std
#include <array>
#include <cstddef> // NOLINT - Used (std::size_t)
#include <optional>
#include <string_view>

namespace MediaHash {

// ---------------------------------------------------------------------------
// HashAlgorithm
// ---------------------------------------------------------------------------

/// @brief Hash algorithms supported by FileHasher and ChecksumFile.
///
/// BLAKE3 is the application default: cryptographically secure and much
/// faster than the SHA family on large media files. XXH3 and XXH128 are
/// non-cryptographic and even faster, suitable for pure corruption
/// detection. SHA-256 is offered for interoperability with external
/// tooling; SHA-1 remains supported so companion files written by earlier
/// versions stay verifiable.
enum class HashAlgorithm {
    Blake3, ///< BLAKE3, 256-bit digest (64 hex characters). Default.
    Xxh3,   ///< XXH3 64-bit digest (16 hex characters).
    Xxh128, ///< XXH3 128-bit digest (32 hex characters).
    Sha256, ///< SHA-256, 256-bit digest (64 hex characters).
    Sha1    ///< SHA-1, 160-bit digest (40 hex characters). Legacy.
};

/// @brief Every supported algorithm, in canonical (UI and discovery) order.
inline constexpr std::array<HashAlgorithm, 5> AllAlgorithms{
    HashAlgorithm::Blake3,
    HashAlgorithm::Xxh3,
    HashAlgorithm::Xxh128,
    HashAlgorithm::Sha256,
    HashAlgorithm::Sha1,
};

// ---------------------------------------------------------------------------
// Metadata helpers
// ---------------------------------------------------------------------------

/// @brief Human-readable display name, also used in companion file headers.
/// @param algorithm The algorithm to query.
/// @return Display name, e.g. "BLAKE3" or "SHA-256".
[[nodiscard]] constexpr std::string_view name(const HashAlgorithm algorithm) noexcept {
    switch (algorithm) {
        case HashAlgorithm::Blake3: return "BLAKE3";
        case HashAlgorithm::Xxh3:   return "XXH3";
        case HashAlgorithm::Xxh128: return "XXH128";
        case HashAlgorithm::Sha256: return "SHA-256";
        case HashAlgorithm::Sha1:   return "SHA-1";
    }
    return {};
}

/// @brief Stable lowercase identifier used as the settings.yml value.
/// @param algorithm The algorithm to query.
/// @return Settings key, e.g. "blake3" or "sha256".
// CLion global DFA analyzes one target at a time; the callers of this
// public API live in the ui and test targets, so DFA wrongly reports all calls
// as unreachable when resolving within the core library target.
// NOLINTNEXTLINE
[[nodiscard]] constexpr std::string_view key(const HashAlgorithm algorithm) noexcept {
    switch (algorithm) {
        case HashAlgorithm::Blake3: return "blake3";
        case HashAlgorithm::Xxh3:   return "xxh3";
        case HashAlgorithm::Xxh128: return "xxh128";
        case HashAlgorithm::Sha256: return "sha256";
        case HashAlgorithm::Sha1:   return "sha1";
    }
    return {};
}

/// @brief Companion file extension, doubling as the algorithm identifier
///        during sidecar discovery (see ChecksumFile::existingAlgorithms).
/// @param algorithm The algorithm to query.
/// @return Extension including the leading dot, e.g. ".blake3".
[[nodiscard]] constexpr std::string_view extension(const HashAlgorithm algorithm) noexcept {
    switch (algorithm) {
        case HashAlgorithm::Blake3: return ".blake3";
        case HashAlgorithm::Xxh3:   return ".xxh3";
        case HashAlgorithm::Xxh128: return ".xxh128";
        case HashAlgorithm::Sha256: return ".sha256";
        case HashAlgorithm::Sha1:   return ".sha1";
    }
    return {};
}

/// @brief Length of the lowercase hex digest string for the algorithm.
/// @param algorithm The algorithm to query.
/// @return Digest length in hex characters (e.g. 64 for BLAKE3).
[[nodiscard]] constexpr std::size_t digestHexLength(const HashAlgorithm algorithm) noexcept {
    switch (algorithm) {
        case HashAlgorithm::Blake3: return 64;
        case HashAlgorithm::Xxh3:   return 16;
        case HashAlgorithm::Xxh128: return 32;
        case HashAlgorithm::Sha256: return 64;
        case HashAlgorithm::Sha1:   return 40;
    }
    return 0;
}

/// @brief Resolves a settings key back to its algorithm.
/// @param algorithmKey Lowercase identifier as stored in settings.yml.
/// @return The matching algorithm, or @c std::nullopt if unrecognized.
[[nodiscard]] constexpr std::optional<HashAlgorithm> algorithmFromKey(
    const std::string_view algorithmKey) noexcept {
    for (const HashAlgorithm algorithm : AllAlgorithms) {
        if (key(algorithm) == algorithmKey)
            return algorithm;
    }
    return std::nullopt;
}

} // namespace MediaHash
