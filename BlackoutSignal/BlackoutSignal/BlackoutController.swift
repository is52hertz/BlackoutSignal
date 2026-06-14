//
//  BlackoutController.swift
//  BlackoutSignal
//
//  Single source of truth for blackout mode. Orchestrates the overlay, DDC/CI
//  brightness, power assertions, the global hotkey and crash-recovery persistence.
//  Entering and exiting are designed to complete well under one second.
//

import AppKit
import Observation
import os

@MainActor
@Observable
final class BlackoutController {
    enum State {
        case idle
        case active
    }

    private(set) var state: State = .idle
    var isActive: Bool { state == .active }

    /// Number of displays whose backlight was dimmed via DDC/CI this session.
    private(set) var ddcDimmedCount = 0
    /// Number of displays covered by the black overlay only (no DDC).
    private(set) var overlayOnlyCount = 0
    /// True when the global hotkey could not be registered (e.g. taken by another app).
    private(set) var hotKeyConflict = false

    /// A previous session that did not exit cleanly (set at launch). The UI offers to restore it.
    private(set) var pendingRecovery: BlackoutSession?

    private let overlay = OverlayManager()
    private let power = PowerAssertionManager()
    private let hotKey = HotKeyManager()
    private let store: BrightnessStore

    /// Displays dimmed in the current session, with the exact value to restore.
    private var dimmed: [(display: BSDisplayDDC, original: Int)] = []

    private static let log = Logger(subsystem: "cn.Teethe.BlackoutSignal", category: "controller")

    init(store: BrightnessStore = BrightnessStore()) {
        self.store = store
    }

    // MARK: - Lifecycle

    /// Wire up callbacks, register the hotkey, and detect an interrupted previous session.
    func start() {
        overlay.onExitRequested = { [weak self] in self?.exitBlackout() }
        hotKey.onActivate = { [weak self] in self?.toggle() }
        hotKeyConflict = !hotKey.register()
        pendingRecovery = store.load()
    }

    func toggle() {
        switch state {
        case .idle: enterBlackout()
        case .active: exitBlackout()
        }
    }

    /// Re-attempt hotkey registration after the user resolved a conflict.
    @discardableResult
    func retryHotKeyRegistration() -> Bool {
        hotKeyConflict = !hotKey.register()
        return !hotKeyConflict
    }

    // MARK: - Enter / Exit

    func enterBlackout() {
        guard state == .idle else { return }

        // 1. Instant black on every screen first, so the experience feels immediate.
        overlay.show()
        // 2. Keep the video signal and the Mac awake (only while blacked out).
        power.begin()

        // 3. Read + remember each DDC display's brightness, persist, then dim to 0.
        let displays = BSDisplayDDC.onlineDisplays()
        var recovery: [String: Int] = [:]
        dimmed.removeAll()
        for display in displays where display.supportsDDC {
            var current: Int32 = 0
            var max: Int32 = 0
            // Only dim displays whose brightness we could read — otherwise we could
            // not reliably restore them, and the overlay already guarantees black.
            if display.readBrightnessCurrent(&current, max: &max) {
                dimmed.append((display, Int(current)))
                recovery[display.stableKey] = Int(current)
            }
        }
        // Persist BEFORE dimming so a crash can always recover what we are about to change.
        if !recovery.isEmpty {
            store.save(BlackoutSession(brightness: recovery))
        }
        for entry in dimmed {
            _ = entry.display.writeBrightness(0)
        }

        ddcDimmedCount = dimmed.count
        overlayOnlyCount = max(0, displays.count - dimmed.count)
        state = .active
        Self.log.info("Entered blackout: \(self.ddcDimmedCount) dimmed, \(self.overlayOnlyCount) overlay-only")
    }

    func exitBlackout() {
        guard state == .active else { return }

        // 1. Restore brightness first (while still black) to avoid a bright flash.
        var failures: [String] = []
        for entry in dimmed where entry.display.supportsDDC {
            if !entry.display.writeBrightness(Int32(entry.original)) {
                failures.append(entry.display.productName ?? entry.display.stableKey)
            }
        }
        // 2. Release power assertions and remove the overlay.
        power.end()
        overlay.hide()

        dimmed.removeAll()
        ddcDimmedCount = 0
        overlayOnlyCount = 0
        state = .idle

        if failures.isEmpty {
            store.clear()   // clean exit — no recovery needed next launch
        } else {
            // Keep the session file so the next launch can offer recovery.
            Self.log.error("Brightness restore failed for: \(failures.joined(separator: ", "))")
            presentRestoreFailure(displays: failures)
        }
    }

    /// Restore on app termination (best effort, synchronous).
    func handleAppWillTerminate() {
        if state == .active {
            exitBlackout()
        }
    }

    // MARK: - Crash recovery

    /// Restore brightness for the interrupted session by matching current displays.
    func performRecovery() {
        guard let session = pendingRecovery else { return }
        var failures: [String] = []
        let displays = BSDisplayDDC.onlineDisplays()
        for display in displays where display.supportsDDC {
            if let value = session.brightness[display.stableKey] {
                if !display.writeBrightness(Int32(value)) {
                    failures.append(display.productName ?? display.stableKey)
                }
            }
        }
        store.clear()
        pendingRecovery = nil
        if !failures.isEmpty {
            presentRestoreFailure(displays: failures)
        }
    }

    /// User declined recovery — forget the pending session.
    func dismissRecovery() {
        store.clear()
        pendingRecovery = nil
    }

    // MARK: - Alerts

    private func presentRestoreFailure(displays: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "亮度恢复失败"
        alert.informativeText = """
        以下显示器的亮度未能通过 DDC/CI 恢复，请使用显示器自带按钮手动调整：
        \(displays.joined(separator: "\n"))
        """
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
