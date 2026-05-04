//
//  SettingsView.swift
//  UnNatural
//
//  Created by Tomokazu HIRAI on 2026/05/04.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scrollReverser: ScrollReverser

    var body: some View {
        Form {
            Section {
                Toggle("Trackpad", isOn: $settings.reverseTrackpad)
                Toggle("Mouse", isOn: $settings.reverseMouse)
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
            }

            Section {
                HStack {
                    Circle()
                        .fill(scrollReverser.isEnabled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(scrollReverser.isEnabled ? "Scroll monitor is active" : "Accessibility permission is required")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open Permission") {
                        scrollReverser.requestAccessibilityPermission()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
