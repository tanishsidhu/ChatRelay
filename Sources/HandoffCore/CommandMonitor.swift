import AppKit
import CoreGraphics
import Foundation

public final class CommandMonitor: @unchecked Sendable {
    public var onCommand: ((ChatCommand, ChatTarget) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private static weak var active: CommandMonitor?

    public init() {}

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        Self.active = self
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                CommandMonitor.handle(type: type, event: event)
            },
            userInfo: nil
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let monitor = Self.active else {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = monitor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != ComposerWriter.syntheticEventTag
        else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 36 || keyCode == 76 else {
            return Unmanaged.passUnretained(event)
        }

        let blockedModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard event.flags.intersection(blockedModifiers).isEmpty,
              let target = AccessibilityBridge.frontmostTarget(),
              let value = AccessibilityBridge.fieldValue(processIdentifier: target.processIdentifier),
              let command = ChatCommand.parse(value)
        else {
            return Unmanaged.passUnretained(event)
        }

        let callback = monitor.onCommand
        DispatchQueue.main.async {
            callback?(command, target)
        }
        return nil
    }
}
