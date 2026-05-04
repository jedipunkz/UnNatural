//
//  AppSettings.swift
//  UnNatural
//
//  Created by Tomokazu HIRAI on 2026/05/04.
//

import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let reverseTrackpad = "reverseTrackpad"
        static let reverseMouse = "reverseMouse"
    }

    @Published var reverseTrackpad: Bool {
        didSet {
            UserDefaults.standard.set(reverseTrackpad, forKey: Key.reverseTrackpad)
        }
    }

    @Published var reverseMouse: Bool {
        didSet {
            UserDefaults.standard.set(reverseMouse, forKey: Key.reverseMouse)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Key.reverseTrackpad) == nil {
            defaults.set(true, forKey: Key.reverseTrackpad)
        }

        reverseTrackpad = defaults.bool(forKey: Key.reverseTrackpad)
        reverseMouse = defaults.bool(forKey: Key.reverseMouse)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            NSLog("Failed to update login item: \(error.localizedDescription)")
        }
    }
}
