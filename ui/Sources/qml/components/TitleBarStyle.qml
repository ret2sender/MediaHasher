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

pragma Singleton

import QtQuick

import com.mediahasher.app


/*!
    Per-platform styling for the frameless title bar caption buttons.

    Structure:

      Profile          - every knob, with the default (Linux) values.
      <name>Profile    - a variant, stating ONLY what it changes.
      resolveVariant() - the single place that decides which one applies.

    Adding a variant is two edits: one Profile block, one case in
    resolveVariant(). Nothing downstream changes.

    macOS never reaches here; the parent uses the native traffic lights.

    Kept deliberately in sync with rawform's copy of this file. The only
    intended divergences are the import URI, the showMaximize default
    (this window is fixed-size), and the per-profile padding* values,
    which are tuned against each app's own title bar height.
*/
QtObject {
    id: style

    // ==================================================================
    // Profile definition
    //
    // These values are the default profile. Variants below inherit them
    // and override only what differs, so a new distro or desktop variant
    // is a handful of lines rather than a full copy.
    // ==================================================================
    component Profile: QtObject {
        property url minimizeIcon: Qt.resolvedUrl("../../icons/default/control_minimize.svg")
        property url maximizeIcon: Qt.resolvedUrl("../../icons/default/control_maximize.svg")
        property url restoreIcon: Qt.resolvedUrl("../../icons/default/control_restore.svg")
        property url closeIcon: Qt.resolvedUrl("../../icons/default/control_close.svg")

        // Hover glyphs. Bound to the rest glyph by default, so profiles that
        // do not invert on hover get a no-op swap. The hover color lives in
        // the artwork rather than a color knob: AppIcon stays free of any
        // colorization stage and the Windows profile stays behavior-identical.
        property url minimizeHoverIcon: minimizeIcon
        property url maximizeHoverIcon: maximizeIcon
        property url restoreHoverIcon: restoreIcon
        property url closeHoverIcon: closeIcon

        property real iconWidth: 10
        property real iconHeight: 10

        // Button geometry.
        property real buttonWidth: 32
        property real buttonHeight: 40
        property real spacing: 0

        // Padding of the whole caption chunk (feeds Control's *Padding on
        // TitleBarControls). Moves the chunk as one box; button hit areas
        // and glyph placement inside buttons are unaffected. Sides are not
        // mirrored by controlsOnLeft: a left-side profile sets paddingLeft
        // itself.
        property real paddingLeft: 0
        property real paddingRight: 0
        property real paddingTop: 0
        property real paddingBottom: 0

        // Applied to whichever top corner faces the window edge. Left at 0
        // by default: a rounded corner stays rounded when the compositor
        // half-tiles the window, and a Qt client cannot detect that state.
        property real closeCornerRadius: 0

        // Fill colors, per state. The rest fills are transparent by default
        // (glyph-only buttons, today's look); a profile that wants an
        // always-visible plate behind the glyphs overrides them.
        property color controlBackground: "transparent"
        property color closeBackground: "transparent"
        property color controlHover: Theme.controlHover
        property color closeHover: Theme.closeHover

        // Background plate geometry. The plate is a square centered behind
        // the glyph (the button cell itself is not square, so an inset can
        // only ever produce an oval; an explicit side length is the only
        // way to get a true circle). backgroundSize is that side length,
        // with 0 as the sentinel for "fill the whole button cell"
        // (Windows-style). backgroundRadius defaults to half the side, so
        // a sized plate is a circle unless a profile overrides the radius
        // for a rounded-square chip; in full-cell mode the default
        // collapses to 0 and the fill stays square.
        //
        // closeCornerRadius (above) applies ONLY in full-cell mode: a
        // centered plate never touches the window corner, so the
        // edge-corner rounding is meaningless there and the control
        // enforces that rather than trusting the two knobs to be kept
        // consistent.
        property real backgroundSize: 28
        property real backgroundRadius: backgroundSize / 2

        // Inactive-window dimming and animation.
        property real inactiveOpacity: 0.5
        property int hoverDuration: 200
        property int dimDuration: 200

        // false -> right side, reading [minimize][close]
        // true  -> left side,  reading [close][minimize]
        property bool controlsOnLeft: false

        // Whether the maximize/restore button exists at all. Off for every
        // profile here: the MediaHasher window is fixed-size, so there is
        // nothing to maximize. The property (and the artwork it points at)
        // is kept so this file stays a straight copy of rawform's, where
        // the button is live.
        property bool showMaximize: false
    }

    // ==================================================================
    // Variants
    // ==================================================================
    readonly property Profile defaultProfile: Profile {
        paddingBottom: 16
        paddingRight: 1
    }

    readonly property Profile windowsProfile: Profile {
        minimizeIcon: Qt.resolvedUrl("../../icons/windows/control_minimize.svg")
        maximizeIcon: Qt.resolvedUrl("../../icons/windows/control_maximize.svg")
        restoreIcon: Qt.resolvedUrl("../../icons/windows/control_restore.svg")
        closeIcon: Qt.resolvedUrl("../../icons/windows/control_close.svg")

        buttonWidth: 46
        buttonHeight: 30
        closeCornerRadius: 8

        controlHover: Theme.windowsControlHover
        closeHover: Theme.windowsCloseHover
        inactiveOpacity: 0.4

        paddingBottom: 16

        // Full-cell hover fill, the stock Win11 caption treatment; the
        // circular plate is a Linux affordance.
        backgroundSize: 0

        hoverDuration: 200
        dimDuration: 150
    }

    // Breeze: a transcription of what the Breeze decoration itself paints
    // (18x18 box, 1.01px pen). The glyph inverts to dark on hover over a
    // near-white plate, so each button carries a second, hover-only asset.
    // iconWidth/iconHeight equal backgroundSize so the icon box is the
    // plate and every line lands where Breeze's pen puts it.
    readonly property Profile breezeProfile: Profile {
        minimizeIcon: Qt.resolvedUrl("../../icons/breeze/control_minimize.svg")
        maximizeIcon: Qt.resolvedUrl("../../icons/breeze/control_maximize.svg")
        restoreIcon: Qt.resolvedUrl("../../icons/breeze/control_restore.svg")
        closeIcon: Qt.resolvedUrl("../../icons/breeze/control_close.svg")

        minimizeHoverIcon: Qt.resolvedUrl("../../icons/breeze/control_minimize_hover.svg")
        maximizeHoverIcon: Qt.resolvedUrl("../../icons/breeze/control_maximize_hover.svg")
        restoreHoverIcon: Qt.resolvedUrl("../../icons/breeze/control_restore_hover.svg")
        closeHoverIcon: Qt.resolvedUrl("../../icons/breeze/control_close_hover.svg")

        iconHeight: 18
        iconWidth: 18

        buttonWidth: 26
        buttonHeight: 30

        controlHover: Theme.breezeControlHover
        closeHover: Theme.breezeCloseHover

        paddingRight: 4
        paddingBottom: 16

        backgroundSize: 18

        hoverDuration: 0
        dimDuration: 0
    }

    // ==================================================================
    // Resolution
    //
    // Explicit override wins, then platform, then the user's icon theme.
    // Set overrideVariant from SettingsManager to expose this as a user
    // preference: it is a declared property, so the whole title bar
    // restyles live when it changes.
    // ==================================================================
    property string overrideVariant: ""

    readonly property string variantName: style.resolveVariant()

    function resolveVariant(): string {
        if (style.overrideVariant !== "")
            return style.overrideVariant

        if (Qt.platform.os === "windows")
            return "windows"

        return style.resolveDesktopVariant()
    }

    /*!
        Keyed off the active icon theme rather than XDG_CURRENT_DESKTOP.
        The theme name is what the user actually configured, so it stays
        correct on Plasma-with-Papirus, on tiling compositors, and on any
        desktop not enumerated here. Unknown themes fall through to the
        default, which is always a valid answer.

        Requires AppInfo.systemIconTheme; returns "default" harmlessly if
        that property is absent.
    */
    function resolveDesktopVariant(): string {
        const iconTheme = (AppInfo.systemIconTheme || "").toLowerCase()

        if (iconTheme.startsWith("breeze"))
            return "breeze"

        return "default"
    }

    readonly property Profile profile: {
        switch (style.variantName) {
        case "windows":
            return style.windowsProfile
        case "breeze":
            return style.breezeProfile
        default:
            return style.defaultProfile
        }
    }

    // ==================================================================
    // Public API
    //
    // Flat forwards so consumers stay unaware of profiles.
    // ==================================================================
    readonly property url minimizeIcon: style.profile.minimizeIcon
    readonly property url maximizeIcon: style.profile.maximizeIcon
    readonly property url restoreIcon: style.profile.restoreIcon
    readonly property url closeIcon: style.profile.closeIcon

    readonly property url minimizeHoverIcon: style.profile.minimizeHoverIcon
    readonly property url maximizeHoverIcon: style.profile.maximizeHoverIcon
    readonly property url restoreHoverIcon: style.profile.restoreHoverIcon
    readonly property url closeHoverIcon: style.profile.closeHoverIcon

    readonly property real iconWidth: style.profile.iconWidth
    readonly property real iconHeight: style.profile.iconHeight

    readonly property real buttonWidth: style.profile.buttonWidth
    readonly property real buttonHeight: style.profile.buttonHeight
    readonly property real spacing: style.profile.spacing
    readonly property real closeCornerRadius: style.profile.closeCornerRadius

    readonly property real paddingLeft: style.profile.paddingLeft
    readonly property real paddingRight: style.profile.paddingRight
    readonly property real paddingTop: style.profile.paddingTop
    readonly property real paddingBottom: style.profile.paddingBottom

    readonly property color controlBackground: style.profile.controlBackground
    readonly property color closeBackground: style.profile.closeBackground
    readonly property color controlHover: style.profile.controlHover
    readonly property color closeHover: style.profile.closeHover

    readonly property real backgroundSize: style.profile.backgroundSize
    readonly property real backgroundRadius: style.profile.backgroundRadius

    readonly property real inactiveOpacity: style.profile.inactiveOpacity
    readonly property int hoverDuration: style.profile.hoverDuration
    readonly property int dimDuration: style.profile.dimDuration

    readonly property bool controlsOnLeft: style.profile.controlsOnLeft
    readonly property bool showMaximize: style.profile.showMaximize
}
