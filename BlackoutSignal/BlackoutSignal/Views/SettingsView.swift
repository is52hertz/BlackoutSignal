//
//  SettingsView.swift
//  BlackoutSignal
//
//  A small settings/about window using the standard grouped Form, which adopts
//  the macOS 26 look (Liquid Glass materials) automatically.
//

import SwiftUI

struct SettingsView: View {
    let controller: BlackoutController

    var body: some View {
        Form {
            Section("黑屏保信号") {
                LabeledContent("当前状态", value: controller.isActive ? "黑屏中" : "正常")
                LabeledContent("全局快捷键", value: "⌥ ⌘ B")
                LabeledContent("退出方式", value: "再按快捷键 ・ Esc ・ 菜单")
                if controller.hotKeyConflict {
                    Label("快捷键注册失败，可能与其他应用冲突", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("重试注册") { controller.retryHotKeyRegistration() }
                }
            }

            Section("工作方式") {
                Text("进入黑屏模式后，会通过 DDC/CI 将支持的外接显示器亮度降到 0，"
                     + "并在所有屏幕叠加纯黑覆盖；同时保持视频信号输出、阻止系统与显示器进入睡眠。"
                     + "退出后会恢复进入前的亮度并释放电源占用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("版本", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 360)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
