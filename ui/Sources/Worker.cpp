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

/// @file Worker.cpp
/// @brief Worker implementation - multi-algorithm hashing with core library
///        delegation and companion file conversion.
///
/// Each Worker runs on a QThreadPool thread and processes files from a
/// shared queue. For each file it discovers the existing companion files,
/// computes every needed digest in a single read pass via
/// FileHasher::hashMulti, performs the companion write/convert/cleanup
/// actions dictated by its HashJobConfig, and emits the classified result
/// through its WorkerSignals bridge.

#include "Worker.hpp"

#include <QDebug> // NOLINT - used in module for qDebug and qWarning
#include <QElapsedTimer>
#include <QFileInfo>
#include <QThread>

#include <MediaHash/ChecksumFile.hpp>
#include <MediaHash/HashAlgorithm.hpp>
#include <MediaHash/MediaHash.hpp>

#include <filesystem>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

/// @brief Converts a std::string_view (e.g. from HashAlgorithm helpers)
///        into a QString.
/// @param text The string view to convert.
/// @return The equivalent QString.
[[nodiscard]] QString toQString(const std::string_view text) {
    return QString::fromUtf8(text.data(), static_cast<qsizetype>(text.size()));
}

/// @brief A stale companion file: same media file, different algorithm than
///        the currently selected one.
struct StaleCompanion {
    MediaHash::HashAlgorithm algorithm; ///< Algorithm of the stale companion.
    std::optional<std::string> stored;  ///< Stored digest; nullopt when the
                                        ///< companion file is unreadable.
};

} // namespace

Worker::Worker(QQueue<QString>* queue, QMutex* queueMutex,
               std::atomic<bool>* shutdownFlag, HashJobConfig config)
    : m_config(config), m_mutex(queueMutex), m_queue(queue),
      m_shutdownFlag(shutdownFlag) {
    m_signals = new WorkerSignals();
    setAutoDelete(false);
}

Worker::~Worker() {
    delete m_signals;
}

void Worker::cleanup() { // NOLINT - intentionally non-const despite not modifying Worker members
    // Prevent stale signal emissions after threads are joined.
    // The main thread calls this after waitForDone().
    // Return value intentionally ignored - we don't care if already disconnected.
    (void)m_signals->disconnect(); // NOLINT - return value intentionally discarded
}

void Worker::run() {
    // Wire the abort signal into our atomic flag.
    QObject::connect(m_signals, &WorkerSignals::workerAbort, m_signals, [this]() {
        abort();
    });

    while (!m_abort.load()) {
        QString filePath;

        {
            QMutexLocker lock(m_mutex);
            if (m_queue->isEmpty()) {
                // Queue is empty right now. Exit only if the shutdown flag has
                // been set (meaning no more files will be added). Otherwise,
                // keep waiting - new files may arrive from a mid-run drop.
                if (m_shutdownFlag->load())
                    break;
                lock.unlock();
                QThread::msleep(100);
                continue;
            }
            filePath = m_queue->dequeue();
        }

        if (m_abort.load())
            break;

        try {
            processFile(filePath);
        } catch (const MediaHash::CancellationError&) {
            break;
        }
    }

    // Always emit workerFinished, even on abort - the main thread
    // counts these to know when all workers have exited.
    emit m_signals->workerFinished();
}

void Worker::abort() {
    m_abort.store(true);
}

