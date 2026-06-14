//
//  OverlayManager.swift
//  BlackoutSignal
//
//  Creates one borderless, pure-black window per screen at the shielding window
//  level (above the menu bar and Dock). This is the reliable guarantee that the
//  screen looks black even on displays without DDC/CI. The overlay shows nothing —
//  no text, icons, or animation — hides the cursor, and captures Esc so the user
//  can always escape the blackout.
//

import AppKit
import CoreGraphics

/// Borderless window that can take keyboard focus (so it can receive Esc) and
/// swallows key events to avoid system beeps.
final class OverlayWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
        // Intentionally do not call super: we swallow every key while blacked out.
    }
}

@MainActor
final class OverlayManager: NSObject {
    /// Invoked when the user presses Esc on the overlay.
    var onExitRequested: (() -> Void)?

    private(set) var isShown = false
    private var windows: [OverlayWindow] = []

    private static let escapeKeyCode: UInt16 = 53

    func show() {
        guard !isShown else { return }
        isShown = true
        buildWindows()
        NSCursor.hide()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        tearDownWindows()
        NSCursor.unhide()
    }

    // MARK: - Windows

    private func buildWindows() {
        NSApp.activate(ignoringOtherApps: true)
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false)
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: true)
            window.onKeyDown = { [weak self] event in
                if event.keyCode == OverlayManager.escapeKeyCode {
                    self?.onExitRequested?()
                }
            }

            if index == 0 {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            windows.append(window)
        }
        // Ensure a key window exists so Esc is delivered even if screen 0 was busy.
        windows.first?.makeKey()
    }

    private func tearDownWindows() {
        for window in windows {
            window.onKeyDown = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    @objc private func screensChanged() {
        guard isShown else { return }
        // Rebuild to cover any added/removed/rearranged displays. Hot-plug safe.
        tearDownWindows()
        buildWindows()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
