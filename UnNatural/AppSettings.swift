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
        static let reverseTrackpadHorizontal = "reverseTrackpadHorizontal"
        static let reverseMouse = "reverseMouse"
        static let reverseMouseHorizontal = "reverseMouseHorizontal"
        static let isActive = "isActive"
        static let reverseHid = "reverseHid"
    }

    @Published var isActive: Bool {
        didSet {
            UserDefaults.standard.set(isActive, forKey: Key.isActive)
        }
    }

    @Published var reverseTrackpad: Bool {
        didSet {
            UserDefaults.standard.set(reverseTrackpad, forKey: Key.reverseTrackpad)
        }
    }

    @Published var reverseTrackpadHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(reverseTrackpadHorizontal, forKey: Key.reverseTrackpadHorizontal)
        }
    }

    @Published var reverseMouse: Bool {
        didSet {
            UserDefaults.standard.set(reverseMouse, forKey: Key.reverseMouse)
        }
    }

    @Published var reverseMouseHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(reverseMouseHorizontal, forKey: Key.reverseMouseHorizontal)
        }
    }

    @Published var reverseHid: Bool {
        didSet {
            UserDefaults.standard.set(reverseHid, forKey: Key.reverseHid)
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
        if defaults.object(forKey: Key.isActive) == nil {
            defaults.set(true, forKey: Key.isActive)
        }

        isActive = defaults.bool(forKey: Key.isActive)
        reverseTrackpad = defaults.bool(forKey: Key.reverseTrackpad)
        reverseTrackpadHorizontal = defaults.bool(forKey: Key.reverseTrackpadHorizontal)
        reverseMouse = defaults.bool(forKey: Key.reverseMouse)
        reverseMouseHorizontal = defaults.bool(forKey: Key.reverseMouseHorizontal)
        reverseHid = defaults.bool(forKey: Key.reverseHid)
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
