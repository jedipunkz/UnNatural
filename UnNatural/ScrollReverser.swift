//
//  ScrollReverser.swift
//  UnNatural
//
//  Created by Tomokazu HIRAI on 2026/05/04.
//

import ApplicationServices
import AppKit
import Combine
import Darwin
import Foundation

private typealias IOHIDEventRef = UnsafeMutableRawPointer
private typealias IOHIDEventField = UInt32
private typealias IOHIDFloat = Double

nonisolated private let kIOHIDEventTypeScroll: UInt32 = 6
nonisolated private let kIOHIDEventFieldScrollBase = kIOHIDEventTypeScroll << 16
nonisolated private let kIOHIDEventFieldScrollX = kIOHIDEventFieldScrollBase | 0
nonisolated private let kIOHIDEventFieldScrollY = kIOHIDEventFieldScrollBase | 1

@_silgen_name("CGEventCopyIOHIDEvent")
nonisolated private func CGEventCopyIOHIDEvent(_ event: CGEvent) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
nonisolated private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: IOHIDEventField) -> IOHIDFloat

@_silgen_name("IOHIDEventSetFloatValue")
nonisolated private func IOHIDEventSetFloatValue(_ event: IOHIDEventRef, _ field: IOHIDEventField, _ value: IOHIDFloat)

@_silgen_name("CFRelease")
nonisolated private func CFReleaseSPI(_ value: IOHIDEventRef)

@MainActor
final class ScrollReverser: ObservableObject {
    @Published private(set) var isEnabled = false

