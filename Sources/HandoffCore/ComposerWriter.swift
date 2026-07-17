import AppKit
import CoreGraphics
import Darwin
import Foundation

public enum ComposerWriteError: LocalizedError, Equatable {
    case targetUnavailable
    case composerUnavailable
    case clipboardUnavailable
    case pasteDidNotLand
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The target chat app is no longer running."
        case .composerUnavailable:
            "The target chat composer is no longer focused."
        case .clipboardUnavailable:
            "The helper could not prepare the local clipboard."
        case .pasteDidNotLand:
            "The helper pasted into the composer, but the text did not appear before submit."
        case .eventCreationFailed:
            "The helper could not create a keyboard event."
        }
    }
}

public enum ComposerWriter {
    public static let syntheticEventTag: Int64 = 0x48414E444F4646
    private static let writerLock = NSLock()

    public static func replaceAndSubmit(_ text: String, target: ChatTarget) throws {
        try writerLock.withLock {
            try replaceAndSubmitLocked(text, target: target)
        }
    }

    private static func replaceAndSubmitLocked(_ text: String, target: ChatTarget) throws {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              !application.isTerminated
        else {
            throw ComposerWriteError.targetUnavailable
        }

        application.activate()
        usleep(150_000)

        guard AccessibilityBridge.focusedComposer(processIdentifier: target.processIdentifier) != nil else {
            throw ComposerWriteError.composerUnavailable
        }

        let snapshot = Clipboard.snapshot()
        defer { Clipboard.restore(snapshot) }
        try Clipboard.setString(text)

        try postKey(keyCode: 0, flags: .maskCommand, processIdentifier: target.processIdentifier)
        usleep(80_000)
        try postKey(keyCode: 9, flags: .maskCommand, processIdentifier: target.processIdentifier)

        // Large pastes can land slowly or become attachments. Confirm inline text first.
        var landed = false
        for _ in 0..<12 {
            usleep(100_000)
            if let value = AccessibilityBridge.fieldValue(processIdentifier: target.processIdentifier),
               pasteAppearsLanded(expected: text, actual: value)
            {
                landed = true
                break
            }
        }
        guard landed else {
            throw ComposerWriteError.pasteDidNotLand
        }

        try postKey(
            keyCode: 36,
            flags: [],
            processIdentifier: target.processIdentifier,
            syntheticTag: syntheticEventTag
        )
    }

    private static func pasteAppearsLanded(expected: String, actual: String) -> Bool {
        let trimmedActual = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedActual.count >= min(64, expected.count / 4) else {
            return false
        }
        if expected.count <= 200 {
            return trimmedActual.contains(expected.prefix(40)) || expected.contains(trimmedActual.prefix(40))
        }
        let needle = String(expected.prefix(80))
        let mid = expected.index(expected.startIndex, offsetBy: expected.count / 3)
        let midNeedle = String(expected[mid...].prefix(80))
        return trimmedActual.contains(needle) || trimmedActual.contains(midNeedle)
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
