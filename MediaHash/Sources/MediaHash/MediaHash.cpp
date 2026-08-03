/*
 * MediaHash - multi-algorithm file hashing core library.
 *
 * Copyright (c) 2026 Etienne Fleurant
 * SPDX-License-Identifier: MIT
 *
 * Part of the MediaHash core library, released under the MIT License.
 * See MediaHash/LICENSE for the full license text.
 */

/// @file MediaHash.cpp
/// @brief Multi-algorithm file hashing (BLAKE3, XXH3, XXH128, SHA-256, SHA-1).
///
/// A small internal Digester interface hides the three back-end APIs:
/// the official BLAKE3 C library, xxHash's streaming XXH3 API, and the
/// OpenSSL EVP interface for the SHA family. hashMulti() drives any number of
/// digesters from a single read loop, so converting companion files
/// (verify with the old algorithm + produce the new digest) costs one
/// pass over the media file.
///
/// xxHash digests are rendered through XXH64_canonicalFromHash /
/// XXH128_canonicalFromHash, so the hex strings match the output of the
/// reference `xxhsum` tool by construction.

#include "MediaHash/MediaHash.hpp"

// C++ 23 note: Replace the std includes below by import std
#include <array>
#include <format>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <vector>

// Hashing back-end headers.
#include <blake3.h>
#include <openssl/evp.h> // EVP digest API + EVP_MAX_MD_SIZE
#include <xxhash.h>

namespace MediaHash {

namespace detail {

// ---------------------------------------------------------------------------
// Hex conversion
// ---------------------------------------------------------------------------

/// @brief Converts raw digest bytes to a lowercase hex string.
/// @param data Pointer to the first digest byte.
/// @param size Number of digest bytes.
/// @return Lowercase hexadecimal string of length 2 * @p size.
[[nodiscard]] std::string toHex(const unsigned char* data, const std::size_t size) {
    std::string hex;
    hex.reserve(size * 2);
    for (std::size_t i = 0; i < size; ++i)
        hex += std::format("{:02x}", data[i]);
    return hex;
}

// ---------------------------------------------------------------------------
// Digester interface
// ---------------------------------------------------------------------------

/// @brief Streaming digest context, one per algorithm per hashed file.
///
/// hashMulti() owns a set of these and feeds every file chunk into each of
/// them, which is what makes single-pass multi-digest hashing possible.
class Digester {
public:
    virtual ~Digester() = default;

    Digester() = default;
    Digester(const Digester&) = delete;
    Digester& operator=(const Digester&) = delete;

    /// @brief Feeds a chunk of file data into the digest context.
    /// @param data Pointer to the first byte of the chunk.
    /// @param size Chunk size in bytes.
    virtual void update(const unsigned char* data, std::size_t size) = 0;

    /// @brief Finalizes the digest and returns it as lowercase hex.
    ///
    /// Must be called exactly once, after the last update().
    ///
    /// @return Lowercase hexadecimal digest string.
    [[nodiscard]] virtual std::string finalizeHex() = 0;
};

// ---------------------------------------------------------------------------
// SHA family (OpenSSL EVP)
// ---------------------------------------------------------------------------

/// @brief Custom deleter so we can use std::unique_ptr with EVP_MD_CTX.
///
/// Called automatically when the unique_ptr goes out of scope,
/// ensuring the OpenSSL context is freed even on exception paths.
struct EvpMdCtxDeleter {
    void operator()(EVP_MD_CTX* ctx) const noexcept { EVP_MD_CTX_free(ctx); }
};

/// @brief Alias for a std::unique_ptr managing an EVP_MD_CTX with RAII cleanup.
using EvpMdCtxPtr = std::unique_ptr<EVP_MD_CTX, EvpMdCtxDeleter>;

/// @brief Digester backed by the OpenSSL EVP API (OpenSSL 3.x).
///
/// Covers SHA-1 and SHA-256; any other EVP message digest can be plugged
/// in by passing the corresponding EVP_MD to the constructor.
class EvpDigester final : public Digester {
public:
    /// @brief Creates an initialized EVP context for the given digest.
    /// @param md The OpenSSL message digest, e.g. EVP_sha1() or EVP_sha256().
    /// @throws std::runtime_error If context allocation or initialization fails.
    explicit EvpDigester(const EVP_MD* md) : m_ctx(EVP_MD_CTX_new()) {
        if (!m_ctx)
            throw std::runtime_error("OpenSSL: EVP_MD_CTX_new() failed.");

        if (EVP_DigestInit_ex(m_ctx.get(), md, /*engine=*/nullptr) != 1)
            throw std::runtime_error("OpenSSL: EVP_DigestInit_ex() failed.");
    }

