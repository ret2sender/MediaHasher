# MediaHasher - cross-platform media file integrity tool.
# Copyright (C) 2026 Etienne Fleurant
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 4.1)

# ---------------------------------------------------------------------------
# Version - single source of truth
#
# The application version lives in ui/VERSION.txt as a bare semantic version
# on one line. Reading a file instead of hardcoding the number here means the
# packaging scripts (scripts/build.ps1, scripts/macdeploy.sh) can consume
# the same value with a trivial read instead of a regex over this file -
# reformatting this CMakeLists can then never break artifact naming.
#
# The .txt suffix is load-bearing, not cosmetic: C++20 has a standard header
# named <version>, this directory sits on the compiler's include search path
# (AUTOMOC/QML tooling adds it), and macOS's default case-insensitive
# filesystem lets a bare ui/VERSION shadow that header - every translation
# unit then fails parsing '1.0.0' as C++. Do not rename this file back.
# ---------------------------------------------------------------------------
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION.txt" MEDIAHASHER_VERSION)
string(STRIP "${MEDIAHASHER_VERSION}" MEDIAHASHER_VERSION)
if(NOT MEDIAHASHER_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR
            "ui/VERSION.txt must contain a semantic version (major.minor.patch) "
            "on a single line; found '${MEDIAHASHER_VERSION}'.")
endif()

project(MediaHasher VERSION ${MEDIAHASHER_VERSION} LANGUAGES CXX)

# Re-run the configure step when ui/VERSION.txt changes; file(READ) is not
# tracked as a dependency by itself, so without this a version bump would
# silently keep the old number until the next manual reconfigure.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/VERSION.txt"
)

# ---------------------------------------------------------------------------
# Global C++ standard
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Qt 6
# ---------------------------------------------------------------------------
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickControls2)

# Opt into modern Qt 6.8+ QML resource and module policies.
# QTP0001: embed QML files under :/qt/qml/ instead of :/ to avoid resource collisions.
# QTP0004: require qmldir files for QML subdirectories, enforcing explicit module structure.
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# ---------------------------------------------------------------------------
# yaml-cpp (Homebrew)
# ---------------------------------------------------------------------------
find_package(yaml-cpp REQUIRED)

# ---------------------------------------------------------------------------
# MediaHash core library (reused from ../core/MediaHash)
#
# The subproject locates OpenSSL itself and links OpenSSL::Crypto PUBLIC,
# so no OpenSSL handling is needed at this level.
# ---------------------------------------------------------------------------
add_subdirectory(
        ${CMAKE_CURRENT_SOURCE_DIR}/../MediaHash
        ${CMAKE_CURRENT_BINARY_DIR}/MediaHash
)

# MediaHash is a Qt-free core library; disable AUTOMOC to avoid the empty
# mocs_compilation.cpp.o / ranlib warning.
set_target_properties(MediaHash PROPERTIES AUTOMOC OFF)

# ---------------------------------------------------------------------------
# App sources
# ---------------------------------------------------------------------------
set(APP_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/main.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/FileHelper.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/MediaHasher.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/Worker.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/WorkerSignals.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/models/FileExtensionFilterProxyModel.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/utils/AppInfo.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/utils/ClipboardHelper.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/utils/SettingsManager.cpp
)

# macOS-specific Objective-C++ source for native window styling.
if(APPLE)
    list(APPEND APP_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/Sources/utils/MacOSStyling.mm
    )
endif()

# Platform-specific icon setup
if(APPLE)
    set(APP_ICON_FILE "${CMAKE_CURRENT_SOURCE_DIR}/resources/MediaHasher.icns")
    set_source_files_properties(${APP_ICON_FILE}
            PROPERTIES MACOSX_PACKAGE_LOCATION "Resources"
    )
    set(APP_ICON ${APP_ICON_FILE})
elseif(WIN32)
    # The resource script is a configured template: CMake injects the
    # project version (VERSIONINFO block) and the absolute icon path, so
    # Explorer's file Properties -> Details shows the release version.
    set(MEDIAHASHER_ICO_PATH "${CMAKE_CURRENT_SOURCE_DIR}/resources/MediaHasher.ico")
    configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/MediaHasher.rc.in"
            "${CMAKE_CURRENT_BINARY_DIR}/MediaHasher.rc"
            @ONLY
    )
    set(APP_ICON "${CMAKE_CURRENT_BINARY_DIR}/MediaHasher.rc")
