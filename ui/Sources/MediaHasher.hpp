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

/// @file MediaHasher.hpp
/// @brief Main backend logic for the Qt MediaHasher UI.

#include <atomic>

#include <QHash> // NOLINT - type of m_workerLastBytes
#include <QMutex>
#include <QObject> // NOLINT - base class
#include <QQueue>
#include <QSet>
#include <QString>
#include <QStringList> // NOLINT - used in slot signatures
#include <QThreadPool>
#include <QTimer>
#include <QUrl> // NOLINT - used in resolveAndEnqueue
#include <QtQml/qqmlregistration.h>

#include "HashJobConfig.hpp"

class QJSEngine;
class QQmlEngine;
class Worker;

/// @brief Main application logic for the Qt MediaHasher UI.
///
/// Handles communication between the QML frontend and backend logic,
/// including parallelized checksum computation using worker threads.
/// Manages the file queue, worker lifecycle, hashing configuration
/// (algorithm and companion conversion behavior), progress tracking,
/// and abort/resume semantics.
class MediaHasher : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Backend)
    QML_SINGLETON

public:
    /// @brief Default number of parallel worker threads.
    static constexpr int DefaultParallelProcesses = 3;

    /// @brief Singleton factory called by the QML engine on first access.
    ///
    /// Returns the instance previously supplied via set_instance() and marks
    /// it as C++-owned so the engine never deletes it. The instance must be
    /// set before the root QML component is loaded.
    ///
    /// @param qmlEngine The requesting QML engine (unused).
    /// @param jsEngine  The requesting JS engine (unused).
    /// @return The application-wide MediaHasher instance.
    static MediaHasher* create(QQmlEngine* qmlEngine, QJSEngine* jsEngine);

    /// @brief Supplies the instance returned by create().
    ///
    /// Called once from main() before the QML engine loads the root
    /// component. The instance remains owned by the caller.
    ///
    /// @param instance The application-wide MediaHasher instance.
    static void set_instance(MediaHasher* instance);

    /// @brief Constructs the MediaHasher backend.
    ///
    /// @note Deliberately not default-constructible: a QML_SINGLETON type
    /// with a default constructor qualifies for constructor-mode
    /// registration, which lets the QML engine silently construct its own
    /// instance instead of calling create() - bypassing the main()-owned
    /// instance supplied via set_instance(). Observed on MSVC/Qt 6.11.
    /// Requiring @p parallelProcesses forces factory-mode registration,
    /// matching SettingsManager and FileExtensionFilterProxyModel.
    ///
    /// @param parallelProcesses Number of parallel worker threads. Fixed for
    ///                          the lifetime of the run to prevent race conditions.
    /// @param parent            Optional QObject parent for ownership.
    explicit MediaHasher(int parallelProcesses,
                         QObject* parent = nullptr);

