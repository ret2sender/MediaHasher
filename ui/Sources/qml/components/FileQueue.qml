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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic

import com.mediahasher.app


Rectangle {
    id: root
    color: Theme.panelBackground
    radius: 8

    // -------------------------------------------------------------------------
    // Public interface
    // -------------------------------------------------------------------------
    // Set to true after an abort (paused state), cleared on reset or fresh run.
    property bool isAborted: false

    // Set to true once the full run has completed to block further drops.
    property bool isComplete: false

    // Set to true when some jobs are running.
    property bool isRunning: false


    // True when the queue has at least one item.
    readonly property bool hasItems: internalModel.count > 0

    // Marks a file as "done" - called when a worker finishes it.
    function markDone(filePath) {
        __setStatus(filePath, "done")
    }

    // Marks a file as "failed" - called when a worker reports a hash error.
    function markFailed(filePath) {
        __setStatus(filePath, "failed")
    }

    // Marks a file as "pending" - called on abort to reset in-flight items.
    function markPending(filePath) {
        __setStatus(filePath, "pending")
    }

    // Marks a file as "processing" - called when a worker picks it up.
    function markProcessing(filePath) {
        __setStatus(filePath, "processing")
    }

    // Resets the queue to its initial empty state.
    function reset() {
        internalModel.clear()
        __pathIndex = {}
        clearSelection()
        root.isComplete = false
        root.isAborted = false
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------
    readonly property int gutterWidth: 54
    readonly property int rowNumberSpacing: gutterWidth - 30

    // Tracks the indices of currently selected items.
    property var __selectedIndices: ({})    // JS object used as a Set (index -> true)
    // The last index that was clicked - used as the anchor for Shift+click ranges.
    property int __lastClickedIndex: -1

    // Maps filePath -> model index for O(1) status updates during a run
    // (each finished/failed/started signal would otherwise scan the model).
    // Mutated in place - never used in bindings, so no reassignment needed.
    property var __pathIndex: ({})

    // Returns the model index for filePath, or -1. Verifies the cached
    // index and falls back to a linear scan (self-healing) if stale.
    function __indexOfPath(filePath) {
        const cached = __pathIndex[filePath]
        if (cached !== undefined
                && cached < internalModel.count
                && internalModel.get(cached).filePath === filePath) {
            return cached
        }
        for (let i = 0; i < internalModel.count; i++) {
            if (internalModel.get(i).filePath === filePath) {
                __pathIndex[filePath] = i
                return i
            }
        }
        return -1
    }

    // Rebuilds the path index from scratch - called after removals,
    // which shift the indices of all subsequent items.
    function __rebuildPathIndex() {
        let map = {}
        for (let i = 0; i < internalModel.count; i++) {
            map[internalModel.get(i).filePath] = i
        }
        __pathIndex = map
    }

    // Sets the status of the item with the given path, if present.
    function __setStatus(filePath, status) {
        const idx = __indexOfPath(filePath)
        if (idx >= 0)
            internalModel.setProperty(idx, "status", status)
    }

    // Clears the current selection.
    function clearSelection() {
        __selectedIndices = {}
        __lastClickedIndex = -1
    }

    // Removes all currently selected items that are still "pending".
    // Items that are "processing" or "done" are left untouched.
    function removeSelected() {
        let pathsToRemove = []
        // Collect selected indices in descending order so removal
        // doesn't shift later indices.
        let indices = Object.keys(__selectedIndices)
            .map(Number)
            .sort((a, b) => b - a)

        for (let idx of indices) {
            if (idx < 0 || idx >= internalModel.count)
                continue
            let item = internalModel.get(idx)
            if (item.status !== "pending")
                continue
            pathsToRemove.push(item.filePath)
            internalModel.remove(idx)
        }

        clearSelection()
        __rebuildPathIndex()

        if (pathsToRemove.length > 0) {
            Backend.dequeue_files(pathsToRemove)
        }
    }

    // Returns the number of currently selected items.
    function selectionCount() {
        return Object.keys(__selectedIndices).length
    }

    // Selects all pending items.
    function selectAll() {
        let sel = {}
        for (let i = 0; i < internalModel.count; i++) {
            if (internalModel.get(i).status === "pending")
                sel[i] = true
        }
        __selectedIndices = sel
    }

    // Clicking outside the ListView area (header, margins) clears the selection.
    // Empty space within the ListView is handled by listEmptySpaceHandler.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        z: -1

        onClicked: {
            root.clearSelection()
            listView.forceActiveFocus()
        }
    }

    FileHelper { id: fileHelper }

    // The actual model driving the ListView. Each item: { filePath, status }
    ListModel {
        id: internalModel
    }

    // Wire isRunning and isComplete directly to backend signals so the drop
    // handler never depends on the parent remembering to set these.
    Connections {
        target: Backend

        function onWorkersFinished(wasAborted) {
            root.isRunning = false
            if (wasAborted) {
                root.isAborted = true
            } else {
                root.isComplete = true
            }
        }

        function onWorkersStart() {
            root.isRunning = true
            root.isAborted = false
            root.clearSelection()
        }
    }

    Item {
        id: stripedPattern
        anchors.fill: parent
        visible: root.isComplete

        Rectangle {
            anchors.fill: parent
            color: Theme.panelBackgroundDone
            radius: 8
        }

        Canvas {
            anchors.fill: parent
            opacity: 0.12

            property color hatchColor: Theme.textPrimary
            property int lineWidth: 1
            property int spacing: 10

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                ctx.strokeStyle = hatchColor;
                ctx.lineWidth = lineWidth;

                // 45° diagonal lines
                // Start far enough left so lines cover the whole area.
                for (var x = -height; x < width; x += spacing) {
                    ctx.beginPath();
                    ctx.moveTo(x, 0);
                    ctx.lineTo(x + height, height);
                    ctx.stroke();
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    // -------------------------------------------------------------------------
    // Drop area
    // -------------------------------------------------------------------------
    DropArea {
        id: dropArea
        anchors.fill: parent
        // Block drops entirely once the run is complete.
        enabled: !root.isComplete

        onDropped: (drop) => {
            drop.acceptProposedAction()
            if (!drop.hasUrls) return

            let urlStrings = drop.urls.map(u => u.toString())
            let resolved = fileHelper.resolveMkvFiles(urlStrings)
            if (resolved.length === 0) return

            // Deduplicate against everything already in the model.
            let existing = new Set()
            for (let i = 0; i < internalModel.count; i++) {
                existing.add(internalModel.get(i).filePath)
            }
            let newPaths = resolved.filter(p => !existing.has(p))
            if (newPaths.length === 0) return

            for (let p of newPaths) {
                internalModel.append({ filePath: p, status: "pending" })
                root.__pathIndex[p] = internalModel.count - 1
            }

            // Pass already-resolved string paths to the backend.
            // Both enqueue_files and enqueue_files_mid_run accept strings;
            // the backend's resolveAndEnqueue handles the rest.
            if (root.isRunning) {
                Backend.enqueue_files_mid_run(newPaths)
            } else {
                Backend.enqueue_files(newPaths)
            }
        }

        onEntered: (drag) => {
            drag.accept(Qt.CopyAction)
        }
    }

    // Visual drop-hover feedback (hidden when drops are blocked)
    Rectangle {
        anchors.fill: parent
        border.color: (dropArea.containsDrag && !root.isComplete) ? Theme.accent : "transparent"
        border.width: 2
        color: "transparent"
        radius: root.radius
        z: 10

        AppIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 128
            opacity: 0.25
            source: "../../icons/google_material/place_item.svg"
            visible: dropArea.containsDrag && !root.isComplete
        }
    }

    // -------------------------------------------------------------------------
    // Header
    // -------------------------------------------------------------------------
    Label {
        id: header
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 10
        bottomPadding: 6
        color: Theme.accent
        font.bold: true
        font.family: Theme.interFamily
        font.pixelSize: 16
        font.weight: Font.Bold
        text: "File Queue"
    }

    // -------------------------------------------------------------------------
    // Gutter separator
    // -------------------------------------------------------------------------
    Rectangle {
        id: gutterSeparator
        anchors.bottom: listView.bottom
        anchors.top: listView.top
        color: Theme.textPrimary
        opacity: 0.15
        visible: internalModel.count > 0
        width: 1
        x: root.gutterWidth
    }

    // -------------------------------------------------------------------------
    // File list
    // -------------------------------------------------------------------------
    ListView {
        id: listView
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 4
        clip: true
        focus: true
        model: internalModel
        spacing: -4

        // Keyboard handling for Delete / Backspace.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                if (root.selectionCount() > 0 && !root.isRunning && !root.isComplete) {
                    root.removeSelected()
                    event.accepted = true
                }
            }
            // Cmd+A / Ctrl+A to select all pending items.
            else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                if (!root.isRunning && !root.isComplete) {
                    root.selectAll()
                    event.accepted = true
                }
            }
        }

        ScrollBar.vertical: AutoHideScrollBar { id: verticalScrollBar }

        delegate: Item {
            id: delegateRoot
            height: 22
            width: listView.width

            required property string filePath
            required property int index
            required property string status  // "pending" | "processing" | "done" | "failed"

            readonly property bool isSelected: root.__selectedIndices.hasOwnProperty(index)

            // Text color shared by the row number and file path labels.
            readonly property color rowColor: isSelected ? Theme.textSelected
                : status === "done" ? Theme.textMuted
                : status === "failed" ? Theme.warning
                : status === "processing" ? Theme.accent
                : Theme.textPrimary

            // Selection highlight (drawn behind the hover layer)
            Rectangle {
                id: selectionHighlight
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                color: delegateRoot.isSelected ? Theme.selectionBackground : "transparent"
                radius: 4
            }

            // Row hover highlight
            Rectangle {
                id: rowHover
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                color: hoverHandler.hovered && !delegateRoot.isSelected
                       ? Theme.hoverBackground : "transparent"
                enabled: !root.isComplete
                radius: 4
                visible: !root.isComplete
            }

            HoverHandler { id: hoverHandler }

            // Click handler for selection.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton

                onClicked: (mouse) => {
                    listView.forceActiveFocus()

                    // Only allow selecting "pending" items.
                    if (delegateRoot.status !== "pending")
                        return
                    if (root.isRunning || root.isComplete)
                        return

                    let idx = delegateRoot.index
                    let sel = root.__selectedIndices

                    if (mouse.modifiers & Qt.ShiftModifier) {
                        // Shift+click: range select from anchor to current.
                        let anchor = root.__lastClickedIndex
                        if (anchor < 0) anchor = idx
                        let lo = Math.min(anchor, idx)
                        let hi = Math.max(anchor, idx)
                        // If Ctrl is NOT also held, start fresh.
                        if (!(mouse.modifiers & Qt.ControlModifier))
                            sel = {}
                        for (let i = lo; i <= hi; i++) {
                            if (internalModel.get(i).status === "pending")
                                sel[i] = true
                        }
                    } else if (mouse.modifiers & Qt.ControlModifier
                               || (Qt.platform.os === "osx"
                                   && mouse.modifiers & Qt.MetaModifier)) {
                        // Ctrl/Cmd+click: toggle individual item.
                        if (sel.hasOwnProperty(idx))
                            delete sel[idx]
                        else
                            sel[idx] = true
                    } else {
                        // Plain click: exclusive select.
                        sel = {}
                        sel[idx] = true
                    }

                    root.__lastClickedIndex = idx
                    // Reassign the object to trigger property change notification.
                    root.__selectedIndices = Object.assign({}, sel)
                }
            }

            // Row number
            Label {
                id: rowNumber
                anchors.left: parent.left
                anchors.leftMargin: root.rowNumberSpacing
                anchors.verticalCenter: parent.verticalCenter
                color: delegateRoot.rowColor
                font.family: Theme.jetbrainsMonoFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignRight
                text: delegateRoot.index + 1
                width: root.rowNumberSpacing
            }

            // File path
            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: rowNumber.right
                anchors.leftMargin: root.rowNumberSpacing
                anchors.right: parent.right
                anchors.rightMargin: root.rowNumberSpacing
                color: delegateRoot.rowColor
                elide: Text.ElideMiddle
                font.family: Theme.jetbrainsMonoFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                text: delegateRoot.filePath
            }
        }
    }

    // ---------------------------------------------------------------------------
    // ListView empty-space click handler (sibling overlay on top of the ListView)
    // ---------------------------------------------------------------------------
    // Covers the same bounds as the ListView. Uses indexAt() to decide
    // whether the click landed on a delegate row or on empty space below
    // the content. Delegate clicks are ignored (mouse is forwarded);
    // empty-space clicks clear the selection.
    MouseArea {
        id: listEmptySpaceHandler
        anchors.fill: listView
        // Leave the scroll bar strip uncovered - the overlay would otherwise
        // swallow presses meant for the scroll bar (indexAt() reports empty
        // space there when a row's content ends before the bar).
        anchors.rightMargin: verticalScrollBar.width
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true

        onPressed: (mouse) => {
            // Map the press position into content coordinates and ask
            // the ListView whether a delegate lives there.
            let contentY = mouse.y + listView.contentY
            let idx = listView.indexAt(mouse.x, contentY)
            if (idx === -1) {
                // Empty space - deselect and absorb the click.
                root.clearSelection()
                listView.forceActiveFocus()
            } else {
                // A delegate row - ignore so the delegate's own
                // MouseArea handles it.
                mouse.accepted = false
            }
        }
    }
}
