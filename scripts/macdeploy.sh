#!/usr/bin/env bash
#
# MediaHasher - macOS bundle deployment.
#
# Copies the Qt frameworks, QML modules and third-party dylibs the app links
# against into MediaHasher.app, rewrites their install names, re-signs the
# bundle, and reports anything still pointing outside the bundle.
#
# Usage:
#   scripts/macdeploy.sh [path/to/MediaHasher.app] [--dmg]
#
# Environment:
#   QT_PREFIX           Qt installation prefix (default: `brew --prefix qt`)
#   QMLDIR              QML source directory to scan (default: ui/Sources/qml)
#   APPSTORE_COMPLIANT  Pass -appstore-compliant to macdeployqt, skipping
#                       plugins that use private API (default: 1; set 0 to
#                       deploy them)
#   PRUNE_PLUGINS       Space-separated plugin directories to delete after
#                       deployment (default: sqldrivers; set empty to keep all)
#   BUILD_TYPE          Build type of the bundle being deployed. Anything
#                       other than Release adds a lowercase suffix to the
#                       .dmg name (e.g. -debug), so a Debug image can never
#                       masquerade as a release. The Makefile passes this
#                       automatically; unset means no suffix.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

BUNDLE="${1:-build/app/MediaHasher.app}"
QMLDIR="${QMLDIR:-ui/Sources/qml}"
MAKE_DMG=0

for arg in "$@"; do
    [[ "$arg" == "--dmg" ]] && MAKE_DMG=1
done

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: this script only runs on macOS." >&2
    exit 1
fi

if [[ ! -d "$BUNDLE" ]]; then
    echo "error: bundle not found: $BUNDLE" >&2
    echo "       build it first (e.g. 'make app')." >&2
    exit 1
fi

if [[ ! -d "$QMLDIR" ]]; then
    echo "error: QML directory not found: $QMLDIR" >&2
    echo "       run this from the repository root, or set QMLDIR." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Project version
#
# ui/VERSION.txt is the single source of truth (ui/CMakeLists.txt feeds
# project() from the same file); the .dmg is named after it so a release
# image is identifiable without mounting it. The QMLDIR check above
# already guarantees this script runs from the repository root.
# ---------------------------------------------------------------------------
VERSION="$(tr -d '[:space:]' < ui/VERSION.txt 2>/dev/null || true)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "warning: ui/VERSION.txt does not contain a semantic version;"
    echo "         the .dmg will be named 'unversioned'."
    VERSION="unversioned"
fi

# ---------------------------------------------------------------------------
# Locate macdeployqt
# ---------------------------------------------------------------------------
MACDEPLOYQT=""
if [[ -n "${QT_PREFIX:-}" && -x "$QT_PREFIX/bin/macdeployqt" ]]; then
    MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
elif command -v macdeployqt >/dev/null 2>&1; then
    MACDEPLOYQT="$(command -v macdeployqt)"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix qt)/bin/macdeployqt" ]]; then
    MACDEPLOYQT="$(brew --prefix qt)/bin/macdeployqt"
fi

if [[ -z "$MACDEPLOYQT" ]]; then
    echo "error: macdeployqt not found." >&2
    echo "       Set QT_PREFIX to your Qt installation, e.g.:" >&2
    echo "         QT_PREFIX=\$(brew --prefix qt) scripts/macdeploy.sh" >&2
    exit 1
fi

echo "==> macdeployqt : $MACDEPLOYQT"
echo "==> bundle      : $BUNDLE"
echo "==> qml sources : $QMLDIR"
echo

# ---------------------------------------------------------------------------
# Warn if the bundle looks already-deployed
#
# Running macdeployqt twice over the same bundle can mangle install names.
# A fresh build is always the safe input.
# ---------------------------------------------------------------------------
if [[ -d "$BUNDLE/Contents/Frameworks" ]]; then
    echo "warning: $BUNDLE already contains Contents/Frameworks, so it looks"
    echo "         deployed. Re-running macdeployqt over a deployed bundle can"
    echo "         corrupt install names. Prefer a clean rebuild:"
    echo "             make distclean && make app && make bundle"
    echo
fi

# ---------------------------------------------------------------------------
# Deploy
#
# -appstore-compliant skips the plugins Qt knows use private API: currently
# the qsqlodbc and qsqlpsql SQL drivers. Those are the two that emit "uses
# private API" warnings, and qsqlodbc is the one that leaves a dangling
# reference to libiodbc. Skipping them here is cleaner than deleting them
# afterwards. Set APPSTORE_COMPLIANT=0 to deploy them anyway.
#
# Note this only covers those two drivers; the remaining unused SQL drivers
# are handled by the pruning step below.
# ---------------------------------------------------------------------------
APPSTORE_COMPLIANT="${APPSTORE_COMPLIANT:-1}"

