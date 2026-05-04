//
//  UnNaturalApp.swift
//  UnNatural
//
//  Created by Tomokazu HIRAI on 2026/05/04.
//

import AppKit
import SwiftUI

@main
struct UnNaturalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var scrollReverser = ScrollReverser()

    var body: some Scene {
        MenuBarExtra("UnNatural", systemImage: "arrow.up.arrow.down") {
            MenuBarContent(settings: settings, scrollReverser: scrollReverser)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings, scrollReverser: scrollReverser)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scrollReverser: ScrollReverser
    @Environment(\.openSettings) private var openSettings

    private var statusLabel: String {
        guard scrollReverser.isEnabled else { return "Disabled (Permission Required)" }
        return settings.isActive ? "Enabled" : "Disabled"
    }

    var body: some View {
        Section(statusLabel) {
            Toggle("Enable", isOn: $settings.isActive)
                .disabled(!scrollReverser.isEnabled)
        }

        Divider()

        Button("Settings...") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Exit") {
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
