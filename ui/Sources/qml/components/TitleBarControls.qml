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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

import com.mediahasher.app


/*!
    Caption buttons for the frameless title bar.

    Minimize, maximize/restore, and close, in that visual order. The
    maximize button is profile-gated (TitleBarStyle.showMaximize) and is
    off on every MediaHasher profile, since the window is fixed-size; the
    button is kept so this file stays a straight copy of rawform's. macOS
    is not handled here, as the parent supplies the native traffic lights
    instead.

    All per-platform values come from TitleBarStyle.
*/
Item {
    id: root

    implicitHeight: controlsRow.implicitHeight
    implicitWidth: controlsRow.implicitWidth

    component CaptionButton: Button {
        id: captionButton

        required property url iconSource
        required property real iconWidth
        required property real iconHeight
        required property color restColor
        required property color hoverColor

        // Applied to whichever top corner faces the window edge.
        property real cornerRadius: 0

        hoverEnabled: true
        implicitHeight: TitleBarStyle.buttonHeight
        implicitWidth: TitleBarStyle.buttonWidth

        // The Item is a transparent carrier sized to the button cell; the
        // Rectangle inside it is the actual fill. It is sized explicitly
        // rather than inset from the cell: the cell is not square, so only
        // an explicit square side can render a true circle. The whole cell
        // stays clickable and hoverable regardless of plate size.
        background: Item {
            Rectangle {
                id: backgroundPlate

                // Full-cell mode is where the plate reaches the window
                // edge, and therefore the only mode where the edge-corner
                // rounding (cornerRadius) can apply; a centered plate takes
                // the uniform backgroundRadius on every corner instead.
                readonly property bool fullCell: TitleBarStyle.backgroundSize === 0

                anchors.centerIn: parent
                width: backgroundPlate.fullCell ? parent.width : TitleBarStyle.backgroundSize
                height: backgroundPlate.fullCell ? parent.height : TitleBarStyle.backgroundSize

                color: captionButton.hovered
                    ? captionButton.hoverColor
                    : captionButton.restColor

                radius: TitleBarStyle.backgroundRadius
                topLeftRadius: backgroundPlate.fullCell && TitleBarStyle.controlsOnLeft
                    ? captionButton.cornerRadius
                    : TitleBarStyle.backgroundRadius
                topRightRadius: backgroundPlate.fullCell && !TitleBarStyle.controlsOnLeft
                    ? captionButton.cornerRadius
                    : TitleBarStyle.backgroundRadius

                Behavior on color {
                    ColorAnimation { duration: TitleBarStyle.hoverDuration }
                }
            }
        }

        contentItem: AppIcon {
            iconHeight: captionButton.iconHeight
            iconWidth: captionButton.iconWidth
            opacity: captionButton.Window.active ? 1.0 : TitleBarStyle.inactiveOpacity
            source: captionButton.iconSource

            // Dim the caption glyphs while the window is unfocused.
            Behavior on opacity {
                NumberAnimation { duration: TitleBarStyle.dimDuration }
            }
        }
    }

    RowLayout {
        id: controlsRow

        spacing: TitleBarStyle.spacing

        // Mirrors the row so close stays outboard on either side.
        layoutDirection: TitleBarStyle.controlsOnLeft ? Qt.RightToLeft : Qt.LeftToRight

        CaptionButton {
            iconSource: TitleBarStyle.minimizeIcon
            iconWidth: TitleBarStyle.iconWidth
            iconHeight: TitleBarStyle.iconHeight
            restColor: TitleBarStyle.controlBackground
            hoverColor: TitleBarStyle.controlHover

            onClicked: root.Window.window.showMinimized()
        }

        CaptionButton {
            id: maximizeButton

            // Window.visibility is the ground truth for the toggle: it also
            // tracks maximization performed by the window manager itself
            // (title bar double-click, edge snapping, taskbar actions), so
            // the glyph and the click action never desynchronize from a
            // state change this button did not initiate.
            readonly property bool windowMaximized:
                root.Window.visibility === Window.Maximized

            visible: TitleBarStyle.showMaximize

            iconSource: maximizeButton.windowMaximized
                ? TitleBarStyle.restoreIcon
                : TitleBarStyle.maximizeIcon
            iconWidth: TitleBarStyle.iconWidth
            iconHeight: TitleBarStyle.iconHeight
            restColor: TitleBarStyle.controlBackground
            hoverColor: TitleBarStyle.controlHover

            onClicked: maximizeButton.windowMaximized
                ? root.Window.window.showNormal()
                : root.Window.window.showMaximized()
        }

        CaptionButton {
            iconSource: TitleBarStyle.closeIcon
            iconWidth: TitleBarStyle.iconWidth
            iconHeight: TitleBarStyle.iconHeight
            restColor: TitleBarStyle.closeBackground
            hoverColor: TitleBarStyle.closeHover
            cornerRadius: TitleBarStyle.closeCornerRadius

            onClicked: root.Window.window.close()
        }
    }
}
