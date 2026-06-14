//
//  MenuContentView.swift
//  BlackoutSignal
//
//  The menu-bar dropdown: current status, enter/exit, settings and quit.
//

import SwiftUI

struct MenuContentView: View {
    let controller: BlackoutController

    var body: some View {
        Text(statusText)

        Divider()

        if controller.isActive {
            Button("退出黑屏模式") { controller.exitBlackout() }
        } else {
            Button("进入黑屏模式") { controller.enterBlackout() }
        }
        Text("快捷键 ⌥⌘B ・ 黑屏后按 Esc 退出")
            .font(.footnote)

        Divider()

        if controller.hotKeyConflict {
            Button("重试注册快捷键 ⌥⌘B") { controller.retryHotKeyRegistration() }
        }
        SettingsLink {
            Text("设置…")
        }
        Button("退出 BlackoutSignal") { NSApp.terminate(nil) }
    }

    private var statusText: String {
        guard controller.isActive else {
            return "状态：正常"
        }
        return "状态：黑屏中（DDC \(controller.ddcDimmedCount) ・ 覆盖 \(controller.overlayOnlyCount)）"
    }
}