    private static let iPhoneMirroringBundleID = "com.apple.ScreenContinuity"
    private static let swipeScrollDirectionKey = "com.apple.swipescrolldirection"
    private static let swipeScrollDirectionDidChangeNotification = Notification.Name("SwipeScrollDirectionDidChangeNotification")
    private typealias SetSwipeScrollDirectionFunction = @convention(c) (Bool) -> Void
    private static let setSwipeScrollDirectionFunction: SetSwipeScrollDirectionFunction? = {
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let symbol = dlsym(handle, "setSwipeScrollDirection") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetSwipeScrollDirectionFunction.self)
    }()

    private let eventState = ScrollEventState()
    private var activeEventTap: CFMachPort?
    private var activeRunLoopSource: CFRunLoopSource?
    private var passiveEventTap: CFMachPort?
    private var passiveRunLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()
    private var savedSwipeScrollDirection: Bool?
    private var appliedSwipeScrollDirection: Bool?
    private var isIPhoneMirroringFrontmost = false

    init() {
        start()
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
        start()
    }

    private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    func start() {
        stop()
        eventState.reset()

        let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let gestureMask = CGEventMask(1 << UInt64(NSEvent.EventType.gesture.rawValue))
        let userInfo = Unmanaged.passUnretained(eventState).toOpaque()

        guard let activeTap = makeActiveTap(mask: scrollMask, userInfo: userInfo) else {
            isEnabled = false
            return
        }

        guard let passiveTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: gestureMask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        ) else {
            CFMachPortInvalidate(activeTap)
            isEnabled = false
            return
        }

        guard let activeSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, activeTap, 0),
              let passiveSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, passiveTap, 0) else {
            CFMachPortInvalidate(activeTap)
            CFMachPortInvalidate(passiveTap)
            isEnabled = false
            return
        }

        activeEventTap = activeTap
        activeRunLoopSource = activeSource
        passiveEventTap = passiveTap
        passiveRunLoopSource = passiveSource

        CFRunLoopAddSource(CFRunLoopGetMain(), activeSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), passiveSource, .commonModes)
        CGEvent.tapEnable(tap: activeTap, enable: true)
        CGEvent.tapEnable(tap: passiveTap, enable: true)
        isEnabled = true

        observeActiveApplication()
    }

    func stop() {
        restoreSwipeScrollDirectionIfNeeded()
        cancellables.removeAll()

        if let tap = activeEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let tap = passiveEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = activeRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let source = passiveRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        activeEventTap = nil
        activeRunLoopSource = nil
        passiveEventTap = nil
        passiveRunLoopSource = nil
        isEnabled = false
    }

    private func observeActiveApplication() {
        let bundleID = Self.iPhoneMirroringBundleID
        let state = eventState

        func updateIPhoneMirroringProcesses() {
            let processIDs = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == bundleID }
                .map(\.processIdentifier)
            state.setIPhoneMirroringProcessIDs(processIDs)
        }

        let current = NSWorkspace.shared.frontmostApplication
        setIPhoneMirroringFrontmost(current?.bundleIdentifier == bundleID)
        updateIPhoneMirroringProcesses()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self.setIPhoneMirroringFrontmost(app?.bundleIdentifier == bundleID)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { _ in
                updateIPhoneMirroringProcesses()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyIPhoneMirroringScrollDirection()
            }
            .store(in: &cancellables)
    }

    private func setIPhoneMirroringFrontmost(_ value: Bool) {
        isIPhoneMirroringFrontmost = value
        eventState.setIPhoneMirroringFrontmost(value)
        applyIPhoneMirroringScrollDirection()
    }

    private func applyIPhoneMirroringScrollDirection() {
        let defaults = UserDefaults.standard
        let shouldReverse = isIPhoneMirroringFrontmost &&
            defaults.bool(forKey: "isActive") &&
            defaults.bool(forKey: "reverseTrackpadHid")

        guard shouldReverse else {
            restoreSwipeScrollDirectionIfNeeded()
            return
        }

        let originalDirection = savedSwipeScrollDirection ?? Self.currentSwipeScrollDirection()
        savedSwipeScrollDirection = originalDirection
        setSwipeScrollDirectionIfNeeded(!originalDirection)
    }

    private func restoreSwipeScrollDirectionIfNeeded() {
        guard let originalDirection = savedSwipeScrollDirection else {
            return
        }

        setSwipeScrollDirectionIfNeeded(originalDirection)
        savedSwipeScrollDirection = nil
        appliedSwipeScrollDirection = nil
    }

    private func setSwipeScrollDirectionIfNeeded(_ enabled: Bool) {
        guard appliedSwipeScrollDirection != enabled else {
            return
        }

        Self.setSwipeScrollDirection(enabled)
        appliedSwipeScrollDirection = enabled
    }

    private static func currentSwipeScrollDirection() -> Bool {
        guard let value = UserDefaults.standard.object(forKey: swipeScrollDirectionKey) as? Bool else {
            return true
        }
        return value
    }

    private static func setSwipeScrollDirection(_ enabled: Bool) {
        if let setSwipeScrollDirectionFunction {
            setSwipeScrollDirectionFunction(enabled)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["write", "-g", swipeScrollDirectionKey, "-bool", enabled ? "YES" : "NO"]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("Failed to update swipe scroll direction: \(error.localizedDescription)")
            }
        }

        DistributedNotificationCenter.default().postNotificationName(
            swipeScrollDirectionDidChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: false
        )
    }

    private nonisolated static func makeTap(location: CGEventTapLocation, mask: CGEventMask, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: location,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollEventTapCallback,
            userInfo: userInfo
        )
    }

    private func makeActiveTap(mask: CGEventMask, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        if let tap = Self.makeTap(location: .cghidEventTap, mask: mask, userInfo: userInfo) {
            return tap
        }

        if let tap = Self.makeTap(location: .cgSessionEventTap, mask: mask, userInfo: userInfo) {
            return tap
        }

        return nil
    }

    private nonisolated static func eventState(from userInfo: UnsafeMutableRawPointer?) -> ScrollEventState? {
        guard let userInfo else {
            return nil
        }

        return Unmanaged<ScrollEventState>.fromOpaque(userInfo).takeUnretainedValue()
    }

    fileprivate nonisolated static func handleEvent(type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        guard let state = eventState(from: userInfo) else {
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == UInt32(NSEvent.EventType.gesture.rawValue) {
            let nsEvent = NSEvent(cgEvent: event)
            let touching = nsEvent?.touches(matching: .touching, in: nil).count ?? 0
            if touching >= 2 {
                state.recordTrackpadTouch(count: touching)
            }

            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                return Unmanaged.passUnretained(event)
            }

            return Unmanaged.passUnretained(event)
        }

        let defaults = UserDefaults.standard

        guard defaults.bool(forKey: "isActive") else {
            return Unmanaged.passUnretained(event)
        }

        let source = state.source(for: event)
        let reverseVertical: Bool
        let reverseHorizontal: Bool
        if state.isIPhoneMirroringEvent(event) {
            switch source {
            case .trackpad:
                reverseVertical = defaults.bool(forKey: "reverseTrackpadHid")
            case .mouse:
                reverseVertical = defaults.bool(forKey: "reverseMouseHid")
            }
            reverseHorizontal = false
        } else {
            switch source {
            case .trackpad:
                reverseVertical = defaults.bool(forKey: "reverseTrackpad")
                reverseHorizontal = defaults.bool(forKey: "reverseTrackpadHorizontal")
            case .mouse:
                reverseVertical = defaults.bool(forKey: "reverseMouse")
                reverseHorizontal = defaults.bool(forKey: "reverseMouseHorizontal")
            }
        }

        if reverseVertical || reverseHorizontal {
            reverseScrollEvent(event, reverseVertical: reverseVertical, reverseHorizontal: reverseHorizontal)
        }

        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    private nonisolated static func reverseScrollEvent(_ event: CGEvent, reverseVertical: Bool, reverseHorizontal: Bool) -> Bool {
        let values = ScrollEventValues(event: event)

        if reverseVertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -values.deltaY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -values.fixedDeltaY)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -values.pointDeltaY)
        }
        if reverseHorizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -values.deltaX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -values.fixedDeltaX)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -values.pointDeltaX)
        }

        guard let ioHidEvent = CGEventCopyIOHIDEvent(event) else {
            return false
        }

        if reverseVertical {
            let y = IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY)
            if y != 0 {
                IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY, -y)
            }
        }
        if reverseHorizontal {
            let x = IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX)
            if x != 0 {
                IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX, -x)
            }
        }

        CFReleaseSPI(ioHidEvent)
        return true
    }
}

