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

/// @file FileHelper.hpp
/// @brief QML utility element for resolving file paths from drag-and-drop operations.

#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

/// @brief QML-accessible helper for resolving dropped URLs into .mkv file paths.
///
/// Handles both individual file drops and directory drops (recursively
/// scanning for .mkv files). Registered as a QML element via @c QML_ELEMENT
/// so it can be instantiated directly in QML components that need drop support.
class FileHelper : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    /// @brief Constructs a FileHelper instance.
    /// @param parent Optional QObject parent for ownership.
    explicit FileHelper(QObject* parent = nullptr) : QObject(parent) {}

    /// @brief Resolves a list of dropped URL strings into a flat, sorted list
    ///        of .mkv file paths.
    ///
    /// Directories are recursively scanned for .mkv files. Individual files
    /// are included only if they have a .mkv extension (case-insensitive).
    ///
    /// @param urls List of URL strings from a QML DropArea's drop event.
    /// @return Sorted list of absolute path strings for all matching .mkv files.
    [[nodiscard]] Q_INVOKABLE static QStringList resolveMkvFiles(const QStringList& urls);
};