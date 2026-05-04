//
//  ScrollReverser.swift
//  UnNatural
//
//  Created by Tomokazu HIRAI on 2026/05/04.
//

import ApplicationServices
import AppKit
import Combine
import Foundation

private typealias IOHIDEventRef = UnsafeMutableRawPointer
private typealias IOHIDEventField = UInt32
private typealias IOHIDFloat = Double

private let kIOHIDEventTypeScroll: UInt32 = 6
private let kIOHIDEventFieldScrollBase = kIOHIDEventTypeScroll << 16
private let kIOHIDEventFieldScrollX = kIOHIDEventFieldScrollBase | 0
private let kIOHIDEventFieldScrollY = kIOHIDEventFieldScrollBase | 1

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

    private let eventState = ScrollEventState()
    private var activeEventTap: CFMachPort?
    private var activeRunLoopSource: CFRunLoopSource?
    private var passiveEventTap: CFMachPort?
    private var passiveRunLoopSource: CFRunLoopSource?

    init() {
        start()
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        start()
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
    }

    func stop() {
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
        let source = state.source(for: event)
        let shouldReverse: Bool
        switch source {
        case .trackpad:
            shouldReverse = defaults.bool(forKey: "reverseTrackpad")
        case .mouse:
            shouldReverse = defaults.bool(forKey: "reverseMouse")
        }

        if shouldReverse {
            reverseScrollEvent(event)
        }

        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    private nonisolated static func reverseScrollEvent(_ event: CGEvent) -> Bool {
        let values = ScrollEventValues(event: event)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -values.deltaY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -values.deltaX)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -values.fixedDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -values.fixedDeltaX)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -values.pointDeltaY)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -values.pointDeltaX)

        guard let ioHidEvent = CGEventCopyIOHIDEvent(event) else {
            return false
        }

        let y = IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY)
        if y != 0 {
            IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollY, -y)
        }

        let x = IOHIDEventGetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX)
        if x != 0 {
            IOHIDEventSetFloatValue(ioHidEvent, kIOHIDEventFieldScrollX, -x)
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

    nonisolated func reset() {
        lock.lock()
        lastTouchTime = 0
        touching = 0
        lastSource = .mouse
        lock.unlock()
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