nonisolated(unsafe) private let scrollEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    ScrollReverser.handleEvent(type: type, event: event, userInfo: userInfo)
}

private enum ScrollEventSource: String, Sendable {
    case mouse
    case trackpad
}

struct ScrollEventValues: Sendable, Equatable {
    let deltaY: Int64
    let deltaX: Int64
    let pointDeltaY: Int64
    let pointDeltaX: Int64
    let fixedDeltaY: Double
    let fixedDeltaX: Double

    nonisolated init(event: CGEvent) {
        deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        pointDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        pointDeltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        fixedDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        fixedDeltaX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    }
}

private final class ScrollEventState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var lastTouchTime: UInt64 = 0
    nonisolated(unsafe) private var touching = 0
    nonisolated(unsafe) private var lastSource = ScrollEventSource.mouse
    nonisolated(unsafe) private var iPhoneMirroringFrontmost = false
    nonisolated(unsafe) private var iPhoneMirroringProcessIDs = Set<pid_t>()

    nonisolated func reset() {
        lock.lock()
        lastTouchTime = 0
        touching = 0
        lastSource = .mouse
        iPhoneMirroringFrontmost = false
        iPhoneMirroringProcessIDs.removeAll()
        lock.unlock()
    }

    nonisolated func setIPhoneMirroringFrontmost(_ value: Bool) {
        lock.lock()
        iPhoneMirroringFrontmost = value
        lock.unlock()
    }

    nonisolated func isIPhoneMirroringFrontmost() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return iPhoneMirroringFrontmost
    }

    nonisolated func setIPhoneMirroringProcessIDs(_ processIDs: [pid_t]) {
        lock.lock()
        iPhoneMirroringProcessIDs = Set(processIDs)
        lock.unlock()
    }

    nonisolated func isIPhoneMirroringEvent(_ event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        return iPhoneMirroringFrontmost || iPhoneMirroringProcessIDs.contains(targetPID)
    }

    nonisolated func recordTrackpadTouch(count: Int) {
        lock.lock()
        lastTouchTime = DispatchTime.now().uptimeNanoseconds
        touching = max(touching, count)
        lock.unlock()
    }

    nonisolated func source(for event: CGEvent) -> ScrollEventSource {
        lock.lock()
        defer { lock.unlock() }

        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let momentumPhase = NSEvent(cgEvent: event)?.momentumPhase ?? []
        if !continuous {
            lastSource = .mouse
            touching = 0
            return lastSource
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let touchElapsed = now >= lastTouchTime ? now - lastTouchTime : UInt64.max
        let currentTouching = touching
        touching = 0

        if currentTouching >= 2 && touchElapsed < 222_000_000 {
            lastSource = .trackpad
            return lastSource
        }

        if momentumPhase.isEmpty && touchElapsed > 333_000_000 {
            lastSource = .mouse
            return lastSource
        }

        return lastSource
    }
}
