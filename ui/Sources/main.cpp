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

/// @file main.cpp
/// @brief Application entry point for MediaHasher.
///
/// Sets up the Qt application, file system model with extension filtering,
/// QML engine, settings manager, backend logic, and macOS native styling.
/// Backend objects are exposed to QML as module singletons (QML_SINGLETON);
/// their instances are owned here and handed to the engine via the
/// set_instance() hooks before the root QML component is loaded.

#include <QDir>
#include <QFileSystemModel>
#include <QGuiApplication> // NOLINT - used directly in main()
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

#include "MediaHasher.hpp"
#include "models/FileExtensionFilterProxyModel.hpp"
#include "utils/AppInfo.hpp" // NOLINT - MEDIAHASHER_VERSION_STR fallback guard
#include "utils/MacOSStyling.hpp"
#include "utils/SettingsManager.hpp"


int main(int argc, char* argv[]) {

    #if defined(Q_OS_WIN)
    // The Windows frameless window (Qt::FramelessWindowHint + transparent
    // ApplicationWindow color + radius 8 background) formally requires an
    // alpha channel in the default surface format. Must be called before
    // QGuiApplication is constructed.
    QQuickWindow::setDefaultAlphaBuffer(true);
    #endif

    QGuiApplication app(argc, argv);

    // Application identity. The version string is the same
    // MEDIAHASHER_VERSION_STR the AppInfo singleton exposes to QML
    // (defined from PROJECT_VERSION in ui/CMakeLists.txt), so
    // QCoreApplication::applicationVersion() and the About section can
    // never disagree.
    QGuiApplication::setApplicationName(QStringLiteral("MediaHasher"));
    QGuiApplication::setApplicationVersion(QStringLiteral(MEDIAHASHER_VERSION_STR));

    QQuickStyle::setStyle("Basic");

    // -----------------------------------------------------------------------
    // File system model + proxy
    // -----------------------------------------------------------------------
    QFileSystemModel fileModel;
    fileModel.setRootPath("");
    fileModel.setFilter(QDir::AllEntries | QDir::NoDotDot);

    FileExtensionFilterProxyModel proxyModel({".mkv"});
    proxyModel.setSourceModel(&fileModel);
    FileExtensionFilterProxyModel::set_instance(&proxyModel);

    // -----------------------------------------------------------------------
    // Settings manager
    // -----------------------------------------------------------------------
    // One-time migration from the legacy location (next to the executable)
    // to the canonical ~/.config/MediaHasher/settings.yml.
    SettingsManager::migrate_legacy_settings(
        QDir(QCoreApplication::applicationDirPath()).filePath("settings.yml"));

    SettingsManager settingsManager(SettingsManager::default_settings_path());
    SettingsManager::set_instance(&settingsManager);

    // -----------------------------------------------------------------------
    // Backend
    // -----------------------------------------------------------------------
    MediaHasher backend(settingsManager.get_concurrent_processes());
    MediaHasher::set_instance(&backend);

    // Seed the hashing configuration from the persisted settings. Later
    // changes flow through the same slots when the settings dialog applies
    // (see MainWindow.qml's Connections on settingsDialog.applied).
    backend.set_hash_algorithm(settingsManager.get_hash_algorithm());
    backend.set_convert_existing_hashes(settingsManager.get_convert_existing_hashes());

    // -----------------------------------------------------------------------
    // Load QML
    // -----------------------------------------------------------------------
    // All singleton instances must be set before the root component is
    // loaded - the engine calls the create() hooks on first QML access.
    QQmlApplicationEngine engine;
    engine.loadFromModule("com.mediahasher.app", "MainWindow");

    qDebug().noquote() << "Root objects count:" << engine.rootObjects().count();
    if (engine.rootObjects().isEmpty())
        return -1;

    #if defined(Q_OS_MACOS)
    applyMacOSStyling(&engine);
    #else
    qDebug().noquote() << "Styling: no platform matched";
    #endif

    return QGuiApplication::exec();
}