DEPLOY_ARGS=("$BUNDLE" "-qmldir=$QMLDIR" "-always-overwrite" "-verbose=1")

# The mediahash CLI is placed inside the bundle by the build. It links the
# core library statically but still resolves OpenSSL, BLAKE3 and xxHash
# dynamically, so it needs the same install-name rewriting as the app.
CLI_PATH="$BUNDLE/Contents/MacOS/mediahash"
if [[ -f "$CLI_PATH" ]]; then
    DEPLOY_ARGS+=("-executable=$CLI_PATH")
fi

if [[ "$APPSTORE_COMPLIANT" != "0" ]]; then
    DEPLOY_ARGS+=("-appstore-compliant")
fi

# The disk image is intentionally NOT requested from macdeployqt here (no
# -dmg flag): macdeployqt builds its image immediately after deployment,
# which would snapshot the bundle before the pruning and re-signing steps
# below have run. The image is created at the end of this script instead.

echo "==> Running macdeployqt..."
echo "    flags: ${DEPLOY_ARGS[*]:1}"
"$MACDEPLOYQT" "${DEPLOY_ARGS[@]}"
echo

# ---------------------------------------------------------------------------
# Prune unused plugins and styles
#
# macdeployqt copies plugins by category, tied to the frameworks in use rather
# than to what the application actually loads. Two consequences:
#
#   * Every SQL driver arrives because QtSql is pulled in transitively by the
#     QML LocalStorage plugin. They link against PostgreSQL/ODBC/Mimer client
#     libraries that are usually absent, which is where the "no file at ..."
#     errors come from.
#
#   * Every Qt Quick Controls style arrives because QtQuickControls2 is in use.
#     Importing a specific style in QML does not prevent this; plugin
#     deployment is not driven by the QML import scan.
#
# Each style exists as up to three pieces - a framework pair, a plugin pair,
# and a QML module directory - which must be removed together or the survivors
# reference something that is no longer there.
#
# This must happen before signing: deleting files afterwards invalidates the
# signature.
#
#   PRUNE_PLUGINS  plugin directories to delete       (default: sqldrivers)
#   PRUNE_STYLES   Quick Controls styles to delete    (default: all but Basic)
#
# Set either to "" to keep everything. If the application ever calls
# QQuickStyle::setStyle() with something other than Basic, adjust PRUNE_STYLES
# to match or the chosen style will be missing at runtime.
# ---------------------------------------------------------------------------
PRUNE_PLUGINS="${PRUNE_PLUGINS-sqldrivers}"
PRUNE_STYLES="${PRUNE_STYLES-Material Fusion Imagine Universal FluentWinUI3 IOS MacOS}"

shopt -s nullglob

if [[ -n "$PRUNE_PLUGINS" || -n "$PRUNE_STYLES" ]]; then
    echo "==> Pruning unused components..."
    pruned=0

    for d in $PRUNE_PLUGINS; do
        target="$BUNDLE/Contents/PlugIns/$d"
        if [[ -d "$target" ]]; then
            rm -rf "$target"
            echo "    plugins    PlugIns/$d"
            pruned=$((pruned + 1))
        fi
    done

    for S in $PRUNE_STYLES; do
        s="$(echo "$S" | tr '[:upper:]' '[:lower:]')"

        for fw in "$BUNDLE"/Contents/Frameworks/QtQuickControls2"$S"*.framework; do
            rm -rf "$fw"
            echo "    framework  $(basename "$fw")"
            pruned=$((pruned + 1))
        done

        for pl in "$BUNDLE"/Contents/PlugIns/quick/libqtquickcontrols2"$s"style*plugin.dylib; do
            rm -f "$pl"
            echo "    plugin     $(basename "$pl")"
            pruned=$((pruned + 1))
        done

        # QML directory names differ in case from the module names
        # (iOS vs IOS, macOS vs MacOS), so match case-insensitively.
        qmlroot="$BUNDLE/Contents/Resources/qml/QtQuick/Controls"
        if [[ -d "$qmlroot" ]]; then
            while IFS= read -r d; do
                [[ -n "$d" ]] || continue
                rm -rf "$d"
                echo "    qml        QtQuick/Controls/${d##*/}"
                pruned=$((pruned + 1))
            done < <(find "$qmlroot" -maxdepth 1 -type d -iname "$S" 2>/dev/null || true)
        fi
    done

    echo "    ($pruned items removed)"
    echo
