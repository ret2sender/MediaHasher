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
import QtQuick.Layouts

import com.mediahasher.app


Item {
    id: root
    implicitHeight: 48

    signal abortRequested()
    signal moveRequested()
    signal resetRequested()
    signal runRequested()
    signal settingsRequested()

    property bool hasItems: false
    property bool isAborted: false
    property bool isComplete: false
    property bool isRunning: false

    // Dim factor applied to the title bar icons when the window loses focus.
    // With a custom-drawn title bar the OS provides no inactive treatment,
    // so this mirrors the native behavior (grayed caption content) manually.
    readonly property real inactiveDim: root.Window.active
        ? 1.0
        : TitleBarStyle.inactiveOpacity

    readonly property bool usesCustomControls: Qt.platform.os !== "osx"

    MouseArea {
        id: moveArea
        anchors.fill: parent
        onPressed: root.moveRequested()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: itemsRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            AppIcon {
                id: logo
                // 102 = the previous 90px zero-width spacer + 12px row spacing.
                // Clears the macOS traffic lights; same offset kept on Windows
                // for cross-platform visual parity.
                Layout.leftMargin: 102
                iconHeight: 38
                iconWidth: 215
                source: "../../images/mediahasher_logo.svg"
            }

            Button {
                id: runButton
                // 127 = the previous 115px zero-width spacer + 12px row spacing,
                // holding the button cluster at its position after the logo.
                Layout.leftMargin: 127
                background: Rectangle {
                    color: runButton.hovered ? Theme.buttonHover : "transparent"
                    radius: 6

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                }
                // Enabled when: queue has items AND not complete.
                // (While running it acts as the abort button, so stays enabled.)
                enabled: root.isRunning || (root.hasItems && !root.isComplete)
                hoverEnabled: root.isRunning || (root.hasItems && !root.isComplete)
                implicitHeight: 30
                implicitWidth: 30
                padding: 0

                onClicked: {
                    if (!root.isRunning) {
                        root.runRequested()
                    } else {
                        root.abortRequested()
                    }
                }

                contentItem: AppIcon {
                    source: root.isRunning
                        ? "../../icons/jetbrains_intellij/pause_dark.svg"
                        : "../../icons/jetbrains_intellij/run_dark.svg"
                    opacity: (runButton.enabled ? 1.0 : 0.3) * root.inactiveDim

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }
            }

            Button {
                id: resetButton
                background: Rectangle {
                    color: resetButton.hovered ? Theme.buttonHover : "transparent"
                    radius: 6

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                }
                // Enabled when: aborted (paused), or has items and idle, or completed.
                enabled: root.isAborted
                    || (root.hasItems && !root.isRunning)
                    || root.isComplete
                hoverEnabled: root.isAborted
                    || (root.hasItems && !root.isRunning)
                    || root.isComplete
                implicitHeight: 30
                implicitWidth: 30
                padding: 0

                onClicked: {
                    root.resetRequested()
                }

                contentItem: AppIcon {
                    opacity: (resetButton.enabled ? 1.0 : 0.3) * root.inactiveDim
                    source: "../../icons/jetbrains_intellij/forceRefresh_dark.svg"
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            Button {
                id: settingsButton
                background: Rectangle {
                    color: settingsButton.hovered ? Theme.buttonHover : "transparent"
                    radius: 6

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                }
                // Enabled when not running, or when complete.
                enabled: !root.isRunning && !root.isAborted
                hoverEnabled: !root.isRunning && !root.isAborted
                implicitHeight: 30
                implicitWidth: 30
                padding: 0

                onClicked: {
                    root.settingsRequested()
                }

                contentItem: AppIcon {
                    source: "../../icons/jetbrains_intellij/inlaySettings_dark.svg"
                    opacity: (settingsButton.enabled ? 1.0 : 0.3) * root.inactiveDim

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            Item {
                id: titleBarControlsSpacer
                Layout.fillWidth: true
                visible: root.usesCustomControls
            }

            TitleBarControls {
                id: titleBarControls
                Layout.fillHeight: true
                enabled: root.usesCustomControls
                visible: root.usesCustomControls
            }
        }
        Rectangle {
            id: bottomLineSeparator
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            color: Theme.separator
            implicitHeight: 3
        }
    }
}
