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


Window {
    id: settingsDialog
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    maximumHeight: 368
    maximumWidth: 560
    minimumHeight: 368
    minimumWidth: 560
    modality: Qt.ApplicationModal

    // Index into sectionNames / the StackLayout: 0 = Hashing, 1 = About.
    property int currentSection: 0
    readonly property list<string> sectionNames: ["Hashing", "About"]

    // Persisted values, mirrored after every load/apply. The dirty flag
    // compares the controls against these, so Apply is only enabled while
    // there is actually something to save.
    property int savedAlgorithmIndex: 0
    property int savedConcurrentProcesses: 3
    property bool savedConvertExistingHashes: false

    // Warning text shown below the controls when validation fails.
    property string warningText: ""

    // True while any control differs from the persisted settings.
    readonly property bool dirty:
        concurrentSpinBox.value !== savedConcurrentProcesses
        || algorithmComboBox.currentIndex !== savedAlgorithmIndex
        || convertCheckBox.checked !== savedConvertExistingHashes

    // Per-setting "differs from the built-in default" flags - drive the
    // accent dots next to the labels.
    readonly property bool algorithmModified:
        SettingsManager.get_hash_algorithm_keys()[algorithmComboBox.currentIndex]
        !== SettingsManager.get_default_hash_algorithm()
    readonly property bool concurrentModified:
        concurrentSpinBox.value !== SettingsManager.get_default_concurrent_processes()
    readonly property bool convertModified:
        convertCheckBox.checked !== SettingsManager.get_default_convert_existing_hashes()

    signal applied()

    Component.onCompleted: { loadFromBackend() }

    onVisibleChanged: {
        // Re-opening always lands on the Hashing section, the actionable one.
        if (visible) {
            currentSection = 0
        }
    }

    Shortcut {
        // sequence: "Escape"  // Escape key only
        sequences: [StandardKey.Cancel]  // Escape key being one of them
        onActivated: settingsDialog.close()
    }

    function apply() {
        let warning = SettingsManager.set_concurrent_processes(concurrentSpinBox.value)
        if (warning !== "") {
            warningText = warning
            return false
        }

        let keys = SettingsManager.get_hash_algorithm_keys()
        warning = SettingsManager.set_hash_algorithm(keys[algorithmComboBox.currentIndex])
        if (warning !== "") {
            warningText = warning
            return false
        }

        SettingsManager.set_convert_existing_hashes(convertCheckBox.checked)
        warningText = ""

        let ok = SettingsManager.save()
        if (!ok) {
            warningText = "Failed to write settings file."
            return false
        }

        // Mirror the just-persisted values - dirty drops back to false and
        // the Apply button deactivates.
        savedAlgorithmIndex = algorithmComboBox.currentIndex
        savedConcurrentProcesses = concurrentSpinBox.value
        savedConvertExistingHashes = convertCheckBox.checked

        settingsDialog.applied()
        return true
    }

    function loadFromBackend() {
        concurrentSpinBox.from = SettingsManager.get_min_concurrent()
        concurrentSpinBox.to = SettingsManager.get_max_concurrent()
        savedConcurrentProcesses = SettingsManager.get_concurrent_processes()
        concurrentSpinBox.value = savedConcurrentProcesses

        let keys = SettingsManager.get_hash_algorithm_keys()
        let index = keys.indexOf(SettingsManager.get_hash_algorithm())
        savedAlgorithmIndex = index >= 0 ? index : 0
        algorithmComboBox.currentIndex = savedAlgorithmIndex

        savedConvertExistingHashes = SettingsManager.get_convert_existing_hashes()
        convertCheckBox.checked = savedConvertExistingHashes

        warningText = ""
    }

    // Small accent dot marking a setting whose value differs from its
    // built-in default. Anchored to the right of the label it decorates,
    // inside the row spacing, so toggling it never shifts the layout.
    // The dot occupies the middle of the 18px row spacing: 6px gap,
    // 6px dot, 6px gap - symmetric breathing room on both sides.
    component ModifiedDot: Rectangle {
        anchors.left: parent.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent
        height: 6
        radius: 3
        width: 6
    }

    // Themed check box shared by the conversion options.
    component ThemedCheckBox: CheckBox {
        id: themedCheckBox
        implicitHeight: 26
        spacing: 8

        // Shows the modified dot after the check box label.
        property bool modified: false

        indicator: Rectangle {
            border.color: themedCheckBox.checked ? Theme.accent : Theme.separator
            border.width: 1
            color: Theme.controlBackground
            implicitHeight: 18
            implicitWidth: 18
            radius: 4
            x: themedCheckBox.leftPadding
            y: themedCheckBox.height / 2 - height / 2

            Rectangle {
                anchors.centerIn: parent
                color: Theme.accent
                height: 10
                radius: 2
                visible: themedCheckBox.checked
                width: 10
            }
        }

        contentItem: Text {
            color: themedCheckBox.enabled ? Theme.textPrimary : Theme.textMuted
            font.family: Theme.interFamily
            font.pixelSize: 13
            leftPadding: themedCheckBox.indicator.width + themedCheckBox.spacing
            text: themedCheckBox.text
            verticalAlignment: Text.AlignVCenter

            ModifiedDot {
                visible: themedCheckBox.modified
            }
        }
    }

    // Dialog's background color
    Rectangle {
        anchors.fill: parent
        color: Theme.windowBackground
        radius: 8
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        color: "transparent"
        height: 24

        MouseArea {
            height: parent.height
            width: parent.width

            onPressed: settingsDialog.startSystemMove()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 0

        // Preference header
        Text {
            color: Theme.accent
            font.family: Theme.interFamily
            font.pixelSize: 16
            font.weight: Font.Bold
            text: "Preferences"
        }

        // Preference separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            color: Theme.separator
            implicitHeight: 1
        }

        // Body: section navigation sidebar + page stack.
        RowLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 0

            // -----------------------------------------------------------
            // Sidebar
            // -----------------------------------------------------------
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 108
                spacing: 2

                Repeater {
                    model: settingsDialog.sectionNames

                    delegate: Rectangle {
                        id: navItem

                        required property int index
                        required property string modelData

                        readonly property bool selected:
                            settingsDialog.currentSection === navItem.index

                        Layout.fillWidth: true
                        color: navItem.selected
                               ? Theme.selectionBackground
                               : navItemHover.hovered ? Theme.hoverBackground
                                                      : "transparent"
                        implicitHeight: 28
                        radius: 4

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: navItem.selected ? Theme.textSelected
                                                    : Theme.textPrimary
                            font.family: Theme.interFamily
                            font.pixelSize: 13
                            font.weight: navItem.selected ? Font.DemiBold
                                                          : Font.Normal
                            text: navItem.modelData
                        }

                        HoverHandler {
                            id: navItemHover
                        }

                        TapHandler {
                            onTapped: settingsDialog.currentSection = navItem.index
                        }
                    }
                }
            }

            // Sidebar separator
            Rectangle {
                Layout.fillHeight: true
                Layout.leftMargin: 12
                Layout.rightMargin: 16
                color: Theme.separator
                opacity: 0.5
                implicitWidth: 1
            }

            // -----------------------------------------------------------
            // Pages
            // -----------------------------------------------------------
            StackLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                currentIndex: settingsDialog.currentSection

                // ---- Hashing ------------------------------------------
                ColumnLayout {
                    spacing: 0

                    // Concurrent processes row
                    RowLayout {
                        Layout.topMargin: 6
                        spacing: 18

                        Text {
                            color: Theme.textPrimary
                            font.family: Theme.interFamily
                            font.pixelSize: 13
                            text: "Concurrent processes"

                            ModifiedDot {
                                visible: settingsDialog.concurrentModified
                            }
                        }

                        SpinBox {
                            id: concurrentSpinBox
                            editable: true
                            implicitHeight: 30
                            implicitWidth: 90
                            value: settingsDialog.savedConcurrentProcesses

                            onValueModified: {
                                settingsDialog.warningText = ""
                            }

                            background: Rectangle {
                                border.color: concurrentSpinBox.activeFocus ? Theme.accent : Theme.separator
                                border.width: 1
                                color: Theme.controlBackground
                                radius: 4
                            }

                            contentItem: TextInput {
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                horizontalAlignment: Qt.AlignHCenter
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                selectionColor: Theme.textInputSelection
                                readOnly: !concurrentSpinBox.editable
                                text: concurrentSpinBox.textFromValue(concurrentSpinBox.value, concurrentSpinBox.locale)
                                validator: concurrentSpinBox.validator
                                verticalAlignment: Qt.AlignVCenter

                                onTextEdited: {
                                    let parsed = parseInt(text)
                                    if (isNaN(parsed)) {
                                        return
                                    }
                                    if (parsed < SettingsManager.get_min_concurrent()
                                        || parsed > SettingsManager.get_max_concurrent()) {
                                        settingsDialog.warningText =
                                            "Value must be between "
                                            + SettingsManager.get_min_concurrent()
                                            + " and "
                                            + SettingsManager.get_max_concurrent() + "."
                                    } else {
                                        settingsDialog.warningText = ""
                                    }
                                }
                            }

                            up.indicator: Rectangle {
                                color: concurrentSpinBox.up.pressed ? Theme.controlPressed : "transparent"
                                height: parent.height
                                radius: 4
                                width: 24
                                x: concurrentSpinBox.mirrored ? 0 : parent.width - width

                                Text {
                                    anchors.centerIn: parent
                                    color: concurrentSpinBox.up.pressed ? "#ffffff" : Theme.textPrimary
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    text: "+"
                                }
                            }

                            down.indicator: Rectangle {
                                color: concurrentSpinBox.down.pressed ? Theme.controlPressed : "transparent"
                                height: parent.height
                                width: 24
                                radius: 4
                                x: concurrentSpinBox.mirrored ? parent.width - width : 0

                                Text {
                                    anchors.centerIn: parent
                                    color: concurrentSpinBox.down.pressed ? "#ffffff" : Theme.textPrimary
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    text: "\u2212"
                                }
                            }
                        }
                    }

                    // Hash algorithm row
                    RowLayout {
                        Layout.topMargin: 14
                        spacing: 18

                        Text {
                            color: Theme.textPrimary
                            font.family: Theme.interFamily
                            font.pixelSize: 13
                            text: "Hash algorithm"

                            ModifiedDot {
                                visible: settingsDialog.algorithmModified
                            }
                        }

                        ComboBox {
                            id: algorithmComboBox
                            implicitHeight: 30
                            implicitWidth: 130
                            model: SettingsManager.get_hash_algorithm_labels()

                            onActivated: {
                                settingsDialog.warningText = ""
                            }

                            background: Rectangle {
                                border.color: algorithmComboBox.activeFocus ? Theme.accent : Theme.separator
                                border.width: 1
                                color: Theme.controlBackground
                                radius: 4
                            }

                            contentItem: Text {
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                font.family: Theme.interFamily
                                font.pixelSize: 13
                                leftPadding: 10
                                rightPadding: algorithmComboBox.indicator.width + 6
                                text: algorithmComboBox.displayText
                                verticalAlignment: Text.AlignVCenter
                            }

                            indicator: Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                text: "\u25BE"
                            }

                            delegate: ItemDelegate {
                                id: algorithmDelegate
                                implicitHeight: 26
                                width: algorithmComboBox.width

                                required property int index
                                required property string modelData

                                highlighted: algorithmComboBox.highlightedIndex === index

                                background: Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    color: algorithmDelegate.highlighted ? Theme.buttonHover : "transparent"
                                    radius: 4
                                }

                                contentItem: Text {
                                    color: Theme.textPrimary
                                    font.family: Theme.interFamily
                                    font.pixelSize: 13
                                    leftPadding: 6
                                    text: algorithmDelegate.modelData
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            popup: Popup {
                                padding: 4
                                width: algorithmComboBox.width
                                y: algorithmComboBox.height + 4

                                background: Rectangle {
                                    color: Theme.controlBackground
                                    radius: 6
                                }

                                contentItem: ListView {
                                    clip: true
                                    currentIndex: algorithmComboBox.highlightedIndex
                                    implicitHeight: contentHeight
                                    model: algorithmComboBox.popup.visible ? algorithmComboBox.delegateModel : null
                                }
                            }
                        }
                    }

                    // Convert existing hash files option. Each stale hash
                    // file is always verified with its old algorithm first
                    // (in the same read pass, so it costs no extra I/O) -
                    // corruption is reported as a mismatch instead of being
                    // laundered into a fresh hash file.
                    ThemedCheckBox {
                        id: convertCheckBox
                        Layout.topMargin: 14
                        modified: settingsDialog.convertModified
                        text: "Convert existing hash files to the selected algorithm"

                        onToggled: {
                            settingsDialog.warningText = ""
                        }
                    }

                    // Warning label
                    Text {
                        Layout.topMargin: 6
                        color: Theme.warning
                        font.pixelSize: 12
                        text: settingsDialog.warningText
                        visible: settingsDialog.warningText !== ""
                    }

                    // Spacer
                    Item {
                        Layout.fillHeight: true
                    }
                }

                // ---- About --------------------------------------------
                //
                // A plain Item page with the content column anchored to
                // its center: centering on both axes is then geometric
                // fact rather than a property of layout stretch
                // distribution.
                Item {

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        AppIcon {
                            Layout.alignment: Qt.AlignHCenter
                            iconWidth: 181
                            iconHeight: 32
                            source: "../../images/mediahasher_text.svg"
                        }

                        // Version line. Clicking copies the full build
                        // info - handy for bug reports - with brief
                        // inline feedback.
                        Text {
                            id: versionText

                            property bool copied: false

                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 14
                            color: versionText.copied ? Theme.accent : Theme.textPrimary
                            font.family: Theme.jetbrainsMonoFamily
                            font.pixelSize: 13
                            text: versionText.copied
                                  ? "Copied!"
                                  : "Version " + AppInfo.version

                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    Clipboard.setText(
                                        "MediaHasher " + AppInfo.version
                                        + " (Qt " + AppInfo.qtVersion + ", "
                                        + Qt.platform.os + ")")
                                    versionText.copied = true
                                    copiedResetTimer.restart()
                                }
                            }

                            Timer {
                                id: copiedResetTimer
                                interval: 1200
                                onTriggered: versionText.copied = false
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                            color: Theme.textMuted
                            font.family: Theme.interFamily
                            font.pixelSize: 12
                            text: "Built with Qt " + AppInfo.qtVersion
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 12
                            color: Theme.textMuted
                            font.family: Theme.interFamily
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            text: "Copyright \u00A9 2026 Etienne Fleurant\n"
                                  + "Released under the GNU GPL v3.0 or later"
                        }
                        // External links. Plain Texts styled as links rather than
                        // Text.RichText anchors: hover state and cursor come from
                        // the same handler pattern as everything else in the app,
                        // and the URL lives in one obvious place per link.
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 16
                            spacing: 24

                            Text {
                                id: githubLink
                                color: githubHover.hovered ? Theme.accentHover : Theme.accentSoft
                                font.family: Theme.interFamily
                                font.pixelSize: 12
                                font.underline: true
                                text: "GitHub"

                                HoverHandler {
                                    id: githubHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: Qt.openUrlExternally(
                                        "https://github.com/ret2sender/MediaHasher")
                                }
                            }

                            Text {
                                id: noticesLink
                                color: noticesHover.hovered ? Theme.accentHover : Theme.accentSoft
                                font.family: Theme.interFamily
                                font.pixelSize: 12
                                font.underline: true
                                text: "Third-party notices"

                                HoverHandler {
                                    id: noticesHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: Qt.openUrlExternally(
                                        "https://github.com/ret2sender/MediaHasher/blob/main/THIRD-PARTY-NOTICES.md")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Separator above buttons
        Rectangle {
            Layout.fillWidth: true
            color: Theme.separator
            implicitHeight: 1
        }

        // Button row
        RowLayout {
            Layout.topMargin: 12
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                id: cancelButton
                implicitHeight: 30
                implicitWidth: 80
                text: "Cancel"

                background: Rectangle {
                    border.color: Theme.separator
                    border.width: 1
                    color: cancelButton.down ? Theme.controlPressed : Theme.controlBackground
                    radius: 4
                }

                contentItem: Text {
                    color: Theme.textPrimary
                    font.family: Theme.interFamily
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: cancelButton.text
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    settingsDialog.warningText = ""
                    settingsDialog.loadFromBackend()
                    settingsDialog.close()
                }
            }

            Button {
                id: applyButton
                enabled: settingsDialog.dirty
                implicitHeight: 30
                implicitWidth: 80
                text: "Apply"

                background: Rectangle {
                    border.color: applyButton.enabled ? Theme.separator : Theme.textMuted
                    border.width: 1
                    color: applyButton.down ? Theme.controlPressed : Theme.controlBackground
                    radius: 4
                }

                contentItem: Text {
                    color: applyButton.enabled ? Theme.textPrimary : Theme.textMuted
                    font.family: Theme.interFamily
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: applyButton.text
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    settingsDialog.apply()
                }
            }

            Button {
                id: okButton
                implicitHeight: 30
                implicitWidth: 80
                text: "OK"

                background: Rectangle {
                    border.color: Theme.accent
                    border.width: 1
                    color: okButton.down ? Theme.accent : Theme.accentDeep
                    radius: 4
                }

                contentItem: Text {
                    color: Theme.textPrimary
                    font.family: Theme.interFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    text: okButton.text
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    if (settingsDialog.apply()) {
                        settingsDialog.close()
                    }
                }
            }
        }
    }
}