endif()

if(APPLE)
    qt_add_executable(MediaHasher
            MACOSX_BUNDLE
            ${APP_SOURCES}
            ${APP_ICON}
    )
elseif(WIN32)
    qt_add_executable(MediaHasher
            WIN32
            ${APP_SOURCES}
            ${APP_ICON}
    )
else()
    qt_add_executable(MediaHasher
            ${APP_SOURCES}
    )
endif()

# ---------------------------------------------------------------------------
# Co-locate the CLI with the application
#
# mediahash is built as part of this project via the add_subdirectory above,
# but defaults to its own nested binary directory. Putting it beside the
# application makes the build output directly distributable: on Windows it
# shares the Qt DLLs windeployqt copies there, and on macOS it lands inside
# the bundle, where macdeployqt can repoint it at the bundled libraries.
# ---------------------------------------------------------------------------
set_target_properties(mediahash PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "$<TARGET_FILE_DIR:MediaHasher>"
)

# Debug builds on Windows use the console subsystem so qDebug/qWarning output
# reaches stderr and is visible in the IDE console. Without this, the WIN32
# (GUI) subsystem routes all Qt logging to OutputDebugString, which CLion's
# LLDB-based MSVC debugger does not display.
#
# Note:
# A generator expression rather than an if(CMAKE_BUILD_TYPE STREQUAL "Debug"):
# multi-config generators leave CMAKE_BUILD_TYPE empty at configure time, so
# the if() form silently never fires for them.
if(WIN32)
    set_target_properties(MediaHasher PROPERTIES
            WIN32_EXECUTABLE $<NOT:$<CONFIG:Debug>>
    )
endif()

# macOS bundle metadata
if(APPLE)
    set_target_properties(MediaHasher PROPERTIES
            MACOSX_BUNDLE_ICON_FILE     MediaHasher.icns
            MACOSX_BUNDLE_BUNDLE_NAME   "MediaHasher"
            MACOSX_BUNDLE_GUI_IDENTIFIER "com.mediahasher.app"
            # CFBundleShortVersionString (user-facing) and CFBundleVersion
            # (build number); both track PROJECT_VERSION so Finder's Get
            # Info and the .dmg metadata match the release.
            MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
            MACOSX_BUNDLE_BUNDLE_VERSION       "${PROJECT_VERSION}"
            MACOSX_BUNDLE_COPYRIGHT "Copyright (C) 2026 Etienne Fleurant"
    )
endif()

