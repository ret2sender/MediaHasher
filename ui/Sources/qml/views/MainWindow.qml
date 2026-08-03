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


import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts

import com.mediahasher.app


ApplicationWindow {
    id: applicationWindow
    color: "transparent"
    flags: Qt.platform.os === "osx" ? Qt.Window : Qt.Window | Qt.FramelessWindowHint
    minimumHeight: mainColumn.implicitHeight
    minimumWidth: 860
    maximumHeight: mainColumn.implicitHeight
    maximumWidth: 860
    visible: true

    // Component global variables.
    property bool checksumProcessRunning: false
    property int logCompleteCount: 0
    property int logConvertedCount: 0
    property int logFailedCount: 0
    property int logMatchCount: 0
    property int logMismatchCount: 0
    property int nativeTitleBarHeight: 0

    // Effective offset: only apply on macOS where the transparent title bar
    // still occupies space above the Qt content area (MacOSStyling).
    property int titleBarOffset: Qt.platform.os === "osx" ? nativeTitleBarHeight : 0

    Component.onCompleted: console.log("titleBarOffset:", titleBarOffset, "nativeTitleBarHeight:", nativeTitleBarHeight)

    Connections {
        target: Backend

        function onChecksumFileSize(file_size, pb_id) {
            progress.progressBarContainer.itemAt(pb_id).to = file_size;
        }

        function onChecksumProgressUpdate(chunk_size, pb_id) {
            progress.progressBarContainer.itemAt(pb_id).value = chunk_size;
        }

        function onFileProcessingStarted(file_path) {
            fileQueue.markProcessing(file_path);
        }

        function onFilesRequeued(filePaths) {
            for (let i = 0; i < filePaths.length; i++) {
                fileQueue.markPending(filePaths[i]);
            }
        }

        function onTotalBytesHashedUpdated(bytes_hashed) {
            progress.mainProgressBar.value = bytes_hashed;
        }

        function onTotalBytesUpdated(new_total_bytes) {
            progress.mainProgressBar.to = new_total_bytes;
        }

        function onWorkerProgressChanged(progress_value, pb_id) {
            progress.progressBarContainer.itemAt(pb_id).value = progress_value;
        }

        function onWorkerTaskFailed(file_path, error_message, process_id) {
            // Mark item as failed in the file queue widget.
            fileQueue.markFailed(file_path);

            // Update log.
            jobsLogger.appendFailure(file_path, error_message);
            applicationWindow.logFailedCount++;
        }

        function onWorkerTaskFinished(file_path, kind, algorithm, checksum, checksum_from_file, process_id) {
            // Note: process_id is unused here, but used in the Python backend.

            // Mark item as done in the file queue widget.
            fileQueue.markDone(file_path);

            // The kind is classified by the worker - only it knows which
            // algorithm a comparison refers to (a stale companion mismatch
            // is reported against the old algorithm during conversion).
            if (kind === "complete") {
                applicationWindow.logCompleteCount++;
            } else if (kind === "match") {
                applicationWindow.logMatchCount++;
            } else if (kind === "mismatch") {
                applicationWindow.logMismatchCount++;
            } else if (kind === "converted") {
                applicationWindow.logConvertedCount++;
            }
            jobsLogger.appendResult(kind, algorithm, file_path, checksum, checksum_from_file);
        }

        function onWorkersFinished(aborted) {
            applicationWindow.checksumProcessRunning = false;

            if (!aborted) {
                jobsLogger.appendSummary(
                    applicationWindow.logCompleteCount,
                    applicationWindow.logMatchCount,
                    applicationWindow.logMismatchCount,
                    applicationWindow.logConvertedCount,
                    applicationWindow.logFailedCount
                );
            }
        }

        function onWorkersStart() {

            applicationWindow.checksumProcessRunning = true;

            // On a fresh run, reset everything. On a resume (progress bar
            // already has completed work), keep the accumulated values.
            let isResume = progress.mainProgressBar.value > 0;

            for (let i = 0; i < progress.progressBarContainer.count; i++) {
                progress.progressBarContainer.itemAt(i).value = 0;
            }

            if (!isResume) {
                progress.mainProgressBar.value = 0;
                // .to is already set by onTotalBytesUpdated from enqueue_files.
                applicationWindow.logCompleteCount = 0;
                applicationWindow.logConvertedCount = 0;
                applicationWindow.logFailedCount = 0;
                applicationWindow.logMatchCount = 0;
                applicationWindow.logMismatchCount = 0;
            }
        }
    }

    SettingsDialog {
        id: settingsDialog
    }

    Rectangle {
        id: windowBackground
        anchors.fill: parent
        anchors.topMargin: -applicationWindow.titleBarOffset
        color: Theme.windowBackground
        radius: Qt.platform.os === "osx" ? 0 : 8

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            spacing: 0

            // Title bar
            TitleBar {
                id: titleBar
                Layout.fillWidth: true
                hasItems: fileQueue.hasItems
                isAborted: fileQueue.isAborted
                isComplete: fileQueue.isComplete
                isRunning: applicationWindow.checksumProcessRunning

                onAbortRequested: Backend.abort()

                onMoveRequested: applicationWindow.startSystemMove()

                onResetRequested: {
                    // Reset QML state.
                    fileQueue.reset()
                    progress.mainProgressBar.value = 0
                    progress.mainProgressBar.to = 0
                    for (let i = 0; i < progress.progressBarContainer.count; i++) {
                        progress.progressBarContainer.itemAt(i).value = 0
                    }
                    applicationWindow.logCompleteCount = 0
                    applicationWindow.logConvertedCount = 0
                    applicationWindow.logFailedCount = 0
                    applicationWindow.logMatchCount = 0
                    applicationWindow.logMismatchCount = 0

                    // Clear the jobs log.
                    jobsLogger.clear()

                    // Reset backend state.
                    Backend.reset_state()
                }

                onRunRequested: Backend.start()

                onSettingsRequested: {
                    settingsDialog.show()
                    settingsDialog.raise()
                    settingsDialog.requestActivate()
                }
            }

            Connections {
                target: settingsDialog

                function onApplied() {
                    let newCount = SettingsManager.get_concurrent_processes()
                    Backend.set_parallel_processes(newCount)
                    progress.progressBarCount = newCount

                    // Forward the hashing configuration to the backend; it
                    // takes effect on the next run (the backend guards
                    // against mid-run changes).
                    Backend.set_hash_algorithm(SettingsManager.get_hash_algorithm())
                    Backend.set_convert_existing_hashes(SettingsManager.get_convert_existing_hashes())
                }
            }

            // Main content
            RowLayout {
                id: mainContent
                Layout.bottomMargin: 24
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 10
                spacing: 12

                MediaTreeView {
                    id: fileBrowser
                    Layout.preferredHeight: 700
                    Layout.preferredWidth: 300
                    model: FileSystemModel
                    rootIndex: FileSystemModel.rootIndex
                }

                ColumnLayout {
                    id: processColumn
                    spacing: 12

                    FileQueue {
                        id: fileQueue
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                    }

                    Progress {
                        id: progress
                        Layout.fillWidth: true   // takes remaining horizontal space
                        Layout.preferredHeight: 80
                    }

                    JobsLog {
                        id: jobsLogger
                        Layout.fillWidth: true   // takes remaining horizontal space
                        Layout.preferredHeight: 346
                    }
                }
            }
        }
    }

    // Blur the background and add a dark tint to the main window when
    // the settings window is active.
    ShaderEffectSource {
        id: blurSource
        sourceItem: windowBackground
        anchors.fill: parent
        visible: false
        live: true
    }

    MultiEffect {
        anchors.fill: parent
        anchors.topMargin: -applicationWindow.titleBarOffset
        source: blurSource
        blurEnabled: settingsDialog.visible
        blur: 0.6
        blurMax: 32
        visible: settingsDialog.visible
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -applicationWindow.titleBarOffset
        color: "black"
        opacity: 0.3
        visible: settingsDialog.visible
    }
}
