//
//  PowerAssertionManager.swift
//  BlackoutSignal
//
//  Holds IOKit power assertions so the display keeps receiving a video signal
//  and the Mac does not idle-sleep while blackout mode is active. Assertions are
//  held ONLY during blackout and released the moment it ends (or the app quits),
//  so normal power management resumes immediately afterwards.
//

import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class PowerAssertionManager {
    private var displayAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var systemAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isHeld = false

    private static let log = Logger(subsystem: "cn.Teethe.BlackoutSignal", category: "power")

    var isActive: Bool { isHeld }

    /// Prevent idle display sleep (keeps the video signal / framebuffer alive) and
    /// idle system sleep. Idempotent.
    func begin() {
        guard !isHeld else { return }

        let displayOK = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            reason: "BlackoutSignal keeps the display signal alive",
            into: &displayAssertionID)

        let systemOK = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            reason: "BlackoutSignal prevents idle system sleep during blackout",
            into: &systemAssertionID)

        isHeld = displayOK || systemOK
        if !isHeld {
            Self.log.error("Failed to create any power assertion")
        }
    }

    /// Release every held assertion and restore normal power management. Idempotent.
    func end() {
        if displayAssertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = IOPMAssertionID(0)
        }
        if systemAssertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = IOPMAssertionID(0)
        }
        isHeld = false
    }

    private func createAssertion(type: String, reason: String, into id: inout IOPMAssertionID) -> Bool {
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id)
        if result != kIOReturnSuccess {
            Self.log.error("IOPMAssertionCreateWithName(\(type, privacy: .public)) failed: \(result)")
            return false
        }
        return true
    }
}
