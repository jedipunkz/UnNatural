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
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Basic") {
                Toggle("Enable", isOn: $settings.isActive)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            SettingsSection(title: "Mouse Reverse") {
                Toggle("Up/Down", isOn: $settings.reverseMouse)
                    .disabled(!settings.isActive)
                Toggle("Left/Right", isOn: $settings.reverseMouseHorizontal)
                    .disabled(!settings.isActive)
            }

            SettingsSection(title: "Trackpad Reverse") {
                Toggle("Up/Down", isOn: $settings.reverseTrackpad)
                    .disabled(!settings.isActive)
                Toggle("Left/Right", isOn: $settings.reverseTrackpadHorizontal)
                    .disabled(!settings.isActive)
            }

            permissionSection
        }
        .toggleStyle(.switch)
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(scrollReverser.isEnabled ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(scrollReverser.isEnabled ? "Accessibility permission is enabled" : "Accessibility permission is required")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Button("Open Preferences") {
                scrollReverser.requestAccessibilityPermission()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}
