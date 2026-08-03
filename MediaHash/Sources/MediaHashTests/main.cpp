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
/// @brief MediaHashTests - framework-free unit tests for the core library.
///
/// Covers FileHasher (known vectors, chunking equivalence across all
/// algorithms, single-pass multi-digest consistency, cancellation, progress
/// reporting, error paths) and ChecksumFile (per-algorithm round-trip, CRLF
/// tolerance, missing/malformed companions, path derivation, discovery,
/// removal). Deliberately dependency free - a tiny CHECK harness keeps the
/// core library's zero-dependency philosophy intact and works identically
/// on macOS and Windows.
///
/// Run via ctest, or directly: ./mediahash_tests

#include <MediaHash/ChecksumFile.hpp>
#include <MediaHash/HashAlgorithm.hpp>
#include <MediaHash/MediaHash.hpp>

// C++ 23 note: Replace the std includes below by import std
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

namespace {

int g_checks = 0;
int g_failures = 0;

/// @brief Verifies a condition, recording and printing a failure if false.
#define CHECK(condition)                                                       \
    do {                                                                       \
        ++g_checks;                                                            \
        if (!(condition)) {                                                    \
            ++g_failures;                                                      \
            std::printf("FAIL %s:%d : %s\n", __FILE__, __LINE__, #condition);  \
        }                                                                      \
    } while (false)

/// @brief Verifies that an expression throws the given exception type.
#define CHECK_THROWS(expression, ExceptionType)                                \
    do {                                                                       \
        ++g_checks;                                                            \
        bool thrown = false;                                                   \
        try {                                                                  \
            (void)(expression);                                                \
        } catch (const ExceptionType&) {                                       \
            thrown = true;                                                     \
        } catch (...) {                                                        \
        }                                                                      \
        if (!thrown) {                                                         \
            ++g_failures;                                                      \
            std::printf("FAIL %s:%d : expected %s from %s\n", __FILE__,        \
                        __LINE__, #ExceptionType, #expression);                \
        }                                                                      \
    } while (false)

/// @brief RAII temporary directory, removed with its contents on destruction.
struct TempDir {
    std::filesystem::path path;

    TempDir() {
        const auto stamp = std::chrono::steady_clock::now()
                               .time_since_epoch()
                               .count();
        path = std::filesystem::temp_directory_path()
               / ("mediahash_tests_" + std::to_string(stamp));
        std::filesystem::create_directories(path);
    }

    ~TempDir() {
        std::error_code ec;
        std::filesystem::remove_all(path, ec);
    }

    TempDir(const TempDir&) = delete;
    TempDir& operator=(const TempDir&) = delete;
};

/// @brief Writes @p content verbatim (binary mode) to @p filePath.
void writeFile(const std::filesystem::path& filePath, const std::string_view content) {
    std::ofstream out(filePath, std::ios::binary | std::ios::trunc);
    out.write(content.data(), static_cast<std::streamsize>(content.size()));
}

// ---------------------------------------------------------------------------
// HashAlgorithm metadata tests
// ---------------------------------------------------------------------------

/// @brief Settings keys must round-trip through algorithmFromKey.
void testAlgorithmMetadata() {
    for (const auto algorithm : MediaHash::AllAlgorithms) {
        const auto parsed = MediaHash::algorithmFromKey(MediaHash::key(algorithm));
        CHECK(parsed.has_value() && parsed.value() == algorithm);
    }

    CHECK(!MediaHash::algorithmFromKey("md5").has_value());
    CHECK(!MediaHash::algorithmFromKey("").has_value());

    CHECK(MediaHash::extension(MediaHash::HashAlgorithm::Blake3) == ".blake3");
    CHECK(MediaHash::extension(MediaHash::HashAlgorithm::Sha1) == ".sha1");
    CHECK(MediaHash::name(MediaHash::HashAlgorithm::Sha1) == "SHA-1");
}

// ---------------------------------------------------------------------------
// FileHasher tests
// ---------------------------------------------------------------------------

/// @brief Known test vectors: SHA-1 and SHA-256 NIST (empty, "abc"),
///        BLAKE3 (empty, from the official test suite), XXH3-64 (empty,
///        matches xxhsum). XXH128 correctness is covered structurally: the
///        canonical-form API used for hex conversion is the same one
///        xxhsum uses.
void testKnownVectors(const TempDir& tmp) {
    using MediaHash::FileHasher;
    using MediaHash::HashAlgorithm;

    const auto emptyFile = tmp.path / "empty.bin";
    writeFile(emptyFile, "");
    CHECK(FileHasher::hash(emptyFile, HashAlgorithm::Sha1).hex
          == "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    CHECK(FileHasher::hash(emptyFile, HashAlgorithm::Sha256).hex
          == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    CHECK(FileHasher::hash(emptyFile, HashAlgorithm::Blake3).hex
          == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262");
    CHECK(FileHasher::hash(emptyFile, HashAlgorithm::Xxh3).hex
          == "2d06800538d394c2");

    const auto abcFile = tmp.path / "abc.bin";
    writeFile(abcFile, "abc");
    CHECK(FileHasher::hash(abcFile, HashAlgorithm::Sha1).hex
          == "a9993e364706816aba3e25717850c26c9cd0d89d");
    CHECK(FileHasher::hash(abcFile, HashAlgorithm::Sha256).hex
          == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

/// @brief Every digest must have the length promised by digestHexLength.
void testDigestLengths(const TempDir& tmp) {
    const auto file = tmp.path / "lengths.bin";
    writeFile(file, "some sample content");

    for (const auto algorithm : MediaHash::AllAlgorithms) {
        const auto result = MediaHash::FileHasher::hash(file, algorithm);
        CHECK(result.hex.size() == MediaHash::digestHexLength(algorithm));
    }
}

/// @brief NIST 56-byte content hashed with a tiny chunk size, so the content
///        crosses many chunk boundaries - verifies chunked feeding is
///        equivalent to hashing in one pass, for every algorithm.
void testMultiChunk(const TempDir& tmp) {
    const auto file = tmp.path / "nist56.bin";
    writeFile(file, "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");

    // SHA-1 NIST vector pins absolute correctness across chunk boundaries.
    CHECK(MediaHash::FileHasher::hash(file, MediaHash::HashAlgorithm::Sha1,
                                      /*chunkSize=*/7).hex
          == "84983e441c3bd26ebaae4aa1f95129e5e54670f1");

    // For every algorithm, tiny chunks must equal a single-chunk pass.
    for (const auto algorithm : MediaHash::AllAlgorithms) {
        const auto chunked = MediaHash::FileHasher::hash(file, algorithm,
                                                         /*chunkSize=*/7);
        const auto whole = MediaHash::FileHasher::hash(file, algorithm);
        CHECK(chunked == whole);
    }
}

/// @brief hashMulti must return per-algorithm results identical to
///        individual hash() calls, in input order - the invariant the
///        Worker's single-pass verify-and-convert flow relies on.
void testMultiDigestSinglePass(const TempDir& tmp) {
    const auto file = tmp.path / "multi.bin";
    writeFile(file, "content shared by all digest contexts in one read pass");

    // constexpr vector variable would require
    // non-transient allocation; ill-formed in C++20/23
    // NOLINTNEXTLINE 
    const std::vector<MediaHash::HashAlgorithm> algorithms(
        MediaHash::AllAlgorithms.begin(), MediaHash::AllAlgorithms.end());

    const auto results = MediaHash::FileHasher::hashMulti(file, algorithms,
                                                          /*chunkSize=*/5);
    CHECK(results.size() == algorithms.size());

    for (std::size_t i = 0; i < algorithms.size(); ++i) {
        const auto single = MediaHash::FileHasher::hash(file, algorithms[i]);
        CHECK(results[i] == single);
    }
}

/// @brief Error paths: zero chunk size, empty algorithm list, nonexistent file.
void testErrorPaths(const TempDir& tmp) {
    const auto file = tmp.path / "abc.bin"; // Created in testKnownVectors.
    CHECK_THROWS(MediaHash::FileHasher::hash(file, MediaHash::HashAlgorithm::Blake3,
                                             /*chunkSize=*/0),
                 std::invalid_argument);

    CHECK_THROWS(MediaHash::FileHasher::hashMulti(file, /*algorithms=*/{}),
                 std::invalid_argument);

    CHECK_THROWS(MediaHash::FileHasher::hash(tmp.path / "does_not_exist.bin",
                                             MediaHash::HashAlgorithm::Blake3),
                 std::runtime_error);
}

/// @brief A cancel predicate returning true must raise CancellationError.
void testCancellation(const TempDir& tmp) {
    const auto file = tmp.path / "cancel.bin";
    writeFile(file, "some content that will never be fully hashed");

    CHECK_THROWS(MediaHash::FileHasher::hash(
                     file, MediaHash::HashAlgorithm::Blake3,
                     /*chunkSize=*/4, /*isCanceled=*/[]() { return true; }),
                 MediaHash::CancellationError);
}

/// @brief Progress must be monotonic, sized correctly, and end at 100%.
///        Multi-digest passes must report progress once per chunk, not
///        once per digest context.
void testProgressReporting(const TempDir& tmp) {
    const auto file = tmp.path / "progress.bin";
    writeFile(file, "0123456789"); // 10 bytes, chunkSize 4 -> 3 chunks.

    std::vector<std::int64_t> reported;
    std::int64_t reportedTotal = 0;

    (void)MediaHash::FileHasher::hashMulti(
        file,
        {MediaHash::HashAlgorithm::Blake3, MediaHash::HashAlgorithm::Sha1},
        /*chunkSize=*/4, /*isCanceled=*/nullptr,
        [&reported, &reportedTotal](const std::int64_t bytesRead,
                                    const std::int64_t totalBytes) {
            reported.push_back(bytesRead);
            reportedTotal = totalBytes;
        });

    CHECK(reportedTotal == 10);
    CHECK(reported.size() >= 3);      // 3 chunk ticks + 1 final tick.
    CHECK(reported.size() <= 4);      // Byte-based: one tick per chunk, not per digest.
    CHECK(!reported.empty() && reported.back() == 10);

    bool monotonic = true;
    for (std::size_t i = 1; i < reported.size(); ++i) {
        if (reported[i] < reported[i - 1])
            monotonic = false;
    }
    CHECK(monotonic);
}

// ---------------------------------------------------------------------------
// ChecksumFile tests
// ---------------------------------------------------------------------------

/// @brief write() followed by read() must return the same checksum, for
///        every algorithm, each in its own companion file.
void testCompanionRoundTrip(const TempDir& tmp) {
    const auto file = tmp.path / "movie.mkv";
    writeFile(file, "fake mkv content");

    for (const auto algorithm : MediaHash::AllAlgorithms) {
        const MediaHash::ChecksumFile companion(file, algorithm);
        CHECK(!companion.read().has_value()); // No companion yet.

        const std::string digest(MediaHash::digestHexLength(algorithm), 'a');
        companion.write(digest);

        const auto saved = companion.read();
        CHECK(saved.has_value() && saved.value() == digest);
    }
}

/// @brief A legacy .sha1 companion written with CRLF line endings and the
///        original format must read cleanly - backward compatibility.
void testCompanionCrlf(const TempDir& tmp) {
    const auto file = tmp.path / "crlf.mkv";
    writeFile(file, "content");

    const MediaHash::ChecksumFile companion(file, MediaHash::HashAlgorithm::Sha1);
    writeFile(companion.companionPath(),
              "File name : crlf.mkv\r\n"
              "SHA-1 hash : 84983e441c3bd26ebaae4aa1f95129e5e54670f1\r\n");

    const auto saved = companion.read();
    CHECK(saved.has_value()
          && saved.value() == "84983e441c3bd26ebaae4aa1f95129e5e54670f1");
}

/// @brief A companion with no recognizable hash line must throw. A hash
///        line for a different algorithm does not count.
void testCompanionNoHashLine(const TempDir& tmp) {
    const auto file = tmp.path / "malformed.mkv";
    writeFile(file, "content");

    const MediaHash::ChecksumFile companion(file, MediaHash::HashAlgorithm::Sha1);
    writeFile(companion.companionPath(), "File name : malformed.mkv\n");
    CHECK_THROWS(companion.read(), std::runtime_error);

    // Wrong algorithm header inside a .sha1 file must also be rejected.
    writeFile(companion.companionPath(),
              "File name : malformed.mkv\n"
              "BLAKE3 hash : aa\n");
    CHECK_THROWS(companion.read(), std::runtime_error);
}

/// @brief Path rules: empty path throws; the companion path replaces the
///        original extension per algorithm (movie.mkv -> movie.blake3).
///        The replacement scheme is shared with the Python version.
void testCompanionPathRules(const TempDir& tmp) {
    CHECK_THROWS(MediaHash::ChecksumFile(std::filesystem::path{},
                                         MediaHash::HashAlgorithm::Blake3),
                 std::invalid_argument);

    const MediaHash::ChecksumFile blake3Companion(tmp.path / "movie.mkv",
                                                  MediaHash::HashAlgorithm::Blake3);
    CHECK(blake3Companion.companionPath() == tmp.path / "movie.blake3");
    CHECK(blake3Companion.path() == tmp.path / "movie.mkv");
    CHECK(blake3Companion.algorithm() == MediaHash::HashAlgorithm::Blake3);

    const MediaHash::ChecksumFile sha1Companion(tmp.path / "movie.mkv",
                                                MediaHash::HashAlgorithm::Sha1);
    CHECK(sha1Companion.companionPath() == tmp.path / "movie.sha1");
}

/// @brief existingAlgorithms() must report exactly the companions on disk,
///        in canonical AllAlgorithms order, and remove() must delete them.
void testCompanionDiscoveryAndRemoval(const TempDir& tmp) {
    const auto file = tmp.path / "discovery.mkv";
    writeFile(file, "content");

    CHECK(MediaHash::ChecksumFile::existingAlgorithms(file).empty());

    // Write .sha1 first, then .blake3 - discovery order must still be
    // canonical (Blake3 before Sha1), not creation order.
    const MediaHash::ChecksumFile sha1Companion(file, MediaHash::HashAlgorithm::Sha1);
    sha1Companion.write("aa");
    const MediaHash::ChecksumFile blake3Companion(file, MediaHash::HashAlgorithm::Blake3);
    blake3Companion.write("bb");

    const auto found = MediaHash::ChecksumFile::existingAlgorithms(file);
    CHECK(found.size() == 2
          && found[0] == MediaHash::HashAlgorithm::Blake3
          && found[1] == MediaHash::HashAlgorithm::Sha1);

    sha1Companion.remove();
    const auto afterRemoval = MediaHash::ChecksumFile::existingAlgorithms(file);
    CHECK(afterRemoval.size() == 1
          && afterRemoval[0] == MediaHash::HashAlgorithm::Blake3);

    // Removing an already-missing companion is a no-op.
    sha1Companion.remove();
    CHECK(MediaHash::ChecksumFile::existingAlgorithms(file).size() == 1);
}

} // namespace

int main() {
    const TempDir tmp;

    testAlgorithmMetadata();
    testKnownVectors(tmp);
    testDigestLengths(tmp);
    testMultiChunk(tmp);
    testMultiDigestSinglePass(tmp);
    testErrorPaths(tmp);
    testCancellation(tmp);
    testProgressReporting(tmp);
    testCompanionRoundTrip(tmp);
    testCompanionCrlf(tmp);
    testCompanionNoHashLine(tmp);
    testCompanionPathRules(tmp);
    testCompanionDiscoveryAndRemoval(tmp);

    if (g_failures == 0) {
        std::printf("OK - %d checks passed.\n", g_checks);
        return EXIT_SUCCESS;
    }

    std::printf("FAILED - %d of %d checks failed.\n", g_failures, g_checks);
    return EXIT_FAILURE;
}
