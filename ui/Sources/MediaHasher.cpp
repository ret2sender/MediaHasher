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

/// @file MediaHasher.cpp
/// @brief Main backend implementation for the Qt MediaHasher UI.
///
/// Manages the file queue, worker thread lifecycle, hashing configuration,
/// progress tracking (per-worker and global), abort/resume semantics, and
/// mid-run file additions. Communicates with the QML frontend through Qt
/// signals.

#include "MediaHasher.hpp"
#include "Worker.hpp"

#include <QDebug> // NOLINT - used by qWarning/qDebug
#include <QFileInfo>
#include <QJSEngine>
#include <QUrl>

#include <MediaHash/HashAlgorithm.hpp>

MediaHasher* MediaHasher::s_instance = nullptr;

MediaHasher::MediaHasher(const int parallelProcesses, QObject* parent)
    : QObject(parent), m_parallelProcesses(parallelProcesses) {
    m_watchdog.setInterval(150);
    connect(&m_watchdog, &QTimer::timeout, this, &MediaHasher::checkQueueDrained);
}

// ---------------------------------------------------------------------------
// QML singleton machinery
// ---------------------------------------------------------------------------

MediaHasher* MediaHasher::create(QQmlEngine* /*qmlEngine*/, QJSEngine* /*jsEngine*/) {
    Q_ASSERT_X(s_instance != nullptr, "MediaHasher::create",
               "set_instance() must be called before the engine loads QML");
    // Permanent breadcrumb: proves the engine bound to the main()-owned
    // instance rather than constructing its own. A missing line here at
    // startup means constructor-mode registration silently took over -
    // see the @note on the MediaHasher constructor.
    qDebug().noquote() << "MediaHasher singleton bound to main()-owned instance";
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void MediaHasher::set_instance(MediaHasher* instance) {
    s_instance = instance;
}

// ---------------------------------------------------------------------------
// Public slots (called from QML)
// ---------------------------------------------------------------------------

void MediaHasher::abort() {
    m_aborted = true;
    m_watchdog.stop();
    m_shutdownFlag.store(true);
    emit workersAbort();
}

void MediaHasher::dequeue_files(const QStringList& filePaths) {
    if (m_isRunning) {
        qWarning().noquote() << "dequeue_files() called while running - ignoring.";
        return;
    }

    const QSet<QString> toRemove(filePaths.begin(), filePaths.end());
    const int before = static_cast<int>(m_filePaths.size());

    QStringList surviving;
    surviving.reserve(before);
    for (const QString& path : m_filePaths) {
        if (!toRemove.contains(path))
            surviving.append(path);
    }
    m_filePaths = surviving;

    const int removed = before - static_cast<int>(m_filePaths.size());
    if (removed == 0)
        return;

    // Subtract the enqueue-time size of each removed file and drop it from
    // the size tracker. Using recorded sizes (rather than re-statting the
    // whole surviving list) subtracts exactly what was added, even if a
    // file has changed or disappeared on disk since enqueue.
    for (const QString& path : filePaths)
        m_totalBytes -= m_enqueuedSizes.take(path);
    emit totalBytesUpdated(m_totalBytes);

    // Remove the paths from the pending queue in place. Only pending files
    // are removable from the UI, so this touches neither completed nor
    // in-flight files. Never rebuild the queue from m_filePaths here: after
    // an aborted run m_filePaths still contains already-completed files,
    // and rebuilding would re-enqueue them.
    {
        QMutexLocker lock(&m_queueMutex);
        for (const QString& path : filePaths)
            m_fileQueue.removeAll(path);
    }

    // m_filePaths retains every file belonging to the run (completed files
    // included), so its size remains the correct task total on resume.
    m_totalTasksCount = static_cast<int>(m_filePaths.size());

    qDebug().noquote() << QStringLiteral("dequeue_files: removed %1, total now %2 (%3 bytes)")
                          .arg(removed)
                          .arg(m_totalTasksCount)
                          .arg(m_totalBytes, 0, 'f', 0);
}

void MediaHasher::enqueue_files(const QStringList& filePaths) {
    if (m_isRunning) {
        qWarning().noquote() << "enqueue_files() called while running - use enqueue_files_mid_run().";
        return;
    }

    if (resolveAndEnqueue(filePaths) == 0)
        return;

    m_totalTasksCount = static_cast<int>(m_filePaths.size());
    emit totalBytesUpdated(m_totalBytes);
}

void MediaHasher::enqueue_files_mid_run(const QStringList& filePaths) {
    const int added = resolveAndEnqueue(filePaths);
    if (added == 0)
        return;

    m_totalTasksCount += added;
    emit totalBytesUpdated(m_totalBytes);

    qDebug().noquote() << QStringLiteral("enqueue_files_mid_run: added %1, total now %2 (%3 bytes)")
                          .arg(added)
                          .arg(m_totalTasksCount)
                          .arg(m_totalBytes, 0, 'f', 0);
}

int MediaHasher::get_parallel_processes() const {
    return m_parallelProcesses;
}

void MediaHasher::reset_state() {
    if (m_isRunning) {
        qWarning().noquote() << "reset_state() called while running - ignoring.";
        return;
    }

    m_aborted = false;
    m_completedTasksCount = 0;
    m_enqueuedSizes.clear();
    m_filePaths.clear();
    m_inFlight.clear();
    m_totalBytes = 0.0;
    m_totalBytesHashed = 0.0;
    m_workerLastBytes.clear();
    m_totalTasksCount = 0;

    // Drain the queue in case anything was left over from an abort.
    {
        QMutexLocker lock(&m_queueMutex);
        m_fileQueue.clear();
    }

    qDebug().noquote() << "Backend state reset";
}

void MediaHasher::set_convert_existing_hashes(const bool value) {
    if (m_isRunning) {
        qWarning().noquote() << "set_convert_existing_hashes() called while running - ignoring.";
        return;
    }
    m_hashConfig.convertExistingHashes = value;
    qDebug().noquote() << "Convert existing hashes set to" << value;
}

void MediaHasher::set_hash_algorithm(const QString& key) {
    if (m_isRunning) {
        qWarning().noquote() << "set_hash_algorithm() called while running - ignoring.";
        return;
    }

    const auto algorithm = MediaHash::algorithmFromKey(key.toStdString()); // NOLINT - used directly in if branch
    if (!algorithm.has_value()) {
        qWarning().noquote() << "set_hash_algorithm(): unknown algorithm key"
                             << key << "- keeping current algorithm.";
        return;
    }

    m_hashConfig.algorithm = algorithm.value();
    qDebug().noquote() << "Hash algorithm set to" << key;
}

void MediaHasher::set_parallel_processes(const int value) {
    if (m_isRunning) {
        qWarning().noquote() << "set_parallel_processes() called while running - ignoring.";
        return;
    }
    m_parallelProcesses = value;
    qDebug().noquote() << "Parallel processes set to" << value;
}

void MediaHasher::start() {
    if (m_isRunning) {
        qWarning().noquote() << "start() called while already running - ignoring.";
        return;
    }

    // Note: m_completedTasksCount is intentionally NOT reset here. On a
    // resume after abort the counter must keep counting from the already
    // finished tasks for the watchdog's completed >= total condition to
    // hold. It is reset in reset_state() for fresh runs.

    m_inFlight.clear();
    m_isRunning = true;
    m_shutdownFlag.store(false);
    m_workerLastBytes.clear();
    m_watchdog.start();

    emit workersStart();

    m_workers.clear();
    for (int i = 0; i < m_parallelProcesses; ++i) {
        // Each worker receives a copy of the current hashing configuration,
        // so a mid-run settings change cannot mix algorithms within one run.
        auto* worker = new Worker(&m_fileQueue, &m_queueMutex, &m_shutdownFlag,
                                  m_hashConfig);
        worker->processId = i;

        // Wire worker signals → our slots / signals.
        connect(worker->m_signals, &WorkerSignals::fileProcessingStarted, this,
                &MediaHasher::onFileDequeued);
        connect(worker->m_signals, &WorkerSignals::checksumFileSize, this,
                &MediaHasher::onChecksumFileSize);
        connect(worker->m_signals, &WorkerSignals::checksumProgressUpdate, this,
                &MediaHasher::onChecksumProgressUpdate);
        connect(worker->m_signals, &WorkerSignals::taskFailed, this,
                &MediaHasher::onTaskFailed);
        connect(worker->m_signals, &WorkerSignals::taskFinished, this,
                &MediaHasher::onTaskFinished);
        connect(worker->m_signals, &WorkerSignals::taskProgressChanged, this,
                &MediaHasher::workerProgressChanged);
        connect(worker->m_signals, &WorkerSignals::workerFinished, this,
                &MediaHasher::onWorkerFinished);

        // Wire the abort signal back into the worker.
        connect(this, &MediaHasher::workersAbort, worker->m_signals,
                &WorkerSignals::workerAbort);

        m_workers.append(worker);
        m_threadPool.start(worker);
    }
}

// ---------------------------------------------------------------------------
// Private slots
// ---------------------------------------------------------------------------

void MediaHasher::onChecksumFileSize(const double fileSize, const int processId) {
    m_workerLastBytes[processId] = 0.0;
    emit checksumFileSize(fileSize, processId);
}

void MediaHasher::onChecksumProgressUpdate(const double bytesHashed, const int processId) {
    const double previous = m_workerLastBytes.value(processId, 0.0);
    const double delta = bytesHashed - previous; // NOLINT - used directly in if branch
    if (delta > 0)
        m_totalBytesHashed += delta;
    m_workerLastBytes[processId] = bytesHashed;

    // Re-emit the per-worker signal for the worker progress bar.
    emit checksumProgressUpdate(bytesHashed, processId);
    // Emit the authoritative global total for the main progress bar.
    emit totalBytesHashedUpdated(m_totalBytesHashed);
}

void MediaHasher::onFileDequeued(const QString& filePath) {
    m_inFlight.insert(filePath);
    emit fileProcessingStarted(filePath);
}

void MediaHasher::onTaskFailed(
    const QString& filePath,
    const QString& errorMessage,
    const int processId) {
    // A failed file still counts as "handled" so the watchdog's
    // completed >= total condition remains correct.
    m_completedTasksCount++;
    m_inFlight.remove(filePath);

    // Roll back this worker's partial progress on the failed file.
    const double partial = m_workerLastBytes.value(processId, 0.0);
    if (partial > 0.0) {
        m_totalBytesHashed -= partial;
        emit totalBytesHashedUpdated(m_totalBytesHashed);
    }
    m_workerLastBytes[processId] = 0.0;

    // Remove the failed file from the denominator so the main progress
    // bar can still reach 100% for the files that do succeed.
    const double size = m_enqueuedSizes.value(filePath, 0.0);
    if (size > 0.0) {
        m_totalBytes -= size;
        emit totalBytesUpdated(m_totalBytes);
    }

    // Reset this worker's per-task progress bar.
    emit workerProgressChanged(0, processId);

    emit workerTaskFailed(filePath, errorMessage, processId);

    qDebug().noquote() << QStringLiteral("Worker %1 failed on %2 : %3")
                          .arg(processId)
                          .arg(filePath, errorMessage);
}

void MediaHasher::onTaskFinished(
    const QString& filePath,
    const QString& kind,
    const QString& algorithm,
    const QString& checksum,
    const QString& checksumFromFile,
    const int processId) {
    m_completedTasksCount++;
    m_inFlight.remove(filePath);
    m_workerLastBytes[processId] = 0.0;
    emit workerTaskFinished(filePath, kind, algorithm, checksum,
                            checksumFromFile, processId);
}

void MediaHasher::onWorkerFinished() {
    m_finishedProcessCount++;
    if (m_finishedProcessCount < m_parallelProcesses)
        return;

    // All workers have reported in - safe to join.
    m_threadPool.waitForDone();

    // Clean up workers now that threads are joined.
    for (Worker* worker : m_workers)
        worker->cleanup();
    qDeleteAll(m_workers);
    m_workers.clear();

    // On abort, re-enqueue any files that were in-flight so they can be
    // resumed on the next run.
    if (m_aborted) {
        // Subtract each worker's partial progress on its current file.
        for (
            auto it = m_workerLastBytes.cbegin();
            it != m_workerLastBytes.cend();
            ++it) {
            m_totalBytesHashed -= it.value();
        }
        m_workerLastBytes.clear();
        emit totalBytesHashedUpdated(m_totalBytesHashed);

        if (!m_inFlight.isEmpty()) {
            QStringList requeued(m_inFlight.begin(), m_inFlight.end()); // NOLINT - not a typo
            {
                QMutexLocker lock(&m_queueMutex);
                for (const QString& path : requeued)
                    m_fileQueue.enqueue(path);
            }
            m_inFlight.clear();
            emit filesRequeued(requeued);
            qDebug().noquote() << "Re-enqueued" << requeued.size() << "in-flight files";
        } else {
            m_inFlight.clear();
        }
    } else {
        m_inFlight.clear();
        m_workerLastBytes.clear();
    }

    m_finishedProcessCount = 0;
    m_isRunning = false;
    m_watchdog.stop();
    m_shutdownFlag.store(false);
    emit workersFinished(m_aborted);
    m_aborted = false;

    qDebug().noquote() << "ALL THREADS FINISHED";
}

// ---------------------------------------------------------------------------
// Private methods
// ---------------------------------------------------------------------------

void MediaHasher::checkQueueDrained() {
    bool queueEmpty;
    {
        QMutexLocker lock(&m_queueMutex);
        queueEmpty = m_fileQueue.isEmpty();
    }

    if (queueEmpty && m_inFlight.isEmpty()
        && m_completedTasksCount >= m_totalTasksCount) {
        qDebug().noquote()
            << "Watchdog: queue drained and all"
            << m_completedTasksCount
            << "tasks complete - setting shutdown flag";
        m_watchdog.stop();
        m_shutdownFlag.store(true);
    }
}

int MediaHasher::resolveAndEnqueue(const QStringList& filePaths) {
    // Normalize and deduplicate while preserving the caller's ordering.
    // FileHelper delivers paths sorted, and the QML queue displays them in
    // that order - a QSet here would randomize the processing order.
    QStringList incoming;
    QSet<QString> seen;
    for (const QString& path : filePaths) {
        // Handle both raw strings and QUrl-encoded strings.
        const QString localPath = path.startsWith("file://")
            ? QUrl(path).toLocalFile()
            : path;
        if (!seen.contains(localPath)) {
            seen.insert(localPath);
            incoming.append(localPath);
        }
    }

    // Deduplicate against everything already accumulated.
    const QSet<QString> existing(m_filePaths.begin(), m_filePaths.end());
    QStringList newPaths;
    for (const QString& path : incoming) {
        if (!existing.contains(path))
            newPaths.append(path);
    }

    if (newPaths.isEmpty())
        return 0;

    double addedBytes = 0.0;
    for (const QString& path : newPaths) {
        const QFileInfo fileInfo(path); // NOLINT - used directly in if branch
        if (fileInfo.exists()) {
            const auto size = static_cast<double>(fileInfo.size());
            addedBytes += size;
            m_enqueuedSizes.insert(path, size);
        }
    }

    m_filePaths.append(newPaths);
    {
        QMutexLocker lock(&m_queueMutex);
        for (const QString& path : newPaths)
            m_fileQueue.enqueue(path);
    }

    m_totalBytes += addedBytes;
    return static_cast<int>(newPaths.size());
}
