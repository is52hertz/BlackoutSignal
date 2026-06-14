//
//  HotKeyManager.swift
//  BlackoutSignal
//
//  Registers a single system-wide hotkey using the Carbon Event Manager. This is
//  deliberately chosen over an NSEvent global monitor or a CGEventTap because
//  RegisterEventHotKey requires NO Accessibility / Input-Monitoring permission —
//  the app stays free of unnecessary privacy prompts. The hotkey fires regardless
//  of which app is focused, so it can also exit blackout mode.
//

import Carbon.HIToolbox
import os

@MainActor
final class HotKeyManager {
    /// Called on the main actor when the hotkey is pressed.
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Default chord: Option (⌥) + Command (⌘) + B.
    static let defaultKeyCode = UInt32(kVK_ANSI_B)
    static let defaultModifiers = UInt32(cmdKey | optionKey)

    private static let log = Logger(subsystem: "cn.Teethe.BlackoutSignal", category: "hotkey")

    /// Registers the hotkey. Returns false on failure (e.g. another app already owns
    /// the chord), so the caller can surface a clear conflict message.
    @discardableResult
    func register(keyCode: UInt32 = defaultKeyCode,
                  modifiers: UInt32 = defaultModifiers) -> Bool {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                hotKeyEventHandler,
                                                1, &eventType, selfPtr, &eventHandler)
        guard installStatus == noErr else {
            Self.log.error("InstallEventHandler failed: \(installStatus)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: bsHotKeySignature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr, hotKeyRef != nil else {
            Self.log.error("RegisterEventHotKey failed: \(registerStatus)")
            removeHandler()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        removeHandler()
    }

    private func removeHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func fire() {
        onActivate?()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

/// 'BLKO' four-char code identifying this app's hotkey.
private let bsHotKeySignature: OSType = 0x424C_4B4F

/// C callback for the Carbon hotkey. Carbon invokes it on the main thread; we hop
/// onto the main actor and re-derive the manager from the raw pointer (so nothing
/// non-Sendable is captured across the boundary).
private let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return noErr }
    Task { @MainActor in
        Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
    }
    return noErr
}
