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

/// @file SettingsManager.cpp
/// @brief YAML-based application preferences manager implementation.
///
/// Uses yaml-cpp to read and write a settings.yml file that is compatible
/// with the Python version of MediaHasher (same file format, key names,
/// and canonical location: ~/.config/MediaHasher/settings.yml).

#include "utils/SettingsManager.hpp"

#include <QDebug> // NOLINT - used in module for qDebug and qWarning
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>

#include <yaml-cpp/yaml.h>

#include <MediaHash/HashAlgorithm.hpp>

#include <filesystem>
#include <fstream>
#include <utility>

namespace {

/// @brief Converts a std::string_view (e.g. from HashAlgorithm helpers)
///        into a QString.
/// @param text The string view to convert.
/// @return The equivalent QString.
[[nodiscard]] QString toQString(const std::string_view text) {
    return QString::fromUtf8(text.data(), static_cast<qsizetype>(text.size()));
}

/// @brief Settings key of the default hash algorithm (BLAKE3).
/// @return The default algorithm key as a QString.
[[nodiscard]] QString defaultHashAlgorithmKey() {
    return toQString(MediaHash::key(MediaHash::HashAlgorithm::Blake3));
}

} // namespace

SettingsManager* SettingsManager::s_instance = nullptr;

SettingsManager::SettingsManager(QString settingsPath, QObject* parent)
    : QObject(parent), m_hashAlgorithm(defaultHashAlgorithmKey()),
      m_settingsPath(std::move(settingsPath)) {
    load();
}

// ---------------------------------------------------------------------------
// Public static methods
// ---------------------------------------------------------------------------