    void update(const unsigned char* data, const std::size_t size) override {
        if (EVP_DigestUpdate(m_ctx.get(), data, size) != 1)
            throw std::runtime_error("OpenSSL: EVP_DigestUpdate() failed.");
    }

    [[nodiscard]] std::string finalizeHex() override {
        std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
        unsigned int digestLen = 0;

        if (EVP_DigestFinal_ex(m_ctx.get(), digest.data(), &digestLen) != 1)
            throw std::runtime_error("OpenSSL: EVP_DigestFinal_ex() failed.");

        return toHex(digest.data(), digestLen);
    }

private:
    EvpMdCtxPtr m_ctx;
};

// ---------------------------------------------------------------------------
// BLAKE3 (official C library)
// ---------------------------------------------------------------------------

/// @brief BLAKE3 digester backed by the official C implementation.
///
/// blake3_hasher is a plain struct with no heap allocation, so no RAII
/// wrapper is needed.
class Blake3Digester final : public Digester {
public:
    Blake3Digester() {
        blake3_hasher_init(&m_hasher);
    }

    void update(const unsigned char* data, const std::size_t size) override {
        blake3_hasher_update(&m_hasher, data, size);
    }

    [[nodiscard]] std::string finalizeHex() override {
        std::array<unsigned char, BLAKE3_OUT_LEN> digest{};
        blake3_hasher_finalize(&m_hasher, digest.data(), digest.size());
        return toHex(digest.data(), digest.size());
    }

private:
    blake3_hasher m_hasher{};
};

// ---------------------------------------------------------------------------
// XXH3 / XXH128 (xxHash streaming API)
// ---------------------------------------------------------------------------

/// @brief Custom deleter so we can use std::unique_ptr with XXH3_state_t.
///
/// The xxHash documentation mandates XXH3_createState()/XXH3_freeState()
/// for ABI-safe streaming state management.
struct Xxh3StateDeleter {
    void operator()(XXH3_state_t* state) const noexcept { XXH3_freeState(state); }
};

/// @brief Alias for a std::unique_ptr managing an XXH3_state_t with RAII cleanup.
using Xxh3StatePtr = std::unique_ptr<XXH3_state_t, Xxh3StateDeleter>;

/// @brief Allocates and returns a fresh XXH3 streaming state.
/// @throws std::runtime_error If state allocation fails.
[[nodiscard]] Xxh3StatePtr makeXxh3State() {
    Xxh3StatePtr state{XXH3_createState()};
    if (!state)
        throw std::runtime_error("xxHash: XXH3_createState() failed.");
    return state;
}

/// @brief XXH3 64-bit digester (streaming, seed 0).
class Xxh3Digester final : public Digester {
public:
    Xxh3Digester() : m_state(makeXxh3State()) {
        if (XXH3_64bits_reset(m_state.get()) != XXH_OK)
            throw std::runtime_error("xxHash: XXH3_64bits_reset() failed.");
    }

    void update(const unsigned char* data, const std::size_t size) override {
        if (XXH3_64bits_update(m_state.get(), data, size) != XXH_OK)
            throw std::runtime_error("xxHash: XXH3_64bits_update() failed.");
    }

    [[nodiscard]] std::string finalizeHex() override {
        const XXH64_hash_t hash = XXH3_64bits_digest(m_state.get());

        // Canonical (big-endian) byte order - matches xxhsum output.
        XXH64_canonical_t canonical{};
        XXH64_canonicalFromHash(&canonical, hash);
        return toHex(canonical.digest, sizeof(canonical.digest));
    }

private:
    Xxh3StatePtr m_state;
};

/// @brief XXH3 128-bit digester (streaming, seed 0).
class Xxh128Digester final : public Digester {
public:
    Xxh128Digester() : m_state(makeXxh3State()) {
        if (XXH3_128bits_reset(m_state.get()) != XXH_OK)
            throw std::runtime_error("xxHash: XXH3_128bits_reset() failed.");
    }

    void update(const unsigned char* data, const std::size_t size) override {
        if (XXH3_128bits_update(m_state.get(), data, size) != XXH_OK)
            throw std::runtime_error("xxHash: XXH3_128bits_update() failed.");
    }