fi

# ---------------------------------------------------------------------------
# Ad-hoc code signature
#
# Rewriting install names invalidates any existing signature. On Apple
# Silicon every binary must carry at least an ad-hoc signature or the app
# is killed at launch, so re-sign the whole bundle.
# ---------------------------------------------------------------------------
echo "==> Re-signing (ad-hoc)..."
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/    /' || true
echo

# ---------------------------------------------------------------------------
# Verify self-containment
#
# Walk every Mach-O file in the bundle and report load commands still
# resolving to Homebrew or other prefixes outside the bundle.
# ---------------------------------------------------------------------------
echo "==> Checking for dependencies outside the bundle..."

EXTERNAL="$(
    find "$BUNDLE/Contents" -type f -print0 |
    while IFS= read -r -d '' f; do
        file -b "$f" 2>/dev/null | grep -q 'Mach-O' || continue
        otool -L "$f" 2>/dev/null | tail -n +2 |
            grep -E '/opt/homebrew|/usr/local/opt|/usr/local/Cellar|/opt/local' |
            sed "s|^[[:space:]]*|    ${f#"$BUNDLE"/}: |"
    done || true
)"

if [[ -n "$EXTERNAL" ]]; then
    echo
    echo "  The following still reference libraries outside the bundle:"
    echo "$EXTERNAL"
    echo
    echo "  The app will run on this machine but not on one without those"
    echo "  libraries installed. Each can be fixed with install_name_tool,"
    echo "  or by passing the library to macdeployqt explicitly."
    echo
    echo "  (System libraries under /usr/lib and /System are expected and"
    echo "  are not reported here.)"
else
    echo "    None - every linked library resolves inside the bundle or to"
    echo "    system paths. The bundle looks self-contained."
fi

echo
echo "==> Checking for references to removed frameworks..."

DANGLING="$(
    find "$BUNDLE/Contents" -type f -print0 |
    while IFS= read -r -d '' f; do
        file -b "$f" 2>/dev/null | grep -q 'Mach-O' || continue
        otool -L "$f" 2>/dev/null | tail -n +2 |
            grep -o '@rpath/[A-Za-z0-9_.]*\.framework' | sort -u |
            while IFS= read -r ref; do
                name="${ref#@rpath/}"
                if [[ ! -d "$BUNDLE/Contents/Frameworks/$name" ]]; then
                    echo "    ${f#"$BUNDLE"/} -> $name"
                fi
            done
    done | sort -u || true
)"

if [[ -n "$DANGLING" ]]; then
    echo
    echo "  These link against frameworks that are not in the bundle:"
    echo "$DANGLING"
    echo
    echo "  Pruning removed something still in use. Re-run with the relevant"
    echo "  style restored, e.g.:"
    echo "      PRUNE_STYLES=\"Material Fusion\" make BUILD_TYPE=Release bundle"
    echo "  or PRUNE_STYLES=\"\" to keep them all."
else
    echo "    None - every framework reference resolves inside the bundle."
fi

echo
echo "==> Done: $BUNDLE"

# ---------------------------------------------------------------------------
# Disk image
#
# Created here, as the final step, rather than via macdeployqt's own -dmg
# flag: macdeployqt images the bundle immediately after deployment, so the
# pruning and re-signing above would not be reflected in the shipped file.
# Using hdiutil directly also fixes the volume name - macdeployqt derives
# it from the bundle path (a release image would mount as
# "build:app-release:MediaHasher"), while hdiutil is told the real name.
#
# Release images carry no build-type suffix; anything else is marked so a
# Debug image can never masquerade as a release. Mirrors the Windows zip
# naming in scripts/build.ps1.
# ---------------------------------------------------------------------------
if [[ "$MAKE_DMG" -eq 1 ]]; then
    TYPE_TAG=""
    if [[ -n "${BUILD_TYPE:-}" && "${BUILD_TYPE}" != "Release" ]]; then
        TYPE_TAG="-$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')"
    fi

    DMG_DST="$(dirname "$BUNDLE")/MediaHasher-$VERSION-macos-$(uname -m)$TYPE_TAG.dmg"

    echo "==> Creating disk image..."
    rm -f "$DMG_DST"
    hdiutil create -volname "MediaHasher" -srcfolder "$BUNDLE" \
        -format UDZO -ov "$DMG_DST"
    echo "==> Disk image: $DMG_DST"
fi
