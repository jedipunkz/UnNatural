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
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings, scrollReverser: scrollReverser)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Setting") {
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