SettingsManager* SettingsManager::create(QQmlEngine* /*qmlEngine*/, QJSEngine* /*jsEngine*/) {
    Q_ASSERT_X(s_instance != nullptr, "SettingsManager::create",
               "set_instance() must be called before the engine loads QML");
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

QString SettingsManager::default_settings_path() {
    return QDir::home().filePath(
        QStringLiteral(".config/MediaHasher/settings.yml"));
}

void SettingsManager::migrate_legacy_settings(const QString& legacyPath) {
    const QString newPath = default_settings_path();
    if (!QFile::exists(legacyPath) || QFile::exists(newPath))
        return;

    const QDir targetDir = QFileInfo(newPath).dir(); // NOLINT - used directly in if branch
    if (!targetDir.exists() && !targetDir.mkpath(".")) {
        qWarning().noquote()
            << "Settings migration: failed to create"
            << QDir::toNativeSeparators(targetDir.absolutePath());
        return;
    }

    if (QFile::copy(legacyPath, newPath)) {
        qDebug().noquote()
            << QStringLiteral("Settings migrated from %1 to %2")
                  .arg(QDir::toNativeSeparators(legacyPath),
                       QDir::toNativeSeparators(newPath));
    } else {
        qWarning().noquote()
            << "Settings migration: failed to copy"
            << QDir::toNativeSeparators(legacyPath)
            << "to"
            << QDir::toNativeSeparators(newPath);
    }
}

void SettingsManager::set_instance(SettingsManager* instance) {
    s_instance = instance;
}

// ---------------------------------------------------------------------------
// Public slots
// ---------------------------------------------------------------------------

int SettingsManager::get_concurrent_processes() const {
    return m_concurrentProcesses;
}

bool SettingsManager::get_convert_existing_hashes() const {
    return m_convertExistingHashes;
}

int SettingsManager::get_default_concurrent_processes() {
    return DefaultConcurrent;
}

bool SettingsManager::get_default_convert_existing_hashes() {
    return DefaultConvertExistingHashes;
}

QString SettingsManager::get_default_hash_algorithm() {
    return defaultHashAlgorithmKey();
}

QString SettingsManager::get_hash_algorithm() const {
    return m_hashAlgorithm;
}

QStringList SettingsManager::get_hash_algorithm_keys() {
    QStringList keys;
    keys.reserve(static_cast<qsizetype>(MediaHash::AllAlgorithms.size()));
    for (const MediaHash::HashAlgorithm algorithm : MediaHash::AllAlgorithms)
        keys.append(toQString(MediaHash::key(algorithm)));
    return keys;
}

QStringList SettingsManager::get_hash_algorithm_labels() {
    QStringList labels;
    labels.reserve(static_cast<qsizetype>(MediaHash::AllAlgorithms.size()));
    for (const MediaHash::HashAlgorithm algorithm : MediaHash::AllAlgorithms)
        labels.append(toQString(MediaHash::name(algorithm)));
    return labels;
}

int SettingsManager::get_max_concurrent() {
    return MaxConcurrent;
}

int SettingsManager::get_min_concurrent() {
    return MinConcurrent;
}

void SettingsManager::reload() {
    load();
}

bool SettingsManager::save() {
    try {
        // Ensure the settings directory exists (created lazily on first save).
        const QDir targetDir = QFileInfo(m_settingsPath).dir(); // NOLINT - used directly in if branch
        if (!targetDir.exists() && !targetDir.mkpath(".")) {
            qWarning().noquote()
                << "Failed to create settings directory:"
                << QDir::toNativeSeparators(targetDir.absolutePath());
            return false;
        }

        YAML::Emitter out;
        out << YAML::BeginMap;
        out << YAML::Key << "preferences";
        out << YAML::BeginMap;
        out << YAML::Key << "concurrent_processes" << YAML::Value << m_concurrentProcesses;
        out << YAML::Key << "hash_algorithm" << YAML::Value << m_hashAlgorithm.toStdString();
        out << YAML::Key << "convert_existing_hashes" << YAML::Value << m_convertExistingHashes;
        out << YAML::EndMap;
        out << YAML::EndMap;

        // UTF-16 path construction - see Worker::processFile for rationale.
        // A narrow string breaks for non-ASCII home paths (accented
        // Windows usernames) under MSVC.
        std::ofstream fileOut(std::filesystem::path{m_settingsPath.toStdU16String()});
        if (!fileOut.is_open()) {
            qWarning().noquote()
                << "Failed to open settings file for writing:"
                << QDir::toNativeSeparators(m_settingsPath);
            return false;
        }
        fileOut << out.c_str();
        fileOut.close();

        qDebug().noquote() << QStringLiteral("Settings saved to %1").arg(QDir::toNativeSeparators(m_settingsPath));
        emit settingsChanged();
        return true;
    } catch (const std::exception& e) {
        qWarning().noquote() << "Failed to save settings:" << e.what();
        return false;
    }
}

QString SettingsManager::set_concurrent_processes(const int value) {
    if (value < MinConcurrent || value > MaxConcurrent) {
        return QString("Value must be between %1 and %2.")
            .arg(MinConcurrent)
            .arg(MaxConcurrent);
    }
    m_concurrentProcesses = value;
    return {};
}

void SettingsManager::set_convert_existing_hashes(const bool value) {
    m_convertExistingHashes = value;
}

QString SettingsManager::set_hash_algorithm(const QString& key) {
    if (!MediaHash::algorithmFromKey(key.toStdString()).has_value()) {
        return QString("Unknown hash algorithm '%1'.").arg(key);
    }
    m_hashAlgorithm = key;
    return {};
}

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

void SettingsManager::load() {
    if (!QFile::exists(m_settingsPath)) {
        qDebug().noquote()
            << QStringLiteral("No settings file found at %1 - using defaults.")
                  .arg(QDir::toNativeSeparators(m_settingsPath));
        return;
    }

    try {
        // YAML::LoadFile only accepts a narrow string, which MSVC
        // interprets in the ANSI codepage - breaking for non-ASCII home
        // paths. Open the stream ourselves from a correctly-constructed
        // path instead.
        std::ifstream settingsIn(
            std::filesystem::path{m_settingsPath.toStdU16String()});
        if (!settingsIn.is_open()) {
            qWarning().noquote()
                << "Failed to open settings file for reading:"
                << QDir::toNativeSeparators(m_settingsPath);
            return;
        }
        YAML::Node root = YAML::Load(settingsIn);
        if (!root.IsMap())
            return;

        const auto prefs = root["preferences"];
        if (!prefs || !prefs.IsMap())
            return;

        if (const auto val = prefs["concurrent_processes"]) {
            const int v = val.as<int>(
                DefaultConcurrent); // NOLINT - used directly in if branch
            if (v >= MinConcurrent && v <= MaxConcurrent) {
                m_concurrentProcesses = v;
            } else {
                qWarning().noquote()
                    << "Invalid concurrent_processes value ("
                    << v
                    << ") in settings - using default.";
            }
        }

        if (const auto val = prefs["hash_algorithm"]) {
            const auto key = QString::fromStdString(val.as<std::string>(
                defaultHashAlgorithmKey().toStdString())); // NOLINT - used directly in if branch
            if (MediaHash::algorithmFromKey(key.toStdString()).has_value()) {
                m_hashAlgorithm = key;
            } else {
                qWarning().noquote()
                    << "Invalid hash_algorithm value ("
                    << key
                    << ") in settings - using default.";
            }
        }

        if (const auto val = prefs["convert_existing_hashes"]) {
            m_convertExistingHashes = val.as<bool>(DefaultConvertExistingHashes);
        }
    } catch (const std::exception& e) {
        qWarning().noquote() << "Could not read settings file:" << e.what() << "- using defaults.";

    }
}
