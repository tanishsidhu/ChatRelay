import AppKit
import CoreGraphics
import Darwin
import Foundation

public enum ComposerWriteError: LocalizedError, Equatable {
    case targetUnavailable
    case composerUnavailable
    case clipboardUnavailable
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The target chat app is no longer running."
        case .composerUnavailable:
            "The target chat composer is no longer focused."
        case .clipboardUnavailable:
            "The helper could not prepare the local clipboard."
        case .eventCreationFailed:
            "The helper could not create a keyboard event."
        }
    }
}

public enum ComposerWriter {
    public static let syntheticEventTag: Int64 = 0x48414E444F4646

    public static func replaceAndSubmit(_ text: String, target: ChatTarget) throws {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              !application.isTerminated
        else {
            throw ComposerWriteError.targetUnavailable
        }
        guard AccessibilityBridge.focusedComposer(processIdentifier: target.processIdentifier) != nil else {
            throw ComposerWriteError.composerUnavailable
        }

        application.activate()
        usleep(120_000)

        let snapshot = Clipboard.snapshot()
        defer { Clipboard.restore(snapshot) }
        try Clipboard.setString(text)

        try postKey(keyCode: 0, flags: .maskCommand, processIdentifier: target.processIdentifier)
        usleep(80_000)
        try postKey(keyCode: 9, flags: .maskCommand, processIdentifier: target.processIdentifier)
        usleep(180_000)
        try postKey(
            keyCode: 36,
            flags: [],
            processIdentifier: target.processIdentifier,
            syntheticTag: syntheticEventTag
        )
    }

    private static func postKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        processIdentifier: Int32,
        syntheticTag: Int64? = nil
    ) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw ComposerWriteError.eventCreationFailed
        }

        down.flags = flags
        up.flags = flags
        if let syntheticTag {
            down.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            up.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        }
        down.postToPid(processIdentifier)
        usleep(12_000)
        up.postToPid(processIdentifier)
    }
}
