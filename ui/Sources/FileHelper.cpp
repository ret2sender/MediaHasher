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

/// @file FileHelper.cpp
/// @brief Implementation of the QML drag-and-drop file resolution helper.

#include "FileHelper.hpp"

#include <QDir> // NOLINT - used in QDirIterator filter
#include <QDirIterator>
#include <QFileInfo>
#include <QUrl>

QStringList FileHelper::resolveMkvFiles(const QStringList& urls) {
    QStringList results;

    for (const QString& path : urls) {
        const QString localPath = path.startsWith("file://")
                                      ? QUrl(path).toLocalFile()
                                      : path;
        const QFileInfo info(localPath); // NOLINT - used in both if and else-if branches

        if (info.isDir()) {
            QDirIterator it(localPath, {"*.mkv"}, QDir::Files,
                            QDirIterator::Subdirectories);
            while (it.hasNext()) {
                results.append(it.next());
            }
        } else if (info.isFile()
                   && info.suffix().compare("mkv", Qt::CaseInsensitive) == 0) {
            results.append(localPath);
        }
    }

    results.sort();
    return results;
}