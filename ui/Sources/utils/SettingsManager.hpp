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

/// @file SettingsManager.hpp
/// @brief YAML-based application preferences manager.

#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;

/// @brief Reads and writes application preferences from/to a settings.yml file.
///
/// The canonical location is ~/.config/MediaHasher/settings.yml on all
/// platforms (see default_settings_path()), shared with the Python version.
/// Exposed to QML as the @c SettingsManager module singleton so the settings
/// dialog can load and persist values without touching the file system
/// directly.
class SettingsManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    /// @brief Constructs a SettingsManager and loads settings from disk.
    ///
    /// If the settings file does not exist or contains invalid data,
    /// built-in defaults are used.
    ///
    /// @param settingsPath Absolute path to the settings.yml file.
    /// @param parent       Optional QObject parent for ownership.
    explicit SettingsManager(QString settingsPath, QObject* parent = nullptr);

    /// @brief Singleton factory called by the QML engine on first access.
    ///
    /// Returns the instance previously supplied via set_instance() and marks
    /// it as C++-owned so the engine never deletes it. The instance must be
    /// set before the root QML component is loaded.
    ///
    /// @param qmlEngine The requesting QML engine (unused).
    /// @param jsEngine  The requesting JS engine (unused).
    /// @return The application-wide SettingsManager instance.
    static SettingsManager* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);

    /// @brief Returns the canonical settings file path.
    ///
    /// Deliberately ~/.config/MediaHasher/settings.yml on ALL platforms
    /// (not QStandardPaths::AppConfigLocation) so every MediaHasher
    /// implementation shares one settings file at a predictable location.
    ///
    /// @return Absolute path to the canonical settings.yml.
    [[nodiscard]] static QString default_settings_path();

    /// @brief One-time migration of a settings file from a legacy location.
    ///
    /// Copies @p legacyPath to default_settings_path() if the legacy file
    /// exists and no file exists at the canonical location yet. The legacy
    /// file is left in place. No-op in every other case.
    ///
    /// @param legacyPath Absolute path to the legacy settings.yml.
    static void migrate_legacy_settings(const QString& legacyPath);

    /// @brief Supplies the instance returned by create().
    ///
    /// Called once from main() before the QML engine loads the root
    /// component. The instance remains owned by the caller.
    ///
    /// @param instance The application-wide SettingsManager instance.
    static void set_instance(SettingsManager* instance);

public slots:
    /// @brief Returns the current concurrent-processes preference.
    /// @return Number of concurrent worker threads.
    [[nodiscard]] int get_concurrent_processes() const;

    /// @brief Returns whether stale companion hash files are converted to
    ///        the selected algorithm's format.
    /// @return @c true when conversion is enabled.
    [[nodiscard]] bool get_convert_existing_hashes() const;

    /// @brief Returns the built-in default for concurrent processes.
    ///
    /// Exposed so the settings dialog can mark values that differ from
    /// their defaults.
    ///
    /// @return Default number of concurrent worker threads.
    [[nodiscard]] static int get_default_concurrent_processes();

    /// @brief Returns the built-in default for convert-existing-hashes.
    /// @return Default conversion flag.
    [[nodiscard]] static bool get_default_convert_existing_hashes();

    /// @brief Returns the built-in default hash algorithm.
    /// @return Default algorithm settings key ("blake3").
    [[nodiscard]] static QString get_default_hash_algorithm();

    /// @brief Returns the current hash algorithm preference.
    /// @return Algorithm settings key ("blake3", "xxh3", "xxh128", "sha1").
    [[nodiscard]] QString get_hash_algorithm() const;

    /// @brief Returns the settings keys of all supported hash algorithms.
    ///
    /// Index-aligned with get_hash_algorithm_labels() so QML can map a
    /// ComboBox index to its settings key.
    ///
    /// @return Keys in canonical order, e.g. {"blake3", "xxh3", ...}.
    [[nodiscard]] static QStringList get_hash_algorithm_keys();

    /// @brief Returns the display names of all supported hash algorithms.
    ///
    /// Index-aligned with get_hash_algorithm_keys(); intended as the
    /// ComboBox model in the settings dialog.
    ///
    /// @return Display names in canonical order, e.g. {"BLAKE3", "XXH3", ...}.
    [[nodiscard]] static QStringList get_hash_algorithm_labels();

    /// @brief Returns the maximum allowed value for concurrent processes.
    /// @return Upper bound for the concurrent-processes setting.
    [[nodiscard]] static int get_max_concurrent();

    /// @brief Returns the minimum allowed value for concurrent processes.
    /// @return Lower bound for the concurrent-processes setting.
    [[nodiscard]] static int get_min_concurrent();

    /// @brief Re-reads settings.yml, discarding any unsaved in-memory changes.
    void reload();

    /// @brief Persists the current in-memory settings to settings.yml.
    ///
    /// Emits settingsChanged() on success.
    ///
    /// @return @c true on success, @c false on failure.
    bool save();

    /// @brief Validates and stages a new concurrent-processes value.
    ///
    /// The value is @em not persisted until save() is called.
    ///
    /// @param value Desired number of concurrent processes.
    /// @return Empty string on success, or a warning message if out of bounds.
    QString set_concurrent_processes(int value);

    /// @brief Stages a new convert-existing-hashes value.
    ///
    /// The value is @em not persisted until save() is called.
    ///
    /// @param value @c true to convert stale companion hash files.
    void set_convert_existing_hashes(bool value);

    /// @brief Validates and stages a new hash algorithm.
    ///
    /// The value is @em not persisted until save() is called.
    ///
    /// @param key Algorithm settings key ("blake3", "xxh3", "xxh128", "sha1").
    /// @return Empty string on success, or a warning message if the key is
    ///         unknown.
    QString set_hash_algorithm(const QString& key);

signals:
    /// @brief Emitted after a successful save so the rest of the app can react.
    void settingsChanged();

private:
    /// @brief Loads settings from settings.yml, falling back to defaults
    ///        for any missing or invalid keys.
    void load();

    static constexpr int DefaultConcurrent = 3;
    static constexpr int MaxConcurrent = 5;
    static constexpr int MinConcurrent = 1;
    static constexpr bool DefaultConvertExistingHashes = false;

    /// @brief The application-wide instance handed out by create().
    static SettingsManager* s_instance;

    int m_concurrentProcesses = DefaultConcurrent;
    bool m_convertExistingHashes = DefaultConvertExistingHashes;
    QString m_hashAlgorithm; ///< Initialized to the default key in the constructor.
    QString m_settingsPath;
};
