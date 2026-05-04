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
            Section("Basic") {
                Toggle("Enable", isOn: $settings.isActive)
                    .toggleStyle(.switch)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Devices") {
                Toggle("Trackpad", isOn: $settings.reverseTrackpad)
                    .disabled(!settings.isActive)
                Toggle("Mouse", isOn: $settings.reverseMouse)
                    .disabled(!settings.isActive)
            }

            if !scrollReverser.isEnabled {
                Section {
                    HStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)

                        Text("Accessibility permission is required")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Open Permission") {
                            scrollReverser.requestAccessibilityPermission()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
