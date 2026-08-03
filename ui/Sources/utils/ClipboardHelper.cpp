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

/// @file ClipboardHelper.cpp
/// @brief Implementation of the QML-facing system clipboard wrapper.

#include "utils/ClipboardHelper.hpp"

#include <QClipboard>
#include <QGuiApplication>

ClipboardHelper::ClipboardHelper(QObject* parent) : QObject(parent) {}

// NOLINTNEXTLINE(readability-convert-member-functions-to-static) - Q_INVOKABLE requires an instance method
void ClipboardHelper::setText(const QString& text) const {
    QGuiApplication::clipboard()->setText(text);
}
