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

/// @file Worker.hpp
/// @brief QRunnable worker that dequeues and hashes files.

#include <atomic>

#include <QMutex>
#include <QQueue> // NOLINT - used in constructor and members
#include <QRunnable>
#include <QString>

#include "HashJobConfig.hpp"
#include "WorkerSignals.hpp"

/// @brief Worker that dequeues file paths and computes their checksums.
///
/// Runs on a QThreadPool thread. Communicates with the main thread exclusively
/// through WorkerSignals (since QRunnable is not a QObject). Each worker loops
/// until either the abort flag is set or the shutdown flag fires and the queue
/// is empty.
///
/// Hashing and companion file I/O are delegated to the MediaHasher core
/// library (FileHasher and ChecksumFile respectively), keeping this class
/// focused on threading, queue management, outcome classification, and
/// signal emission.
///
/// Per file, the worker discovers all existing companion files (extension
/// lookup), hashes the media file exactly once, feeding every needed digest
/// context in that single pass, and classifies the outcome as "complete",
/// "match", "mismatch", or "converted" (see HashJobConfig for the conversion
/// semantics). The classification happens here rather than in QML because
/// only the worker knows which algorithm a comparison refers to.
class Worker : public QRunnable {
public:
    /// @brief Constructs a Worker.
    ///
    /// @param queue        Shared queue of file paths, guarded by @p queueMutex.
    ///                     Not owned - owned by MediaHasher.
    /// @param queueMutex   Mutex protecting @p queue. Not owned.
    /// @param shutdownFlag Atomic flag set by the watchdog timer when the queue
    ///                     is drained and no more files will arrive.
    /// @param config       Hashing configuration for this run (algorithm and
    ///                     conversion behavior). Copied - a mid-run settings
    ///                     change cannot affect a running worker.
    explicit Worker(QQueue<QString>* queue, QMutex* queueMutex,
                    std::atomic<bool>* shutdownFlag, HashJobConfig config);

    /// @brief Destructor. Deletes the owned WorkerSignals instance.
    ~Worker() override;

    /// @brief Explicitly disconnects signals and drops references.
    ///
    /// Called from the main thread after waitForDone() ensures no worker
    /// thread is still running. Prevents stale signal emissions and allows
    /// cleanup of the QObject trees.
    void cleanup();

    /// @brief Main execution logic of the worker thread.
    ///
    /// Dequeues files with a short sleep so the worker can detect abort
    /// and also pick up files added mid-run. On each file: notifies QML,
    /// reads any existing companion files, computes all needed digests in
    /// a single pass via FileHasher::hashMulti, performs the companion
    /// write/convert/cleanup actions, and emits the classified result.
    /// Exits when aborted or when the shutdown flag is set and the queue
    /// is empty.
    void run() override;

    /// @brief Signal bridge for communicating with the main thread.
    ///
    /// Public so MediaHasher can wire up connections directly.
    WorkerSignals* m_signals = nullptr;

    /// @brief Worker slot index, used to route progress updates to the
    ///        correct progress bar in QML.
    int processId = 0;

private:
    /// @brief Sets the worker's abort flag.
    ///
    /// Called on the worker thread when the workerAbort signal fires.
    /// The run loop checks this flag at multiple points to exit promptly.
    void abort();

    /// @brief Processes a single dequeued file: companion discovery, the
    ///        single-pass multi-digest hash, conversion actions, and the
    ///        taskFinished / taskFailed emission.
    ///
    /// Factored out of run() so the dequeue/shutdown loop stays readable.
    ///
    /// @param filePath Absolute path of the file to process.
    /// @throws MediaHash::CancellationError Propagated from the hasher when
    ///                                      the abort flag is set mid-hash.
    void processFile(const QString& filePath) const;

    /// @brief Minimum interval between progress signal emissions.
    ///
    /// Hashing on fast storage produces one callback per chunk (thousands
    /// per second across workers), each posting a queued event to the main
    /// thread. The UI cannot display more than ~60 updates/sec, so progress
    /// is throttled at the source. A final 100% emission is always sent
    /// unthrottled after hashing completes.
    static constexpr qint64 ProgressEmitIntervalMs = 50;

    std::atomic<bool> m_abort{false};
    HashJobConfig m_config;
    QMutex* m_mutex; ///< Not owned - owned by MediaHasher.
    QQueue<QString>* m_queue; ///< Shared across workers, guarded by m_mutex.
    std::atomic<bool>* m_shutdownFlag; ///< Set by watchdog when queue is drained.
};
