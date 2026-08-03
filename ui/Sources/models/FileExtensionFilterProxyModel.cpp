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

/// @file FileExtensionFilterProxyModel.cpp
/// @brief Implementation of the file extension filter proxy model.
///
/// Wraps a QFileSystemModel and exposes only directories and files
/// matching a configured set of extensions. Custom roles (IsDirectoryRole,
/// FilePathRole) are provided so QML can query directory status and
/// absolute paths directly from the proxy.

#include "models/FileExtensionFilterProxyModel.hpp"

#include <QDir> // NOLINT - used in rootIndex()
#include <QFileInfo>
#include <QFileSystemModel>
#include <QJSEngine>

// Windows system/junk directories to hide.
const QSet<QString> FileExtensionFilterProxyModel::m_blockedNames = {
    "$RECYCLE.BIN",
    "System Volume Information",
    "$WinREAgent",
    "$SysReset",
    "Recovery",
    "Config.Msi",
};

FileExtensionFilterProxyModel* FileExtensionFilterProxyModel::s_instance = nullptr;

FileExtensionFilterProxyModel::FileExtensionFilterProxyModel(
    const QStringList& extensions, QObject* parent)
    : QSortFilterProxyModel(parent) {
    // Note: recursive filtering is intentionally NOT enabled. It only
    // matters when a rejected parent must stay visible because a descendant
    // matches - filterAcceptsRow() accepts all directories unconditionally,
    // so recursion could never change an outcome and would only add
    // re-evaluation overhead on the lazily populated QFileSystemModel.

    for (const QString& extension : extensions) {
        QString normalized = extension.toLower();
        if (!normalized.startsWith('.'))
            normalized.prepend('.');
        m_extensions.insert(normalized);
    }
}

FileExtensionFilterProxyModel* FileExtensionFilterProxyModel::create(
    QQmlEngine* /*qmlEngine*/, QJSEngine* /*jsEngine*/) {
    Q_ASSERT_X(s_instance != nullptr, "FileExtensionFilterProxyModel::create",
               "set_instance() must be called before the engine loads QML");
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void FileExtensionFilterProxyModel::set_instance(
    FileExtensionFilterProxyModel* instance) {
    s_instance = instance;
}

QVariant FileExtensionFilterProxyModel::data(const QModelIndex& index, const int role) const {
    if (role == IsDirectoryRole) {
        if (const auto* fsModel = qobject_cast<const QFileSystemModel*>(sourceModel()))
            return fsModel->isDir(mapToSource(index));
        return false;
    }
    if (role == FilePathRole)
        return filePath(index);
    return QSortFilterProxyModel::data(index, role);
}

QString FileExtensionFilterProxyModel::filePath(const QModelIndex& index) const {
    if (const auto* fsModel = qobject_cast<const QFileSystemModel*>(sourceModel()))
        return fsModel->filePath(mapToSource(index));
    return {};
}

bool FileExtensionFilterProxyModel::filterAcceptsRow(
    const int sourceRow, const QModelIndex& sourceParent) const {
    const auto* fsModel = qobject_cast<const QFileSystemModel*>(sourceModel());
    if (!fsModel)
        return true;

    const QModelIndex index = fsModel->index(sourceRow, 0, sourceParent);
    const QString name = fsModel->fileName(index);

    // Hide dot-prefixed (hidden) directory entries.
    if (name.startsWith('.'))
        return false;

    if (m_blockedNames.contains(name))
        return false;

    // Unfiltered directories are accepted so the tree remains navigable.
    if (fsModel->isDir(index))
        return true;

    // Accept files whose extension is in the allowed set.
    const QString suffix = '.' + QFileInfo(name).suffix().toLower();
    return m_extensions.contains(suffix);
}

QHash<int, QByteArray> FileExtensionFilterProxyModel::roleNames() const {
    auto roles = QSortFilterProxyModel::roleNames();
    roles[IsDirectoryRole] = "isDirectory";
    roles[FilePathRole] = "filePath";
    return roles;
}

QModelIndex FileExtensionFilterProxyModel::rootIndex() const {
    if (!sourceModel())
        return {};
    return mapFromSource(QModelIndex{}); // invisible root → all drives as children
}