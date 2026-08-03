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

import com.mediahasher.app


/*
   Themed auto-hiding scroll bar shared by the file browser, file queue,
   and jobs log panels. The thumb fades in while scrolling, hovering, or
   dragging, and fades out after a short linger delay.
*/
ScrollBar {
    id: root
    policy: ScrollBar.AsNeeded
    rightPadding: 6

    background: Rectangle {
        color: "transparent"
        implicitWidth: 8
    }

    contentItem: Rectangle {
        id: thumb
        color: root.pressed ? Theme.accent : Theme.scrollBarThumb
        implicitWidth: 8
        opacity: 0.0
        radius: width / 2

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    // Drive visibility from the ScrollBar scope where active/moving
    // are guaranteed to be accessible without initialization races.
    onActiveChanged: {
        if (active) {
            lingerTimer.stop()
            thumb.opacity = 1.0
        } else {
            lingerTimer.restart()
        }
    }
    onHoveredChanged: {
        if (hovered) {
            lingerTimer.stop()
            thumb.opacity = 1.0
        } else {
            lingerTimer.restart()
        }
    }
    onPositionChanged: {
        lingerTimer.stop()
        thumb.opacity = 1.0
        lingerTimer.restart()
    }

    Timer {
        id: lingerTimer
        interval: 1000
        repeat: false

        onTriggered: thumb.opacity = 0.0
    }
}
