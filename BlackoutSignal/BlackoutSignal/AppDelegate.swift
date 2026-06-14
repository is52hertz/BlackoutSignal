//
//  AppDelegate.swift
//  BlackoutSignal
//
//  Owns the BlackoutController and configures the process as a menu-bar-only
//  (accessory) app with no Dock icon. Also drives the launch-time crash-recovery
//  prompt and ensures brightness is restored when the app quits.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = BlackoutController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        controller.start()

        if controller.pendingRecovery != nil {
            presentRecoveryPrompt()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.handleAppWillTerminate()
    }

    private func presentRecoveryPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "检测到上次异常退出"
        alert.informativeText = "BlackoutSignal 上次可能未正常恢复显示器亮度。是否现在恢复到进入黑屏前的亮度？"
        alert.addButton(withTitle: "恢复亮度")
        alert.addButton(withTitle: "忽略")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            controller.performRecovery()
        } else {
            controller.dismissRecovery()
        }
    }
}