    [[nodiscard]] std::string finalizeHex() override {
        const XXH128_hash_t hash = XXH3_128bits_digest(m_state.get());

        // Canonical (big-endian) byte order - matches xxhsum -H2 output.
        XXH128_canonical_t canonical{};
        XXH128_canonicalFromHash(&canonical, hash);
        return toHex(canonical.digest, sizeof(canonical.digest));
    }

private:
    Xxh3StatePtr m_state;
};

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// @brief Creates an initialized digester for the given algorithm.
/// @param algorithm The algorithm to create a digest context for.
/// @return An owning pointer to a ready-to-use Digester.
/// @throws std::runtime_error If back-end context initialization fails.
[[nodiscard]] std::unique_ptr<Digester> makeDigester(const HashAlgorithm algorithm) {
    switch (algorithm) {
        case HashAlgorithm::Blake3: return std::make_unique<Blake3Digester>();
        case HashAlgorithm::Xxh3:   return std::make_unique<Xxh3Digester>();
        case HashAlgorithm::Xxh128: return std::make_unique<Xxh128Digester>();
        case HashAlgorithm::Sha256: return std::make_unique<EvpDigester>(EVP_sha256());
        case HashAlgorithm::Sha1:   return std::make_unique<EvpDigester>(EVP_sha1());
    }
    throw std::runtime_error("Unknown hash algorithm.");
}

} // namespace detail

namespace {

/// Converts a path to a UTF-8 std::string for error messages.
/// std::filesystem::path::string() converts to the ANSI codepage on MSVC,
/// which garbles non-ASCII characters and can even throw for characters
/// the codepage cannot represent; u8string() is UTF-8 on every platform.
/// (Deliberately duplicated in ChecksumFile.cpp - a shared header for four
/// lines is not worth the coupling.)
std::string pathToUtf8(const std::filesystem::path& path) {
    const std::u8string u8 = path.u8string();
    return {u8.begin(), u8.end()};
}

} // namespace

// ---------------------------------------------------------------------------
// FileHasher
// ---------------------------------------------------------------------------

Checksum FileHasher::hash(
    const std::filesystem::path& path,
    const HashAlgorithm algorithm,
    const std::size_t chunkSize,
    const CancelCallback& isCanceled,
    const ProgressCallback& onProgress) {
    return hashMulti(path, {algorithm}, chunkSize, isCanceled, onProgress).front();
}

std::vector<Checksum> FileHasher::hashMulti(
    const std::filesystem::path& path,
    const std::vector<HashAlgorithm>& algorithms,
    const std::size_t chunkSize,
    const CancelCallback& isCanceled,
    const ProgressCallback& onProgress) {
    if (chunkSize == 0)
        throw std::invalid_argument("chunkSize must be > 0");
    if (algorithms.empty())
        throw std::invalid_argument("algorithms must not be empty");

    // Resolve file size for progress reporting (-1 if unavailable).
    std::int64_t totalBytes = -1;
    std::error_code ec;
    const auto size = std::filesystem::file_size(path, ec);
    if (!ec)
        totalBytes = static_cast<std::int64_t>(size);

    // Open file in binary mode.
    std::ifstream file(path, std::ios::binary);
    if (!file)
        throw std::runtime_error("Cannot open file: " + pathToUtf8(path));

    // One digest context per requested algorithm (RAII - freed automatically).
    std::vector<std::unique_ptr<detail::Digester>> digesters;
    digesters.reserve(algorithms.size());
    for (const HashAlgorithm algorithm : algorithms)
        digesters.push_back(detail::makeDigester(algorithm));

    std::vector<unsigned char> buffer(chunkSize);
    std::int64_t bytesRead = 0;

    while (file) {
        // Check for cancellation before each chunk.
        if (isCanceled && isCanceled())
            throw CancellationError{};

        file.read(reinterpret_cast<char*>(buffer.data()),
                  static_cast<std::streamsize>(chunkSize));
        const auto count = file.gcount();
        if (count == 0)
            break;

        // Feed the chunk into every digest context - this is what makes
        // verify-and-convert a single-read operation.
        for (const auto& digester : digesters)
            digester->update(buffer.data(), static_cast<std::size_t>(count));

        bytesRead += count;

        if (onProgress && totalBytes > 0)
            onProgress(bytesRead, totalBytes);
    }

    if (file.bad())
        throw std::runtime_error("Read error on file: " + pathToUtf8(path));

    // One final 100% progress tick.
    if (onProgress && totalBytes > 0)
        onProgress(bytesRead, totalBytes);

    std::vector<Checksum> results;
    results.reserve(digesters.size());
    for (const auto& digester : digesters)
        results.push_back(Checksum{digester->finalizeHex()});

    return results;
}

} // namespace MediaHash
