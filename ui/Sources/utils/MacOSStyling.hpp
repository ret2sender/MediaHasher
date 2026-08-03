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

/// @file MacOSStyling.hpp
/// @brief Native macOS window styling for the MediaHasher application.

/// Forward declaration of QQmlApplicationEngine.
///
/// Only a pointer to this class is used in the function signature below,
/// so the compiler does not need the full class definition here, just
/// the knowledge that the name exists. The full @c \<QQmlApplicationEngine\>
/// header is included in the .mm implementation file where the class is
/// actually used. This avoids pulling a heavy Qt header into every
/// translation unit that includes this header.
class QQmlApplicationEngine;

/// @brief Applies native macOS window styling to the application.
///
/// Configures the title bar to be transparent with full-size content view,
/// hides the title text, disables default window dragging (handled by QML),
/// and measures the native title bar height for QML layout offsets.
///
/// No-op on non-macOS platforms.
///
/// @param engine The QQmlApplicationEngine whose root window will be styled.
void applyMacOSStyling(QQmlApplicationEngine* engine);