# ---------------------------------------------------------------------------
# QML module
#
# C++ singletons (Backend, SettingsManager, FileSystemModel) register into
# this module via QML_ELEMENT / QML_SINGLETON in their headers; Theme.qml is
# the QML-side singleton (fonts + palette), marked below. QTP0004 generates
# the per-directory qmldir files, so none are hand-written anymore.
# ---------------------------------------------------------------------------
set_source_files_properties(
        Sources/qml/Theme.qml
        Sources/qml/components/TitleBarStyle.qml
        PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(MediaHasher
        URI com.mediahasher.app
        # Tracks the application version (major.minor - QML module
        # versions have no patch component). Purely cosmetic while all
        # imports stay versionless, but kept in lockstep so the two can
        # never drift.
        VERSION ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
        QML_FILES
        Sources/qml/Theme.qml
        Sources/qml/views/MainWindow.qml
        Sources/qml/components/AppIcon.qml
        Sources/qml/components/AutoHideScrollBar.qml
        Sources/qml/components/FileQueue.qml
        Sources/qml/components/JobsLog.qml
        Sources/qml/components/MediaTreeView.qml
        Sources/qml/components/Progress.qml
        Sources/qml/components/SettingsDialog.qml
        Sources/qml/components/SlimProgressBar.qml
        Sources/qml/components/TitleBar.qml
        Sources/qml/components/TitleBarControls.qml
        Sources/qml/components/TitleBarStyle.qml
        RESOURCES
        Sources/fonts/Inter-VariableFont_opsz,wght.ttf
        Sources/fonts/Inter-Italic-VariableFont_opsz,wght.ttf
        Sources/fonts/JetBrainsMono-VariableFont_wght.ttf
        Sources/fonts/JetBrainsMono-Italic-VariableFont_wght.ttf
        Sources/icons/breeze/control_close.svg
        Sources/icons/breeze/control_maximize.svg
        Sources/icons/breeze/control_minimize.svg
        Sources/icons/breeze/control_restore.svg
        Sources/icons/default/control_close.svg
        Sources/icons/default/control_maximize.svg
        Sources/icons/default/control_minimize.svg
        Sources/icons/default/control_restore.svg
        Sources/icons/google_material/arrow_right.svg
        Sources/icons/google_material/folder.svg
        Sources/icons/google_material/folder_open.svg
        Sources/icons/google_material/place_item.svg
        Sources/icons/google_material/video_file.svg
        Sources/icons/jetbrains_intellij/forceRefresh_dark.svg
        Sources/icons/jetbrains_intellij/inlaySettings_dark.svg
        Sources/icons/jetbrains_intellij/pause_dark.svg
        Sources/icons/jetbrains_intellij/run_dark.svg
        Sources/icons/windows/control_close.svg
        Sources/icons/windows/control_maximize.svg
        Sources/icons/windows/control_minimize.svg
        Sources/icons/windows/control_restore.svg
        Sources/images/mediahasher_text.svg
)

# ---------------------------------------------------------------------------
# Link
#
# MediaHash links OpenSSL::Crypto PUBLIC, so it arrives transitively.
# QThreadPool/QRunnable live in Qt6::Core - no Qt6::Concurrent needed.
# QFileSystemModel lives in Qt6::Gui since Qt 6 - no Qt6::Widgets needed.
# ---------------------------------------------------------------------------
target_link_libraries(MediaHasher PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
        MediaHash
        yaml-cpp::yaml-cpp
)

# ---------------------------------------------------------------------------
# Version
#
# PROJECT_VERSION is populated from ui/VERSION.txt (see the top of this
# file). It reaches the application through this compile definition and is
# surfaced in QML by the AppInfo singleton; the packaging scripts
# (scripts/build.ps1, scripts/macdeploy.sh) read the same ui/VERSION.txt
# file to name their artifacts.
# ---------------------------------------------------------------------------
target_compile_definitions(MediaHasher PRIVATE
        MEDIAHASHER_VERSION_STR="${PROJECT_VERSION}"
)

if (MSVC)
    target_compile_options(MediaHasher PRIVATE /utf-8)
endif()

# macOS frameworks for native styling.
if(APPLE)
    target_link_libraries(MediaHasher PRIVATE
            "-framework AppKit"
            "-framework Foundation"
    )
endif()

# Windows native libraries for future DWM titlebar work (shadow, Snap
# Layouts hit-testing). Re-enable when the custom title bar buttons land.
# if(WIN32)
#     target_link_libraries(MediaHasher PRIVATE dwmapi comctl32)
# endif()

target_include_directories(MediaHasher PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources
        # qmltyperegistrar includes registered headers by file name only
        # (guarded by __has_include), so every directory containing a
        # QML_ELEMENT / QML_SINGLETON header must be directly on the
        # include path or the type is silently skipped.
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/models
        ${CMAKE_CURRENT_SOURCE_DIR}/Sources/utils
)

# Warnings (errors in Debug builds only).
target_compile_options(MediaHasher PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:
        -Wall -Wextra -Wpedantic
        $<$<CONFIG:Debug>:-Werror>
        >
)

# ---------------------------------------------------------------------------
# Windows deployment (windeployqt)
# ---------------------------------------------------------------------------
if(WIN32)
    find_program(WINDEPLOYQT windeployqt HINTS "${CMAKE_PREFIX_PATH}/bin")

    if(WINDEPLOYQT)
        add_custom_command(TARGET MediaHasher POST_BUILD
                COMMAND "${WINDEPLOYQT}"
                --qmldir "${CMAKE_CURRENT_SOURCE_DIR}/Sources/qml"
                "$<TARGET_FILE:MediaHasher>"
                COMMENT "Running windeployqt"
        )
    else()
        message(WARNING "windeployqt not found - Qt DLLs won't be copied to the build directory. "
                "Set CMAKE_PREFIX_PATH to your Qt installation (e.g. C:/Qt/6.11.0/msvc2022_64).")
    endif()
endif()