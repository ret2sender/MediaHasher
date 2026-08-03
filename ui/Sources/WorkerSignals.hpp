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

/// @file WorkerSignals.hpp
/// @brief Signal bridge for Worker/QRunnable threads.

#include <QObject>
#include <QString>

/// @brief Container that provides Qt signals for use with Worker/QRunnable.
///
/// QRunnable is not a QObject and therefore cannot emit signals directly.
/// A Worker owns one instance of this class and emits through it. All
/// signals use queued connections to cross from the worker thread to the
/// main thread.
class WorkerSignals : public QObject {
    Q_OBJECT

public:
    /// @brief Constructs a WorkerSignals instance.
    /// @param parent Optional QObject parent for ownership.
    explicit WorkerSignals(QObject* parent = nullptr) : QObject(parent) {
    }

signals:
    /// @brief Emitted once per file with the total file size in bytes.
    /// @param fileSize  Size of the file being hashed, in bytes.
    /// @param processId Worker slot index (identifies which progress bar to update).
    void checksumFileSize(double fileSize, int processId);

    /// @brief Emitted per chunk with the cumulative bytes hashed so far.
    /// @param bytesHashed Bytes processed so far for the current file.
    /// @param processId   Worker slot index.
    void checksumProgressUpdate(double bytesHashed, int processId);

    /// @brief Emitted when the worker picks up a file path for processing.
    ///
    /// The main thread uses this to track in-flight files and update
    /// QML item status to "processing".
    ///
    /// @param filePath Absolute path of the file that was dequeued.
    void fileProcessingStarted(const QString& filePath);

    /// @brief Emitted when a file fails to hash (I/O error, digest failure).
    ///
    /// Not emitted on cancellation - an abort terminates the run loop
    /// instead of failing the current file.
    ///
    /// @param filePath     Absolute path of the file that failed.
    /// @param errorMessage Human-readable error description.
    /// @param processId    Worker slot index.
    void taskFailed(const QString& filePath, const QString& errorMessage,
                    int processId);

    /// @brief Emitted when a single file finishes hashing.
    ///
    /// The worker classifies the outcome itself rather than leaving it to
    /// the receiver. During hash file conversion, only the worker knows
    /// which algorithm a mismatch refers to: a stale companion mismatch is
    /// reported against that companion's old algorithm, not the selected
    /// one, and the two may not even share a digest length.
    ///
    /// @param filePath         Absolute path of the hashed file.
    /// @param kind             Outcome: "complete" (no companion existed, one
    ///                         was written), "match" / "mismatch" (compared
    ///                         against an existing companion), or "converted"
    ///                         (companion(s) in other formats replaced by the
    ///                         selected algorithm's).
    /// @param algorithm        Display name of the algorithm the checksum
    ///                         values refer to (e.g. "BLAKE3"; for a stale
    ///                         companion mismatch, the old algorithm).
    /// @param checksum         Newly computed checksum (hex string).
    /// @param checksumFromFile Previously saved checksum from the companion
    ///                         file, or an empty string if none existed.
    /// @param processId        Worker slot index.
    void taskFinished(const QString& filePath, const QString& kind,
                      const QString& algorithm, const QString& checksum,
                      const QString& checksumFromFile, int processId);

    /// @brief Emitted when worker progress resets or updates.
    /// @param progress  Progress value (0-100 integer percent).
    /// @param processId Worker slot index.
    void taskProgressChanged(int progress, int processId);

    /// @brief Received by the worker to trigger abort.
    ///
    /// Connected from MediaHasher::workersAbort to each worker's signals
    /// instance. The worker wires this to its internal abort flag.
    void workerAbort();

    /// @brief Emitted when the worker exits its run loop.
    ///
    /// Fired both on normal completion (queue exhausted) and on abort.
    /// The main thread counts these to know when all workers have exited.
    void workerFinished();
};
