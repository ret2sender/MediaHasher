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

/// @file ClipboardHelper.hpp
/// @brief QML-facing wrapper around the system clipboard.

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

/// @brief Exposes the system clipboard to QML as the @c Clipboard singleton.
///
/// QML only provides clipboard access through editable text controls
/// (TextEdit/TextArea). Read-only views that implement their own selection
/// model (e.g. the jobs log) use this helper to place text on the clipboard
/// via QGuiApplication::clipboard(). Stateless, so the QML engine constructs
/// and owns the singleton instance itself.
///
/// @note Deliberately not @c final: constructor-mode QML singletons are
/// instantiated by the engine through QQmlPrivate::QQmlElement<T>, which
/// derives from T. Marking the class final makes registration ill-formed
/// (MSVC diagnoses this as C3246; clang happens not to instantiate the
/// offending specialization, but the code is invalid either way).
class ClipboardHelper : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Clipboard)
    QML_SINGLETON

public:
    /// @brief Constructs a ClipboardHelper.
    /// @param parent Optional QObject parent for ownership.
    explicit ClipboardHelper(QObject* parent = nullptr);

    /// @brief Places the given text on the system clipboard.
    /// @param text The plain text to copy.
    Q_INVOKABLE void setText(const QString& text) const;
};