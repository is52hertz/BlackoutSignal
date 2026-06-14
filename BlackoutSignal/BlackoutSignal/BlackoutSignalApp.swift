//
//  BlackoutSignalApp.swift
//  BlackoutSignal
//

import SwiftUI

@main
struct BlackoutSignalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: appDelegate.controller)
        } label: {
            Image(systemName: appDelegate.controller.isActive ? "moon.fill" : "moon.stars")
                .accessibilityLabel("BlackoutSignal")
        }

        Settings {
            SettingsView(controller: appDelegate.controller)
        }
    }
}
