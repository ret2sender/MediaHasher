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

    property var model: null
    property var rootIndex: undefined

    // Drag proxy
    Item {
        id: rootDragProxy
        height: 1
        parent: root
        visible: false
        width: 1

        Drag.active: false
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
    }

    MouseArea {
        id: rootMouseArea
        anchors.fill: parent
        z: -1

        onClicked: {
            treeView.selectionModel.clearSelection()
        }
    }

    Label {
        id: header
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 10
        color: Theme.accent
        font.family: Theme.interFamily
        font.pixelSize: 16
        font.weight: Font.Bold
        text: "File Browser"
    }

    TreeView {
        id: treeView
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 6
        clip: true
        columnWidthProvider: function(column) {
            return column === 0 ? treeView.width : 0  // hide all column but first
        }
        model: root.model
        pointerNavigationEnabled: false  // disable built-in selection handling
        rootIndex: root.rootIndex
        selectionBehavior: TableView.SelectRows
        selectionModel: ItemSelectionModel {}

        ScrollBar.vertical: AutoHideScrollBar {}

        TapHandler {
            id: treeViewTapHandler
            acceptedModifiers: Qt.NoModifier

            onTapped: (eventPoint) => {
                let cell = treeView.cellAtPosition(eventPoint.position)
                if (cell.x === -1 && cell.y === -1) {
                    treeView.selectionModel.clearSelection()
                }
            }
        }

        delegate: Item {
            id: treeViewDelegateRoot
            implicitHeight: 28
            implicitWidth: treeView.width

            readonly property real indentation: 20
            readonly property real padding: 5

            required property int column
            required property bool current
            required property int depth
            required property string display
            required property bool expanded
            required property bool hasChildren
            required property bool isDirectory
            required property bool isTreeNode
            required property int row
            required property bool selected
            required property TreeView treeView


            property Animation treeViewItemIndicatorAnimation: NumberAnimation {
                duration: 500
                easing.type: Easing.OutQuart
                from: treeViewDelegateRoot.expanded ? 0 : 90
                property: "rotation"
                target: treeViewItemIndicator
                to: treeViewDelegateRoot.expanded ? 90 : 0
            }

            TableView.onPooled: treeViewItemIndicatorAnimation.complete()
            TableView.onReused: if (current) treeViewItemIndicatorAnimation.start()
            onExpandedChanged: treeViewItemIndicator.rotation = expanded ? 90 : 0

            function iconSource() {
                if (!isDirectory)
                    return "../../icons/google_material/video_file.svg"

                if (isDirectory && !hasChildren)
                    return "../../icons/google_material/folder.svg"

                return expanded
                    ? "../../icons/google_material/folder_open.svg"
                    : "../../icons/google_material/folder.svg"
            }

            // Hover + row highlight
            Rectangle {
                id: treeViewItemBackground
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                color: {
                    if (treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren)
                        return "transparent"
                    return treeViewDelegateRoot.selected
                        ? Theme.selectionBackground
                        : (hoverHandler.hovered ? Theme.hoverBackground : "transparent")
                }
                radius: 4
            }

            // Item zone 1: Indicator (expand/collapse only)
            Item {
                id: treeViewItemIndicatorZone
                height: parent.height
                visible: treeViewDelegateRoot.isTreeNode && treeViewDelegateRoot.hasChildren
                width: treeViewDelegateRoot.indentation
                x: treeViewDelegateRoot.depth * treeViewDelegateRoot.indentation

                AppIcon {
                    id: treeViewItemIndicator
                    anchors.centerIn: parent
                    source: "../../icons/google_material/arrow_right.svg"
                }

                TapHandler {
                    id: treeViewItemIndicatorTapHandler
                    grabPermissions: TapHandler.CanTakeOverFromAnything

                    onSingleTapped: {
                        let index = treeViewDelegateRoot.treeView.index(
                            treeViewDelegateRoot.row, treeViewDelegateRoot.column)
                        treeViewDelegateRoot.treeView.selectionModel.setCurrentIndex(
                            index, ItemSelectionModel.NoUpdate)
                        treeViewDelegateRoot.treeView.toggleExpanded(treeViewDelegateRoot.row)
                    }
                }
            }

            // Item zone 2: Icon + label (selection only)
            Item {
                id: treeViewItemContentZone
                height: parent.height
                width: parent.width - x - 4
                x: (treeViewDelegateRoot.depth * treeViewDelegateRoot.indentation)
                   + treeViewDelegateRoot.indentation

                AppIcon {
                    id: treeViewItemIcon
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren
                             ? 0.35 : 1.0
                    source: treeViewDelegateRoot.iconSource()
                }

                Label {
                    id: treeViewItemLabel
                    anchors.left: treeViewItemIcon.right
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    font.family: Theme.interFamily
                    font.pixelSize: 14
                    opacity: treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren
                             ? 0.35 : 1.0
                    text: treeViewDelegateRoot.display
                }

                // TapHandlers for selection(s)
                TapHandler {
                    acceptedModifiers: Qt.NoModifier
                    onTapped: {
                        if (treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren) return
                        let idx = treeViewDelegateRoot.treeView.index(treeViewDelegateRoot.row, 0)
                        treeViewDelegateRoot.treeView.selectionModel.setCurrentIndex(
                            idx, ItemSelectionModel.NoUpdate)
                        treeViewDelegateRoot.treeView.selectionModel.select(
                            idx, ItemSelectionModel.ClearAndSelect | ItemSelectionModel.Rows)
                    }
                }

                TapHandler {
                    acceptedModifiers: Qt.ControlModifier
                    onTapped: {
                        if (treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren) return
                        let idx = treeViewDelegateRoot.treeView.index(treeViewDelegateRoot.row, 0)
                        treeViewDelegateRoot.treeView.selectionModel.setCurrentIndex(
                            idx, ItemSelectionModel.NoUpdate)
                        treeViewDelegateRoot.treeView.selectionModel.select(
                            idx, ItemSelectionModel.Toggle | ItemSelectionModel.Rows)
                    }
                }

                TapHandler {
                    acceptedModifiers: Qt.ShiftModifier
                    onTapped: {
                        if (treeViewDelegateRoot.isDirectory && !treeViewDelegateRoot.hasChildren) return
                        let view = treeViewDelegateRoot.treeView
                        let currentRow = view.rowAtIndex(view.selectionModel.currentIndex)
                        let topRow = Math.min(currentRow, treeViewDelegateRoot.row)
                        let bottomRow = Math.max(currentRow, treeViewDelegateRoot.row)
                        for (let r = topRow; r <= bottomRow; r++) {
                            view.selectionModel.select(
                                view.index(r, 0),
                                ItemSelectionModel.Select | ItemSelectionModel.Rows
                            )
                        }
                    }
                }

                // DragHandler for dragging items, target: null stops it from moving the item
                DragHandler {
                    target: null  // important: prevents moving the treeViewItemContentZone

                    onActiveChanged: {
                        if (active) {
                            let view = treeViewDelegateRoot.treeView
                            let selected = view.selectionModel.selectedIndexes
                            let filtered = selected.filter(i => i.column === 0)
                            let paths = filtered.map(i => root.model.filePath(i))
                            if (paths.length === 0)
                                paths = [root.model.filePath(view.index(treeViewDelegateRoot.row, 0))]

                            // Set mimeData imperatively before activating
                            rootDragProxy.Drag.mimeData = { "text/uri-list": paths.join("\r\n") }
                            rootDragProxy.Drag.active = true
                        } else {
                            rootDragProxy.Drag.drop()
                            rootDragProxy.Drag.active = false
                            treeViewDelegateRoot.treeView.selectionModel.clearSelection()
                        }
                    }
                }
            }
            HoverHandler { id: hoverHandler }
        }
    }
}
