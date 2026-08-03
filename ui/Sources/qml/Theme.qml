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

pragma Singleton

import QtQuick


// Application-wide theme singleton: fonts and the color palette.
//
// Registered as a QML singleton via QT_QML_SINGLETON_TYPE in the
// qt_add_qml_module call (see ui/CMakeLists.txt). Every component reads
// fonts and colors from here instead of reaching into the context chain.
QtObject {
    id: root

    // -------------------------------------------------------------------------
    // Fonts
    // -------------------------------------------------------------------------
    readonly property FontLoader interLoader: FontLoader {
        source: "../fonts/Inter-VariableFont_opsz,wght.ttf"
    }

    readonly property FontLoader jetbrainsMonoLoader: FontLoader {
        source: "../fonts/JetBrainsMono-VariableFont_wght.ttf"
    }

    // Font family names for font.family bindings.
    readonly property string interFamily: interLoader.name
    readonly property string jetbrainsMonoFamily: jetbrainsMonoLoader.name

    // -------------------------------------------------------------------------
    // Palette - JetBrains/Affinity-inspired dark theme
    // -------------------------------------------------------------------------
    // Accents
    readonly property color accent: "#C495FF"        // headers, active state, drop hover
    readonly property color accentDeep: "#9641FF"    // worker progress fill, OK button
    readonly property color accentSoft: "#BDB2FF"    // lavender: focus strokes, highlights
    readonly property color accentHover: "#D4B8FF"   // menu-label hover tint

    // Surfaces
    readonly property color windowBackground: "#292929"
    readonly property color panelBackground: "#1B1B1B"
    readonly property color panelBackgroundDone: "#1E1F24"  // completed-queue hatch backdrop
    readonly property color controlBackground: "#3C3F41"    // spin box, combo box, dialog buttons
    readonly property color controlPressed: "#505356"

    // Text
    readonly property color textPrimary: "#E2E2E2"
    readonly property color textMuted: "#6B6B6B"     // done rows, log separator glyphs
    readonly property color textSelected: "#D4B8FF"
    readonly property color textInputSelection: "#6897BB"

    // States
    readonly property color warning: "#E06C75"       // failed rows, validation warnings
    readonly property color selectionBackground: "#3D2D5C"
    readonly property color hoverBackground: "#232323"
    readonly property color buttonHover: "#4E4E4E"
    readonly property color scrollBarThumb: "#2E2E2E"
    readonly property color separator: "#717171"

    // Title bar controls - default (non-Windows)
    readonly property color controlHover: "#4E4E4E"
    readonly property color closeHover: "#C42B1C"

    // Title bar controls - Windows
    readonly property color windowsControlHover: "#626262"
    readonly property color windowsCloseHover: "#C42B1C"

    // Jobs Log entry colors
    readonly property color logComplete: "lawngreen"
    readonly property color logConverted: "deepskyblue"  // hash file converted to the selected algorithm
    readonly property color logFailed: "orange"
    readonly property color logMatch: "lightgreen"
    readonly property color logMismatch: "red"
}