void Worker::processFile(const QString& filePath) const {
    // Notify QML that this file is now being processed.
    emit m_signals->fileProcessingStarted(filePath);

    // Reset current task progress bar.
    emit m_signals->taskProgressChanged(0, processId);

    // Emit the current file size to update its matching progress bar.
    const qint64 fileSize = QFileInfo(filePath).size();
    emit m_signals->checksumFileSize(static_cast<double>(fileSize), processId);

    // Constructed from UTF-16, not toStdString(): the char16_t constructor
    // is guaranteed to convert to the native encoding on every platform,
    // whereas a narrow std::string is interpreted in the ANSI codepage on
    // MSVC - mangling any non-ASCII path (e.g. accented characters) into a
    // file the OS cannot find.
    const std::filesystem::path mediaPath{filePath.toStdU16String()};
    const MediaHash::HashAlgorithm algorithm = m_config.algorithm;
    const QString algorithmName = toQString(MediaHash::name(algorithm));

    // -----------------------------------------------------------------------
    // Companion discovery
    //
    // Existing companions are identified by extension and their stored
    // digests read up front, so the subsequent hash pass knows exactly
    // which digest contexts to run.
    // -----------------------------------------------------------------------
    bool primaryExists = false;      // Companion for the selected algorithm.
    bool primaryUnreadable = false;  // Exists but malformed - never overwritten.
    std::optional<std::string> storedPrimary;
    std::vector<StaleCompanion> staleCompanions;

    for (const MediaHash::HashAlgorithm existing
         : MediaHash::ChecksumFile::existingAlgorithms(mediaPath)) {
        if (existing == algorithm) {
            primaryExists = true;
            try {
                storedPrimary = MediaHash::ChecksumFile(mediaPath, existing).read();
            } catch (const std::exception& e) {
                primaryUnreadable = true;
                qWarning().noquote() << "Worker" << processId
                                     << ": companion file error:" << e.what();
            }
            // Vanished between discovery and read (race) - treat as absent.
            if (!storedPrimary.has_value() && !primaryUnreadable)
                primaryExists = false;
        } else if (m_config.convertExistingHashes) {
            StaleCompanion stale{existing, std::nullopt};
            // Stale companions are always verified before conversion - the
            // digest rides the same read pass as the new one, so it costs
            // no extra I/O and prevents laundering corruption into a fresh
            // companion file.
            try {
                stale.stored = MediaHash::ChecksumFile(mediaPath, existing).read();
            } catch (const std::exception& e) {
                // Unverifiable - it is kept on disk and excluded from
                // both verification and deletion below.
                qWarning().noquote()
                    << "Worker" << processId
                    << ": stale companion unreadable (kept):" << e.what();
            }
            staleCompanions.push_back(std::move(stale));
        }
    }

    // -----------------------------------------------------------------------
    // Single-pass multi-digest hash
    //
    // The selected algorithm always runs; stale companions being verified
    // add their algorithm to the same pass, so verify-and-convert reads
    // the (potentially very large) media file exactly once.
    // -----------------------------------------------------------------------
    std::vector<MediaHash::HashAlgorithm> toCompute{algorithm};
    for (const StaleCompanion& stale : staleCompanions) {
        if (stale.stored.has_value())
            toCompute.push_back(stale.algorithm);
    }

    // Progress emissions are throttled (see ProgressEmitIntervalMs) - the
    // final 100% update below is emitted unconditionally.
    QElapsedTimer progressTimer;
    progressTimer.start();

    std::vector<MediaHash::Checksum> digests;
    try {
        digests = MediaHash::FileHasher::hashMulti(
            mediaPath,
            toCompute,
            1024 * 1024,
            [this]() -> bool { return m_abort.load(); },
            [this, &progressTimer](const std::int64_t bytesRead,
                                   std::int64_t /*total*/) {
                if (progressTimer.elapsed() < ProgressEmitIntervalMs)
                    return;
                progressTimer.restart();
                emit m_signals->checksumProgressUpdate(static_cast<double>(bytesRead),
                                                       processId);
            });
    } catch (const MediaHash::CancellationError&) {
        throw; // Propagated to run(), which exits its loop.
    } catch (const std::exception& e) {
        qWarning().noquote() << "Worker" << processId << ": hash error:" << e.what();
        emit m_signals->taskFailed(filePath, QString::fromUtf8(e.what()),
                                   processId);
        return;
    }

    if (m_abort.load())
        return;

    // Make sure we send a final 100% progress update.
    emit m_signals->checksumProgressUpdate(static_cast<double>(fileSize), processId);

    const QString newChecksum = QString::fromStdString(digests.front().hex);

    // -----------------------------------------------------------------------
    // Verification
    //
    // Any mismatch - against the primary companion or a stale one - stops
    // this file cold: nothing is written and nothing is deleted, so the
    // companion remains as evidence of what the file should have contained.
    // -----------------------------------------------------------------------
    if (primaryExists && storedPrimary.has_value()
        && storedPrimary.value() != digests.front().hex) {
        emit m_signals->taskFinished(filePath, QStringLiteral("mismatch"),
                                     algorithmName, newChecksum,
                                     QString::fromStdString(storedPrimary.value()),
                                     processId);
        return;
    }

    std::size_t digestIndex = 1;
    for (const StaleCompanion& stale : staleCompanions) {
        if (!stale.stored.has_value())
            continue;
        const std::string& staleDigest = digests[digestIndex++].hex;
        if (staleDigest != stale.stored.value()) {
            // Corruption detected against the OLD algorithm. Reported with
            // that algorithm's name and digests so the log entry compares
            // like with like.
            emit m_signals->taskFinished(filePath, QStringLiteral("mismatch"),
                                         toQString(MediaHash::name(stale.algorithm)),
                                         QString::fromStdString(staleDigest),
                                         QString::fromStdString(stale.stored.value()),
                                         processId);
            return;
        }
    }

    // -----------------------------------------------------------------------
    // Companion actions: write the new companion, then clean up stale ones
    // -----------------------------------------------------------------------
    bool wroteNewCompanion = false;
    if (!primaryExists) {
        try {
            MediaHash::ChecksumFile(mediaPath, algorithm).write(digests.front().hex);
            wroteNewCompanion = true;
        } catch (const std::exception& e) {
            qWarning().noquote() << "Worker" << processId
                                 << ": companion file error:" << e.what();
        }
    }

    // Stale companions are only deleted once the primary is secured: either
    // it already existed and matched, or the replacement was just written.
    // Unverified (unreadable) stales are always kept.
    const bool primarySecured = wroteNewCompanion
                                || (primaryExists && storedPrimary.has_value());
    int convertedCount = 0;
    if (m_config.convertExistingHashes && primarySecured) {
        for (const StaleCompanion& stale : staleCompanions) {
            if (!stale.stored.has_value())
                continue;
            try {
                MediaHash::ChecksumFile(mediaPath, stale.algorithm).remove();
                ++convertedCount;
            } catch (const std::exception& e) {
                qWarning().noquote() << "Worker" << processId
                                     << ": companion cleanup error:" << e.what();
            }
        }
    }

    // -----------------------------------------------------------------------
    // Outcome classification
    // -----------------------------------------------------------------------
    QString kind;
    QString checksumFromFile;
    if (primaryExists && storedPrimary.has_value()) {
        kind = QStringLiteral("match");
        checksumFromFile = QString::fromStdString(storedPrimary.value());
        if (convertedCount > 0) {
            qDebug().noquote() << "Worker" << processId << ": removed"
                               << convertedCount << "stale companion(s) for"
                               << filePath;
        }
    } else if (wroteNewCompanion && convertedCount > 0) {
        kind = QStringLiteral("converted");
        qDebug().noquote() << "Worker" << processId << ": converted"
                           << convertedCount << "companion(s) to"
                           << algorithmName << "for" << filePath;
    } else {
        kind = QStringLiteral("complete");
    }

    emit m_signals->taskFinished(filePath, kind, algorithmName, newChecksum,
                                 checksumFromFile, processId);
}
