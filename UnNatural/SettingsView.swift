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
            Section("スクロール反転") {
                Toggle(isOn: $settings.isActive) {
                    Label("有効にする", systemImage: settings.isActive ? "checkmark.circle.fill" : "circle")
                }
                .toggleStyle(.checkbox)
            }

            Section("対象デバイス") {
                Toggle("Trackpad", isOn: $settings.reverseTrackpad)
                    .disabled(!settings.isActive)
                Toggle("Mouse", isOn: $settings.reverseMouse)
                    .disabled(!settings.isActive)
            }

            Section {
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
