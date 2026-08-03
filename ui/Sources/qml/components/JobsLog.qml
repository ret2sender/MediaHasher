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
    //
    // Entries are structured model items rendered by a ListView delegate,
    // replacing the previous rich-text TextArea whose per-append relayout
    // cost grew with the full document size. Entries can be selected
    // (click / Ctrl+click / Shift+click) and copied as plain text via
    // Ctrl+C / Cmd+C or the context menu.
    // -------------------------------------------------------------------------

    // Appends a failure entry (hash error reported by a worker).
    function appendFailure(filePath, errorMessage) {
        __append({
            kind: "failed",
            algorithm: "",
            filePath: filePath,
            checksum: "",
            checksumFromFile: "",
            message: errorMessage,
            countComplete: 0,
            countConverted: 0,
            countFailed: 0,
            countMatch: 0,
            countMismatch: 0
        })
    }

    // Appends a result entry. kind: "complete" | "match" | "mismatch" |
    // "converted". algorithm is the display name of the hash algorithm the
    // checksum values refer to (e.g. "BLAKE3"; for a stale companion
    // mismatch, the old algorithm).
    function appendResult(kind, algorithm, filePath, checksum, checksumFromFile) {
        __append({
            kind: kind,
            algorithm: algorithm,
            filePath: filePath,
            checksum: checksum,
            checksumFromFile: checksumFromFile,
            message: "",
            countComplete: 0,
            countConverted: 0,
            countFailed: 0,
            countMatch: 0,
            countMismatch: 0
        })
    }

    // Appends the end-of-run summary line. The converted and failed
    // segments are only rendered when their counts are > 0.
    function appendSummary(completeCount, matchCount, mismatchCount, convertedCount, failedCount) {
        __append({
            kind: "summary",
            algorithm: "",
            filePath: "",
            checksum: "",
            checksumFromFile: "",
            message: "",
            countComplete: completeCount,
            countConverted: convertedCount,
            countFailed: failedCount,
            countMatch: matchCount,
            countMismatch: mismatchCount
        })
    }

    // Removes all log entries.
    function clear() {
        logModel.clear()
        clearSelection()
    }

    // Clears the current selection.
    function clearSelection() {
        __selectedIndices = {}
        __lastClickedIndex = -1
    }

    // Copies the selected entries to the clipboard as plain text,
    // in model order, separated by blank lines.
    function copySelection() {
        const indices = Object.keys(__selectedIndices)
            .map(Number)
            .sort((a, b) => a - b)
        if (indices.length === 0)
            return
        Clipboard.setText(indices.map(__entryText).join("\n\n"))
    }

    // Selects all log entries.
    function selectAll() {
        let sel = {}
        for (let i = 0; i < logModel.count; i++)
            sel[i] = true
        __selectedIndices = sel
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------
    // Entry values captured when the context menu opens, driving the
    // visibility and payload of the checksum menu items.
    property string __contextChecksum: ""
    property string __contextChecksumFromFile: ""
    property string __contextKind: ""

    // The last index that was clicked - used as the anchor for Shift+click ranges.
    property int __lastClickedIndex: -1
    // Tracks the indices of currently selected entries.
    property var __selectedIndices: ({})    // JS object used as a Set (index -> true)

    function __append(entry) {
        logModel.append(entry)
        // Defer so the new delegate exists before scrolling to it.
        Qt.callLater(listView.positionViewAtEnd)
    }

    // "CHECKSUM (BLAKE3) : " style label prefix. The algorithm suffix is
    // omitted when unknown so legacy-shaped entries still render cleanly.
    function __checksumLabel(prefix, algorithm) {
        return prefix + (algorithm !== "" ? " (" + algorithm + ")" : "") + " : "
    }

    // Entry text color by entry kind.
    function __colorFor(kind) {
        if (kind === "complete") return Theme.logComplete
        if (kind === "converted") return Theme.logConverted
        if (kind === "failed") return Theme.logFailed
        if (kind === "match") return Theme.logMatch
        if (kind === "mismatch") return Theme.logMismatch
        return Theme.textPrimary
    }

    // Plain-text form of the entry at the given index, mirroring the
    // rendered lines. Used by copySelection().
    function __entryText(index) {
        const e = logModel.get(index)
        if (e.kind === "summary") {
            let parts = [
                "Complete Checksum : " + e.countComplete,
                "Match Checksum : " + e.countMatch,
                "Mismatch Checksum : " + e.countMismatch
            ]
            if (e.countConverted > 0)
                parts.push("Converted Checksum : " + e.countConverted)
            if (e.countFailed > 0)
                parts.push("Failed Checksum : " + e.countFailed)
            return parts.join("   |   ")
        }

        let lines = [__titleFor(e.kind) + " : " + e.filePath]
        if (e.kind === "complete" || e.kind === "match" || e.kind === "converted") {
            lines.push(__checksumLabel("CHECKSUM", e.algorithm) + e.checksum)
        } else if (e.kind === "mismatch") {
            lines.push(__checksumLabel("CURRENT CHECKSUM", e.algorithm) + e.checksum)
            lines.push(__checksumLabel("CHECKSUM FROM FILE", e.algorithm) + e.checksumFromFile)
        } else if (e.kind === "failed") {
            lines.push("ERROR : " + e.message)
        }
        return lines.join("\n")
    }

    // StyledText interprets markup - escape user-controlled strings
    // (file paths and error messages may contain & or <).
    function __escapeStyledText(text) {
        return text
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    // Title line prefix by entry kind.
    function __titleFor(kind) {
        if (kind === "complete") return "Checksum Completed!"
        if (kind === "converted") return "Checksum Converted!"
        // "failed" covers I/O errors (unreadable/unreachable file) where no
        // digest was ever computed - "Checksum Failed" would falsely imply a
        // verification verdict.
        if (kind === "failed") return "Processing Failed!"
        if (kind === "match") return "Checksum Match!"
        return "Checksum Mismatch!"
    }

    // Shared look for all log entry lines.
    component EntryLabel: Label {
        font.family: Theme.interFamily
        font.pixelSize: 12
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
    }

    // Menu item matching the application theme. Explicit MenuItem children
    // are not styled by Menu's delegate property, hence this component.
    component ThemedMenuItem: MenuItem {
        id: themedMenuItem
        implicitHeight: 26

        background: Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            color: themedMenuItem.highlighted ? Theme.buttonHover : "transparent"
            radius: 4
        }

        contentItem: Label {
            color: themedMenuItem.enabled ? Theme.textPrimary : Theme.textMuted
            elide: Text.ElideRight
            font.family: Theme.interFamily
            font.pixelSize: 12
            leftPadding: 8
            text: themedMenuItem.text
            verticalAlignment: Text.AlignVCenter
        }
    }

    ListModel {
        id: logModel
    }

    // Right-click context menu. The checksum items adapt to the entry
    // that was clicked (captured in the __context* properties).
    Menu {
        id: contextMenu
        padding: 4

        background: Rectangle {
            color: Theme.controlBackground
            implicitWidth: 210
            radius: 6
        }

        ThemedMenuItem {
            enabled: Object.keys(root.__selectedIndices).length > 0
            text: "Copy"

            onTriggered: root.copySelection()
        }
        ThemedMenuItem {
            text: "Copy Checksum"
            visible: root.__contextKind === "complete"
                     || root.__contextKind === "match"
                     || root.__contextKind === "converted"

            onTriggered: Clipboard.setText(root.__contextChecksum)
        }
        ThemedMenuItem {
            text: "Copy Current Checksum"
            visible: root.__contextKind === "mismatch"

            onTriggered: Clipboard.setText(root.__contextChecksum)
        }
        ThemedMenuItem {
            text: "Copy Checksum From File"
            visible: root.__contextKind === "mismatch"

            onTriggered: Clipboard.setText(root.__contextChecksumFromFile)
        }
        ThemedMenuItem {
            enabled: logModel.count > 0
            text: "Select All"

            onTriggered: root.selectAll()
        }
    }

    // Clicking empty space (header, margins, area between/below entries)
    // clears the selection. Sits behind the ListView; entry delegates
    // consume their own clicks. Right-clicking empty space still offers
    // Copy / Select All.
    MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        anchors.fill: parent
        z: -1

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.__contextKind = ""
                contextMenu.popup()
                return
            }
            root.clearSelection()
        }
    }

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
        text: "Jobs Log"
    }

    ListView {
        id: listView
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: header.bottom
        anchors.topMargin: 4
        clip: true
        model: logModel
        spacing: 10

        Keys.onPressed: (event) => {
            if (event.matches(StandardKey.Copy)) {
                root.copySelection()
                event.accepted = true
            } else if (event.matches(StandardKey.SelectAll)) {
                root.selectAll()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.clearSelection()
                event.accepted = true
            }
        }

        ScrollBar.vertical: AutoHideScrollBar { id: logScrollBar }

        delegate: Item {
            id: entry
            height: entryColumn.implicitHeight
            width: ListView.view ? ListView.view.width - 12 : 0

            required property int index
            required property string kind
            required property string algorithm
            required property string filePath
            required property string checksum
            required property string checksumFromFile
            required property string message
            required property int countComplete
            required property int countConverted
            required property int countFailed
            required property int countMatch
            required property int countMismatch

            readonly property color entryColor: root.__colorFor(kind)
            readonly property bool isSelected: root.__selectedIndices.hasOwnProperty(index)

            // Selection highlight (drawn behind the hover layer).
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: entry.isSelected ? Theme.selectionBackground : "transparent"
                radius: 4
            }

            // Entry hover highlight.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: entryHoverHandler.hovered && !entry.isSelected
                       ? Theme.hoverBackground : "transparent"
                radius: 4
            }

            HoverHandler { id: entryHoverHandler }

            // Click handler for selection and the context menu.
            MouseArea {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                anchors.fill: parent

                onClicked: (mouse) => {
                    listView.forceActiveFocus()

                    let idx = entry.index
                    let sel = root.__selectedIndices

                    if (mouse.button === Qt.RightButton) {
                        // Right-clicking an unselected entry makes it the
                        // exclusive selection first (platform convention).
                        if (!sel.hasOwnProperty(idx)) {
                            root.__lastClickedIndex = idx
                            root.__selectedIndices = { [idx]: true }
                        }
                        root.__contextKind = entry.kind
                        root.__contextChecksum = entry.checksum
                        root.__contextChecksumFromFile = entry.checksumFromFile
                        contextMenu.popup()
                        return
                    }

                    if (mouse.modifiers & Qt.ShiftModifier) {
                        // Shift+click: range select from anchor to current.
                        let anchor = root.__lastClickedIndex
                        if (anchor < 0) anchor = idx
                        let lo = Math.min(anchor, idx)
                        let hi = Math.max(anchor, idx)
                        // If Ctrl is NOT also held, start fresh.
                        if (!(mouse.modifiers & Qt.ControlModifier))
                            sel = {}
                        for (let i = lo; i <= hi; i++)
                            sel[i] = true
                    } else if (mouse.modifiers & Qt.ControlModifier
                               || (Qt.platform.os === "osx"
                                   && mouse.modifiers & Qt.MetaModifier)) {
                        // Ctrl/Cmd+click: toggle individual entry.
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

            Column {
                id: entryColumn
                width: parent.width

                // Title line: "Checksum X! : /path/to/file.mkv"
                EntryLabel {
                    color: entry.entryColor
                    text: "<b>" + root.__titleFor(entry.kind) + " : </b>"
                          + root.__escapeStyledText(entry.filePath)
                    visible: entry.kind !== "summary"
                    width: parent.width
                }

                // Detail line for complete / match / converted results.
                EntryLabel {
                    color: entry.entryColor
                    text: "<b>" + root.__checksumLabel("CHECKSUM", entry.algorithm) + "</b>"
                          + entry.checksum
                    visible: entry.kind === "complete" || entry.kind === "match"
                             || entry.kind === "converted"
                    width: parent.width
                }

                // Detail lines for mismatch results.
                EntryLabel {
                    color: entry.entryColor
                    text: "<b>" + root.__checksumLabel("CURRENT CHECKSUM", entry.algorithm) + "</b>"
                          + entry.checksum
                    visible: entry.kind === "mismatch"
                    width: parent.width
                }
                EntryLabel {
                    color: entry.entryColor
                    text: "<b>" + root.__checksumLabel("CHECKSUM FROM FILE", entry.algorithm) + "</b>"
                          + entry.checksumFromFile
                    visible: entry.kind === "mismatch"
                    width: parent.width
                }

                // Detail line for failures.
                EntryLabel {
                    color: entry.entryColor
                    text: "<b>ERROR : </b>" + root.__escapeStyledText(entry.message)
                    visible: entry.kind === "failed"
                    width: parent.width
                }

                // End-of-run summary: colored segments on one wrapping line.
                EntryLabel {
                    readonly property string separator:
                        "&nbsp;&nbsp;&nbsp;<font color='" + Theme.textMuted + "'>|</font>&nbsp;&nbsp;&nbsp;"

                    color: Theme.textPrimary
                    text: "<b>"
                          + "<font color='" + Theme.logComplete + "'>Complete Checksum : " + entry.countComplete + "</font>"
                          + separator
                          + "<font color='" + Theme.logMatch + "'>Match Checksum : " + entry.countMatch + "</font>"
                          + separator
                          + "<font color='" + Theme.logMismatch + "'>Mismatch Checksum : " + entry.countMismatch + "</font>"
                          + (entry.countConverted > 0
                             ? separator + "<font color='" + Theme.logConverted + "'>Converted Checksum : " + entry.countConverted + "</font>"
                             : "")
                          + (entry.countFailed > 0
                             ? separator + "<font color='" + Theme.logFailed + "'>Failed Checksum : " + entry.countFailed + "</font>"
                             : "")
                          + "</b>"
                    visible: entry.kind === "summary"
                    width: parent.width
                }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // ListView empty-space click handler (sibling overlay on top of the ListView)
    // ---------------------------------------------------------------------------
    // Covers the same bounds as the ListView. Uses indexAt() to decide
    // whether the press landed on an entry or on empty space. Entry presses
    // are ignored (mouse is forwarded to the delegate's own MouseArea);
    // empty-space presses clear the selection (left) or open the generic
    // context menu (right).
    MouseArea {
        id: listEmptySpaceHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        anchors.fill: listView
        // Leave the scroll bar strip uncovered - the overlay would otherwise
        // swallow presses meant for the scroll bar (indexAt() reports empty
        // space there since delegates are narrower than the view).
        anchors.rightMargin: logScrollBar.width
        propagateComposedEvents: true

        onPressed: (mouse) => {
            // Map the press position into content coordinates and ask
            // the ListView whether a delegate lives there.
            let contentY = mouse.y + listView.contentY
            let idx = listView.indexAt(mouse.x, contentY)
            if (idx === -1) {
                listView.forceActiveFocus()
                if (mouse.button === Qt.RightButton) {
                    root.__contextKind = ""
                    contextMenu.popup()
                } else {
                    root.clearSelection()
                }
            } else {
                // An entry - ignore so the delegate's own MouseArea handles it.
                mouse.accepted = false
            }
        }
    }
}