public slots:
    /// @brief Aborts the current processing run.
    ///
    /// Stops the watchdog, sets the shutdown flag so workers wake and exit
    /// promptly, and emits the abort signal to all connected workers.
    void abort();

    /// @brief Removes file paths from the pending queue before processing
    ///        begins or between runs.
    ///
    /// Only effective when no run is in progress. Removes the given paths
    /// in place from the internal file list and the backing queue, and
    /// subtracts their enqueue-time sizes from the total. Safe to call in
    /// the aborted state: completed and in-flight files are unaffected.
    /// Emits totalBytesUpdated so the main progress bar denominator stays
    /// in sync.
    ///
    /// @param filePaths String file paths to remove.
    void dequeue_files(const QStringList& filePaths);

    /// @brief Adds file paths to the queue before processing begins.
    ///
    /// Safe to call multiple times - each call deduplicates and accumulates
    /// rather than replacing prior state. Emits totalBytesUpdated so the
    /// main progress bar denominator stays in sync.
    ///
    /// @param filePaths String file paths from a Qt file dialog or drop.
    void enqueue_files(const QStringList& filePaths);

    /// @brief Adds new file paths while a run is in progress.
    ///
    /// Does NOT re-initialize worker progress bars. Updates the main progress
    /// bar denominator by emitting totalBytesUpdated.
    ///
    /// @param filePaths Raw string paths to add mid-run.
    void enqueue_files_mid_run(const QStringList& filePaths);

    /// @brief Returns the fixed number of parallel worker threads.
    ///
    /// Called by QML (e.g. Progress.qml's Component.onCompleted) to
    /// initialize the worker progress bars at startup.
    ///
    /// @return The number of parallel worker threads.
    [[nodiscard]] int get_parallel_processes() const;

    /// @brief Resets all backend state so the user can start a fresh run.
    ///
    /// Clears file paths, counters, in-flight tracking, and drains any
    /// leftover items from the file queue. Must only be called when no
    /// run is in progress.
    void reset_state();

    /// @brief Updates whether stale companion files are converted to the
    ///        selected algorithm's format.
    ///
    /// Only safe to call when no run is in progress. The new value takes
    /// effect on the next start() call.
    ///
    /// @param value @c true to convert stale companion files.
    void set_convert_existing_hashes(bool value);

    /// @brief Updates the hash algorithm used for subsequent runs.
    ///
    /// Only safe to call when no run is in progress. The new value takes
    /// effect on the next start() call. Unknown keys are rejected with a
    /// warning and the current algorithm is kept.
    ///
    /// @param key Settings key of the algorithm ("blake3", "xxh3",
    ///            "xxh128", or "sha1").
    void set_hash_algorithm(const QString& key);

    /// @brief Updates the number of parallel worker threads.
    ///
    /// Only safe to call when no run is in progress. The new value
    /// takes effect on the next start() call.
    ///
    /// @param value Desired number of parallel worker threads.
    void set_parallel_processes(int value);

    /// @brief Launches a fixed pool of worker threads to compute checksums.
    ///
    /// Workers are spawned once per run; they drain the file queue until it's
    /// empty and the shutdown flag is set. Each worker receives a copy of the
    /// current hashing configuration, so mid-run settings changes cannot mix
    /// algorithms within one run. On a resume (after abort), the completed
    /// task counter is preserved so the watchdog condition remains correct.
    void start();

signals:
    /// @brief Emitted with the size of the current file being processed.
    /// @param fileSize  File size in bytes.
    /// @param processId Worker slot index.
    void checksumFileSize(double fileSize, int processId);

    /// @brief Emitted when a file chunk is hashed (for progress updates).
    /// @param bytesHashed Bytes hashed so far for the current file.
    /// @param processId   Worker slot index.
    void checksumProgressUpdate(double bytesHashed, int processId);

    /// @brief Emitted when a worker picks up a file for processing.
    /// @param filePath Absolute path of the file being processed.
    void fileProcessingStarted(const QString& filePath);

    /// @brief Emitted on abort with the list of in-flight file paths.
    ///
    /// QML uses this to reset those items back to "pending".
    ///
    /// @param filePaths List of file paths that were re-enqueued.
    void filesRequeued(const QStringList& filePaths); // NOLINT - not a typo

    /// @brief Emitted on every progress update with the global bytes-hashed total.
    ///
    /// QML assigns this directly to the main progress bar's value.
    ///
    /// @param bytesHashed Running total of bytes hashed across all workers.
    void totalBytesHashedUpdated(double bytesHashed);

    /// @brief Emitted whenever the set of queued files changes.
    ///
    /// Carries the total size in bytes of all queued files so QML can set
    /// the main progress bar's denominator.
    ///
    /// @param newTotalBytes Total size in bytes of all queued files.
    void totalBytesUpdated(double newTotalBytes);

    /// @brief Updates a specific worker progress bar.
    /// @param progress  Progress value.
    /// @param processId Worker slot index.
    void workerProgressChanged(int progress, int processId);

    /// @brief Emitted when a file fails to hash.
    /// @param filePath     Absolute path of the file that failed.
    /// @param errorMessage Human-readable error description.
    /// @param processId    Worker slot index.
    void workerTaskFailed(const QString& filePath, const QString& errorMessage,
                          int processId);

    /// @brief Emitted when a file finishes hashing.
    ///
    /// The outcome is classified by the worker (see
    /// WorkerSignals::taskFinished for the kind semantics).
    ///
    /// @param filePath         Absolute path of the hashed file.
    /// @param kind             "complete", "match", "mismatch", or "converted".
    /// @param algorithm        Display name of the algorithm the checksum
    ///                         values refer to (e.g. "BLAKE3").
    /// @param checksum         Newly computed checksum.
    /// @param checksumFromFile Previously saved checksum, or empty string.
    /// @param processId        Worker slot index.
    void workerTaskFinished(const QString& filePath, const QString& kind,
                            const QString& algorithm, const QString& checksum,
                            const QString& checksumFromFile, int processId);

    /// @brief Signals to abort all running workers.
    void workersAbort();

    /// @brief Emitted when all worker threads have completed.
    /// @param aborted @c true if the run was aborted, @c false if completed normally.
    void workersFinished(bool aborted);

    /// @brief Signals the start of processing.
    void workersStart();

