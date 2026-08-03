/*
 * MediaHasher - cross-platform media file integrity tool.
 * Copyright (C) 2026 Etienne Fleurant
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

/// @file HashJobConfig.hpp
/// @brief Per-run hashing configuration shared by MediaHasher and Worker.

#include <MediaHash/HashAlgorithm.hpp>

/// @brief Immutable-per-run hashing configuration.
///
/// MediaHasher keeps one instance updated from the settings (via its
/// set_* slots) and hands a copy to each Worker at start(). Workers never
/// read settings directly, so a mid-run settings change cannot produce a
/// run that mixes algorithms.
struct HashJobConfig {
    /// @brief Algorithm used to hash files and name new companion files.
    MediaHash::HashAlgorithm algorithm = MediaHash::HashAlgorithm::Blake3;

    /// @brief When @c true, companion files in other formats are converted
    ///        to @ref algorithm.
    ///
    /// Each stale companion is always verified against the file first,
    /// computed in the same single read pass as the new digest, so it costs
    /// no extra I/O, and only then replaced: the new companion is written
    /// and the stale ones are deleted. On any mismatch nothing is written
    /// or deleted, so the stale companion remains as evidence of what the
    /// file should have contained.
    bool convertExistingHashes = false;
};
