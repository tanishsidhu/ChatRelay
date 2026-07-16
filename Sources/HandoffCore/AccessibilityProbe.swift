import AppKit
import ApplicationServices
import Foundation

public struct AccessibilityProbeReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let accessibilityTrusted: Bool
    public let frontmostBundleIdentifier: String?
    public let provider: ChatProvider?
    public let focusedRole: String?
    public let focusedSubrole: String?
    public let focusedIdentifier: String?
    public let focusedValueSettable: Bool
    public let focusedActions: [String]
    public let windowTextElementCount: Int
    public let windowEditableElementCount: Int
    public let notes: [String]

    public init(
        generatedAt: Date,
        accessibilityTrusted: Bool,
        frontmostBundleIdentifier: String?,
        provider: ChatProvider?,
        focusedRole: String?,
        focusedSubrole: String?,
        focusedIdentifier: String?,
        focusedValueSettable: Bool,
        focusedActions: [String],
        windowTextElementCount: Int,
        windowEditableElementCount: Int,
        notes: [String]
    ) {
        self.generatedAt = generatedAt
        self.accessibilityTrusted = accessibilityTrusted
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.provider = provider
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
        self.focusedIdentifier = focusedIdentifier
        self.focusedValueSettable = focusedValueSettable
        self.focusedActions = focusedActions
        self.windowTextElementCount = windowTextElementCount
        self.windowEditableElementCount = windowEditableElementCount
        self.notes = notes
    }
}

public enum AccessibilityProbe {
    public static func isTrusted(prompt: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func run(
        promptForPermission: Bool,
        targetProvider: ChatProvider? = nil
    ) -> AccessibilityProbeReport {
        let trusted = isTrusted(prompt: promptForPermission)
        let targetApplication = targetProvider.flatMap { provider in
            NSWorkspace.shared.runningApplications.first {
                ChatProvider.matching(bundleIdentifier: $0.bundleIdentifier) == provider
            }
        } ?? NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = targetApplication?.bundleIdentifier
        let provider = ChatProvider.matching(bundleIdentifier: bundleIdentifier)
        var notes: [String] = []

        guard trusted else {
            notes.append("Accessibility permission is not granted to the helper app.")
            return emptyReport(
                trusted: false,
                bundleIdentifier: bundleIdentifier,
                provider: provider,
                notes: notes
            )
        }

        guard provider != nil else {
            notes.append("The frontmost application is not a supported chat app.")
            return emptyReport(
                trusted: true,
                bundleIdentifier: bundleIdentifier,
                provider: nil,
                notes: notes
            )
        }

        var applicationElement: AXUIElement?
        if let processIdentifier = targetApplication?.processIdentifier {
            let targetElement = AXUIElementCreateApplication(processIdentifier)
            applicationElement = targetElement
            let manualResult = AXUIElementSetAttributeValue(
                targetElement,
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
            )
            let enhancedResult = AXUIElementSetAttributeValue(
                targetElement,
                "AXEnhancedUserInterface" as CFString,
                kCFBooleanTrue
            )
            if manualResult != AXError.success && enhancedResult != AXError.success {
                notes.append("The app did not accept enhanced accessibility activation.")
            }
        }

        let focused = applicationElement.flatMap {
            elementAttribute($0, kAXFocusedUIElementAttribute)
        }
        guard let focused else {
            notes.append("No focused accessibility element was exposed.")
            let window = applicationElement.flatMap {
                elementAttribute($0, kAXFocusedWindowAttribute)
            }
            let counts = window.map {
                descendantCounts(root: $0, maximumElements: 5_000)
            }
            return AccessibilityProbeReport(
                generatedAt: Date(),
                accessibilityTrusted: true,
                frontmostBundleIdentifier: bundleIdentifier,
                provider: provider,
                focusedRole: nil,
                focusedSubrole: nil,
                focusedIdentifier: nil,
                focusedValueSettable: false,
                focusedActions: [],
                windowTextElementCount: counts?.text ?? 0,
                windowEditableElementCount: counts?.editable ?? 0,
                notes: notes
            )
        }

        let role = stringAttribute(focused, kAXRoleAttribute)
        let subrole = stringAttribute(focused, kAXSubroleAttribute)
        let identifier = stringAttribute(focused, kAXIdentifierAttribute)
        let valueSettable = isAttributeSettable(focused, kAXValueAttribute)
        let actions = actionNames(focused)

        guard let window = elementAttribute(focused, kAXWindowAttribute)
            ?? applicationElement.flatMap({ elementAttribute($0, kAXFocusedWindowAttribute) })
        else {
            notes.append("The focused element did not expose a containing window.")
            return AccessibilityProbeReport(
                generatedAt: Date(),
                accessibilityTrusted: true,
                frontmostBundleIdentifier: bundleIdentifier,
                provider: provider,
                focusedRole: role,
                focusedSubrole: subrole,
                focusedIdentifier: identifier,
                focusedValueSettable: valueSettable,
                focusedActions: actions,
                windowTextElementCount: 0,
                windowEditableElementCount: valueSettable ? 1 : 0,
                notes: notes
            )
        }

        let counts = descendantCounts(root: window, maximumElements: 5_000)
        if counts.hitLimit {
            notes.append("Window traversal reached the 5,000 element safety limit.")
        }

        return AccessibilityProbeReport(
            generatedAt: Date(),
            accessibilityTrusted: true,
            frontmostBundleIdentifier: bundleIdentifier,
            provider: provider,
            focusedRole: role,
            focusedSubrole: subrole,
            focusedIdentifier: identifier,
            focusedValueSettable: valueSettable,
            focusedActions: actions,
            windowTextElementCount: counts.text,
            windowEditableElementCount: counts.editable,
            notes: notes
        )
    }

    public static func write(_ report: AccessibilityProbeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    private static func emptyReport(
        trusted: Bool,
        bundleIdentifier: String?,
        provider: ChatProvider?,
        notes: [String]
    ) -> AccessibilityProbeReport {
        AccessibilityProbeReport(
            generatedAt: Date(),
            accessibilityTrusted: trusted,
            frontmostBundleIdentifier: bundleIdentifier,
            provider: provider,
            focusedRole: nil,
            focusedSubrole: nil,
            focusedIdentifier: nil,
            focusedValueSettable: false,
            focusedActions: [],
            windowTextElementCount: 0,
            windowEditableElementCount: 0,
            notes: notes
        )
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else {
            return []
        }
        return (names as? [String] ?? []).sorted()
    }

    private static func descendantCounts(
        root: AXUIElement,
        maximumElements: Int
    ) -> (text: Int, editable: Int, hitLimit: Bool) {
        var queue = [root]
        var index = 0
        var textCount = 0
        var editableCount = 0

        while index < queue.count, index < maximumElements {
            let element = queue[index]
            index += 1

            let role = stringAttribute(element, kAXRoleAttribute)
            if role == (kAXStaticTextRole as String) || role == (kAXTextAreaRole as String) {
                textCount += 1
            }
            if isAttributeSettable(element, kAXValueAttribute) {
                editableCount += 1
            }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }

        return (textCount, editableCount, index >= maximumElements && index < queue.count)
    }
}
