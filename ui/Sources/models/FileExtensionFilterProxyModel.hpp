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

/// @file FileExtensionFilterProxyModel.hpp
/// @brief Proxy model for filtering a QFileSystemModel by file extension.

#include <QModelIndex> // NOLINT - used in QSortFilterProxyModel
#include <QSet>
#include <QSortFilterProxyModel>
#include <QString>
#include <QStringList> // NOLINT - used in constructor signature
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;

/// @brief A sort/filter proxy that sits on top of a QFileSystemModel and only
///        exposes directories and files whose extension is in the allowed set.
///
/// Filtering is recursive (setRecursiveFilteringEnabled) so that parent
/// directories remain visible when they contain matching files at any depth.
///
/// Custom roles exposed to QML:
///   - @c IsDirectoryRole - bool indicating whether the index is a directory.
///   - @c FilePathRole    - absolute file path string for the index.
class FileExtensionFilterProxyModel : public QSortFilterProxyModel {
    Q_OBJECT
    QML_NAMED_ELEMENT(FileSystemModel)
    QML_SINGLETON

    /// @brief The proxy index corresponding to the user's home directory.
    ///
    /// Exposed as a Qt Property so QML can bind a TreeView's rootIndex
    /// directly. Maps the source model's home directory index through
    /// the proxy.
    Q_PROPERTY(QModelIndex rootIndex READ rootIndex NOTIFY rootIndexChanged)

public:
    /// @brief Custom data roles for QML consumption.
    enum CustomRoles {
        IsDirectoryRole = Qt::UserRole + 1,
        FilePathRole = Qt::UserRole + 2,
    };

    /// @brief Constructs the proxy with the given set of allowed extensions.
    ///
    /// Extensions are normalized to lowercase with a leading dot and stored
    /// as a QSet for O(1) lookup in filterAcceptsRow.
    ///
    /// @param extensions List of extensions to allow (e.g. {".mkv", ".mp4"}).
    ///                   A leading dot is added automatically if missing.
    /// @param parent     Optional QObject parent.
    explicit FileExtensionFilterProxyModel(const QStringList& extensions,
                                           QObject* parent = nullptr);

    /// @brief Singleton factory called by the QML engine on first access.
    ///
    /// Returns the instance previously supplied via set_instance() and marks
    /// it as C++-owned so the engine never deletes it. The instance must be
    /// set before the root QML component is loaded.
    ///
    /// @param qmlEngine The requesting QML engine (unused).
    /// @param jsEngine  The requesting JS engine (unused).
    /// @return The application-wide FileExtensionFilterProxyModel instance.
    static FileExtensionFilterProxyModel* create(QQmlEngine* qmlEngine,
                                                 QJSEngine* jsEngine);

    /// @brief Supplies the instance returned by create().
    ///
    /// Called once from main() before the QML engine loads the root
    /// component. The instance remains owned by the caller.
    ///
    /// @param instance The application-wide proxy model instance.
    static void set_instance(FileExtensionFilterProxyModel* instance);

    /// @brief Returns data for the given index and role.
    ///
    /// Handles custom roles (IsDirectoryRole, FilePathRole) by querying
    /// the source model directly. All other roles are delegated to the
    /// base class.
    ///
    /// @param index Proxy model index to query.
    /// @param role  Data role (Qt::DisplayRole, IsDirectoryRole, FilePathRole, etc.).
    /// @return The requested data, or the base class result for standard roles.
    [[nodiscard]] QVariant data(const QModelIndex& index, int role) const override;

    /// @brief Returns the absolute file path for the given proxy index.
    ///
    /// QML-invokable replacement for the former magic-number FilePathRole
    /// lookup. Used by MediaTreeView's drag handler to build the
    /// text/uri-list payload.
    ///
    /// @param index Proxy model index to resolve.
    /// @return Absolute file path string, or an empty string if no
    ///         QFileSystemModel source is set.
    [[nodiscard]] Q_INVOKABLE QString filePath(const QModelIndex& index) const;

    /// @brief Returns the mapping of role integers to role name byte strings.
    ///
    /// Extends the base class roles with IsDirectoryRole ("isDirectory")
    /// and FilePathRole ("filePath") for QML property binding.
    ///
    /// @return Dictionary mapping role integers to role name byte strings.
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    /// @brief Returns the proxy index for the user's home directory.
    /// @return Proxy QModelIndex for QDir::homePath(), or an invalid
    ///         QModelIndex if no source model is set.
    [[nodiscard]] QModelIndex rootIndex() const;

signals:
    /// @brief Emitted when the root index changes (unused, required by Q_PROPERTY).
    void rootIndexChanged();

protected:
    /// @brief Determines whether a row in the source model should be included.
    ///
    /// Directories are always accepted (so the tree remains navigable).
    /// Files are accepted only if their suffix is in the allowed extensions set.
    ///
    /// @param sourceRow    Row number in the source model.
    /// @param sourceParent Parent index in the source model.
    /// @return @c true if the row should be visible, @c false otherwise.
    [[nodiscard]] bool filterAcceptsRow(int sourceRow,
                                        const QModelIndex& sourceParent) const override;

private:
    QSet<QString> m_extensions; ///< Allowed extensions, lowercase with leading dot.
    static const QSet<QString> m_blockedNames;

    /// @brief The application-wide instance handed out by create().
    static FileExtensionFilterProxyModel* s_instance;
};