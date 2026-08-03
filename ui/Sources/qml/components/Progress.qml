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
import QtQuick.Layouts

import com.mediahasher.app


Rectangle {
    id: root
    color: Theme.panelBackground
    radius: 8

    // Expose internals to the outside world
    property alias mainProgressBar: mainProgressBar
    property alias progressBarContainer: progressBarContainer
    property alias progressBarCount: progressBarContainer.model

    Component.onCompleted: {
        progressBarCount = Backend.get_parallel_processes()
    }

    TextMetrics {
        id: percentageLabelMetrics
        font.family: Theme.jetbrainsMonoFamily
        font.pixelSize: 12
        font.weight: Font.Bold
        text: "100%"
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
        text: "Progress"
    }

    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.top: header.bottom
        height: 24

        ColumnLayout {
            id: progressBarColumn
            Layout.fillWidth: true
            spacing: -1

            RowLayout {
                id: repeaterRowLayout
                Layout.fillWidth: true
                Layout.rightMargin: 34
                spacing: 0

                Repeater {
                    id: progressBarContainer
                    model: 0

                    ColumnLayout {
                        id: taskProgressBarDelegate
                        spacing: 0

                        property alias to: taskProgressBar.to
                        property alias value: taskProgressBar.value

                        Label {
                            id: taskProgressBarLabel
                            Layout.preferredWidth: percentageLabelMetrics.boundingRect.width
                            color: Theme.textPrimary
                            font.family: Theme.interFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignLeft
                            text: taskProgressBar.to > 0
                                  ? Math.round((taskProgressBar.value / taskProgressBar.to) * 100) + "%"
                                  : "0%"
                        }

                        SlimProgressBar {
                            id: taskProgressBar
                            Layout.fillWidth: true
                            activeColor: Theme.accentDeep
                            progressBarHeight: 4
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SlimProgressBar {
                    id: mainProgressBar
                    Layout.preferredWidth: 430
                }

                Label {
                    id: mainProgressBarLabel
                    Layout.preferredWidth: percentageLabelMetrics.boundingRect.width
                    color: Theme.textPrimary
                    font.family: Theme.interFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    text: mainProgressBar.to > 0
                          ? Math.round((mainProgressBar.value / mainProgressBar.to) * 100) + "%"
                          : "0%"
                }
            }
        }
    }
}
