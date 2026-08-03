/*
 * MediaHash - multi-algorithm file hashing core library.
 *
 * Copyright (c) 2026 Etienne Fleurant
 * SPDX-License-Identifier: MIT
 *
 * Part of the MediaHash core library, released under the MIT License.
 * See MediaHash/LICENSE for the full license text.
 */

/// @file ChecksumFile.cpp
/// @brief Implementation of algorithm-named companion file operations.

#include "MediaHash/ChecksumFile.hpp"

// C++ 23 note: Replace the std includes below by import std
#include <cctype>
#include <fstream>
#include <stdexcept>
#include <string>

namespace MediaHash {

namespace {

/// @brief Hash line prefix inside a companion file, e.g. "BLAKE3 hash : ".
///
/// For SHA-1 this yields "SHA-1 hash : ", byte identical to the legacy
/// format, so companions written by earlier versions stay readable.
///
/// @param algorithm Algorithm whose prefix to build.
/// @return The full "<ALGORITHM> hash : " prefix string.
[[nodiscard]] std::string headerPrefix(const HashAlgorithm algorithm) {
    return std::string(name(algorithm)) + " hash : ";
}

} // namespace

ChecksumFile::ChecksumFile(std::filesystem::path path, const HashAlgorithm algorithm)
    : m_algorithm(algorithm), m_path(std::move(path)) {
    if (m_path.empty())
        throw std::invalid_argument("ChecksumFile: path must not be empty.");
}

HashAlgorithm ChecksumFile::algorithm() const noexcept {
    return m_algorithm;
}

std::filesystem::path ChecksumFile::companionPath() const {
    auto result = m_path;
    result.replace_extension(extension(m_algorithm));
    return result;
}

const std::filesystem::path& ChecksumFile::path() const noexcept {
    return m_path;
}

namespace {

/// Converts a path to a UTF-8 std::string for error messages and file
/// content. std::filesystem::path::string() converts to the ANSI codepage
/// on MSVC, which garbles non-ASCII characters and can even throw for
/// characters the codepage cannot represent; u8string() is UTF-8 on every
/// platform. (Deliberately duplicated in MediaHash.cpp - a shared header
/// for four lines is not worth the coupling.)
std::string pathToUtf8(const std::filesystem::path& path) {
    const std::u8string u8 = path.u8string();
    return {u8.begin(), u8.end()};
}

} // namespace

std::optional<std::string> ChecksumFile::read() const {
    const auto companion = companionPath();

    if (!std::filesystem::is_regular_file(companion))
        return std::nullopt;

    std::ifstream file(companion);
    if (!file)
        throw std::runtime_error(
            "ChecksumFile: cannot open companion file: " + pathToUtf8(companion));

    const std::string prefix = headerPrefix(m_algorithm);

    std::string line;
    while (std::getline(file, line)) {
        if (line.starts_with(prefix)) {
            auto hex = line.substr(prefix.size());
            // Trim trailing whitespace (e.g. \r on Windows).
            while (!hex.empty() && std::isspace(static_cast<unsigned char>(hex.back())))
                hex.pop_back();
            return hex;
        }
    }

    throw std::runtime_error(
        "ChecksumFile: no " + std::string(name(m_algorithm))
        + " hash found in companion file: " + pathToUtf8(companion));
}

void ChecksumFile::remove() const {
    const auto companion = companionPath();

    std::error_code ec;
    std::filesystem::remove(companion, ec); // Missing file is a no-op.
    if (ec)
        throw std::runtime_error(
            "ChecksumFile: cannot remove companion file: " + pathToUtf8(companion)
            + " (" + ec.message() + ")");
}

void ChecksumFile::write(const std::string_view checksum) const {
    const auto companion = companionPath();

    std::ofstream file(companion, std::ios::trunc);
    if (!file)
        throw std::runtime_error(
            "ChecksumFile: cannot write companion file: " + pathToUtf8(companion));

    // UTF-8 on every platform so companion files are byte-identical
    // regardless of which OS wrote them.
    file << "File name : " << pathToUtf8(m_path.filename()) << '\n'
         << headerPrefix(m_algorithm) << checksum;
}

std::vector<HashAlgorithm> ChecksumFile::existingAlgorithms(
    const std::filesystem::path& path) {
    std::vector<HashAlgorithm> found;

    for (const HashAlgorithm algorithm : AllAlgorithms) {
        auto companion = path;
        companion.replace_extension(extension(algorithm));

        std::error_code ec;
        if (std::filesystem::is_regular_file(companion, ec))
            found.push_back(algorithm);
    }

    return found;
}

} // namespace MediaHash