private slots:
    /// @brief Resets per-worker byte tracker and re-emits checksumFileSize.
    void onChecksumFileSize(double fileSize, int processId);

    /// @brief Computes global bytes-hashed delta and re-emits progress signals.
    void onChecksumProgressUpdate(double bytesHashed, int processId);

    /// @brief Tracks in-flight files and re-emits fileProcessingStarted.
    void onFileDequeued(const QString& filePath);

    /// @brief Rolls back progress accounting for a failed file and re-emits
    ///        the failure to QML as workerTaskFailed.
    void onTaskFailed(const QString& filePath, const QString& errorMessage,
                      int processId);

    /// @brief Maintains completed task count and re-emits workerTaskFinished.
    void onTaskFinished(const QString& filePath, const QString& kind,
                        const QString& algorithm, const QString& checksum,
                        const QString& checksumFromFile, int processId);

    /// @brief Joins threads and cleans up when all workers have exited.
    void onWorkerFinished();

private:
    /// @brief Watchdog callback - sets shutdown flag when queue is drained.
    void checkQueueDrained();

    /// @brief Shared helper: converts paths, deduplicates, enqueues, returns count added.
    ///
    /// Preserves the input ordering so files are processed in the same
    /// (sorted) order the queue displays them in.
    ///
    /// @param filePaths Mixed list of raw string or QUrl-encoded file paths.
    /// @return Number of newly enqueued paths.
    int resolveAndEnqueue(const QStringList& filePaths);

    /// @brief The application-wide instance handed out by create().
    static MediaHasher* s_instance;

    bool m_aborted = false;
    int m_completedTasksCount = 0;

    /// @brief Size in bytes of each enqueued file, recorded at enqueue time.
    ///        Used to correct m_totalBytes when a file fails, since the file
    ///        may no longer be stat-able at failure time.
    QHash<QString, double> m_enqueuedSizes;

    QStringList m_filePaths;
    QQueue<QString> m_fileQueue;
    int m_finishedProcessCount = 0;

    /// @brief Hashing configuration handed to each worker at start().
    ///        Updated by the set_* slots when no run is in progress.
    HashJobConfig m_hashConfig;

    QSet<QString> m_inFlight;
    bool m_isRunning = false;
    int m_parallelProcesses;
    QMutex m_queueMutex;

    /// @brief Workers keep polling until this is set. Set by the watchdog
    ///        timer when the queue is empty and no workers are mid-hash.
    std::atomic<bool> m_shutdownFlag{false};

    QThreadPool m_threadPool;
    double m_totalBytes = 0.0;
    double m_totalBytesHashed = 0.0;
    int m_totalTasksCount = 0;

    /// @brief Per-worker tracker: last cumulative byte value reported by each
    ///        worker for its current file. Used to compute deltas for
    ///        m_totalBytesHashed. Indexed by processId.
    QHash<int, double> m_workerLastBytes;

    QTimer m_watchdog;
    QList<Worker*> m_workers;
};
