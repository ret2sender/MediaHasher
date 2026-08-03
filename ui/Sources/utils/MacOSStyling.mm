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

/// @file MacOSStyling.mm
/// @brief Objective-C++ implementation of native macOS window styling.
///
/// This file is compiled as Objective-C++ (.mm) so it can call AppKit
/// APIs directly. It bridges from Qt's QQuickWindow to the underlying
/// NSWindow to configure the title bar appearance.
///
/// The macOS styling performs five operations:
/// 1. Adds @c NSWindowStyleMaskFullSizeContentView so the Qt content
///    area extends behind the native title bar.
/// 2. Sets the title bar to transparent and hides the window title text.
/// 3. Disables the default window dragging (QML's TitleBar MouseArea
///    handles this via @c startSystemMove()).
/// 4. Measures the native title bar height (from the traffic light
///    button superview) and passes it to QML as a property so the
///    layout can offset its content accordingly.
/// 5. Observes main-window status changes and forces the traffic light
///    buttons to redraw. Mutating the style mask at runtime (step 1)
///    rebuilds the title bar, after which AppKit can fail to refresh the
///    standard buttons on focus changes - leaving them colored while the
///    window is inactive instead of the expected gray.

#include "utils/MacOSStyling.hpp"

#if defined(__APPLE__)

#import <AppKit/AppKit.h>

#include <QDebug>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

void applyMacOSStyling(QQmlApplicationEngine* engine) {
    if (engine->rootObjects().isEmpty())
        return;

    // Retrieve the root QQuickWindow from the engine.
    auto* rootObject = qobject_cast<QQuickWindow*>(engine->rootObjects().first());
    if (!rootObject) {
        qWarning().noquote() << "applyMacOSStyling: root object is not a QQuickWindow";
        return;
    }

    // On macOS, winId() returns a pointer-sized integer whose value is
    // the address of the content NSView backing the QQuickWindow.
    auto nsView = reinterpret_cast<NSView*>(rootObject->winId());
    if (!nsView) {
        qWarning().noquote() << "applyMacOSStyling: could not obtain NSView";
        return;
    }

    // Walk from the NSView to the owning NSWindow.
    NSWindow* nsWindow = [nsView window];
    if (!nsWindow) {
        qWarning().noquote() << "applyMacOSStyling: NSWindow is nil";
        return;
    }

    // Configure the title bar: transparent, full-size content view.
    NSWindowStyleMask currentMask = [nsWindow styleMask];
    [nsWindow setStyleMask:currentMask | NSWindowStyleMaskTitled
                                       | NSWindowStyleMaskFullSizeContentView];
    [nsWindow setTitlebarAppearsTransparent:YES];
    [nsWindow setTitleVisibility:NSWindowTitleHidden];
    [nsWindow setMovable:NO];

    // Measure the native title bar height from the traffic light buttons'
    // superview (NSTitlebarContainerView) and expose it to QML as the
    // "nativeTitleBarHeight" property.
    //
    // This is intentionally measured via the close button's superview rather
    // than computing (frame.size.height - contentLayoutRect.size.height).
    // The subtraction approach depends on the window being fully laid out
    // and produces incorrect values during certain lifecycle points (e.g.
    // minimize/restore), causing visible UI "jumping". The close button's
    // superview is always correctly sized immediately after setStyleMask:.
    NSButton* closeButton = [nsWindow standardWindowButton:NSWindowCloseButton];
    if (closeButton && closeButton.superview) {
        NSRect frame = closeButton.superview.frame;
        int titlebarHeight = static_cast<int>(frame.size.height);
        rootObject->setProperty("nativeTitleBarHeight", titlebarHeight);
        qDebug().noquote() << "applyMacOSStyling: titlebar height = " << titlebarHeight;
    }

    // Keep the traffic lights' active/inactive appearance in sync.
    //
    // After the styleMask mutation above rebuilds the title bar, AppKit can
    // fail to redraw the standard window buttons when the window gains or
    // loses main status: the buttons stay colored while the window is
    // inactive instead of dimming to gray like every other app. Observing
    // the main-status notifications and forcing a redraw of the button
    // cluster makes them re-query [NSWindow isMainWindow] and pick up the
    // correct artwork.
    //
    // The observer tokens are intentionally not stored or removed: the main
    // window (and thus this observation) lives for the entire application
    // lifetime, so there is nothing to clean up before process exit.
    void (^refreshTrafficLights)(NSNotification*) = ^(NSNotification* /*notification*/) {
        for (NSWindowButton buttonType : {NSWindowCloseButton,
                                          NSWindowMiniaturizeButton,
                                          NSWindowZoomButton}) {
            NSButton* button = [nsWindow standardWindowButton:buttonType];
            if (button) {
                [button setNeedsDisplay:YES];
                [button.superview setNeedsDisplay:YES];
            }
        }
    };

    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:NSWindowDidBecomeMainNotification
                        object:nsWindow
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:refreshTrafficLights];
    [center addObserverForName:NSWindowDidResignMainNotification
                        object:nsWindow
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:refreshTrafficLights];

    qDebug().noquote() << "applyMacOSStyling: styling applied successfully";
}

#else

/// @brief No-op fallback for non-macOS platforms.
void applyMacOSStyling(QQmlApplicationEngine* /*engine*/) {}

#endif