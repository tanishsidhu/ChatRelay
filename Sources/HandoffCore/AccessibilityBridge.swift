import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityBridge {
    public static func target(for application: NSRunningApplication?) -> ChatTarget? {
        guard let application,
              let bundleIdentifier = application.bundleIdentifier,
              let provider = ChatProvider.matching(bundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        return ChatTarget(
            provider: provider,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: application.localizedName ?? provider.displayName
        )
    }

    public static func frontmostTarget() -> ChatTarget? {
        target(for: NSWorkspace.shared.frontmostApplication)
    }

    public static func activateEnhancedAccessibility(processIdentifier: Int32) {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    public static func focusedElement(processIdentifier: Int32) -> AXUIElement? {
        activateEnhancedAccessibility(processIdentifier: processIdentifier)
        let application = AXUIElementCreateApplication(processIdentifier)
        return elementAttribute(application, kAXFocusedUIElementAttribute)
    }

    public static func focusedComposer(processIdentifier: Int32) -> AXUIElement? {
        if let focused = focusedElement(processIdentifier: processIdentifier) {
            if isEditableTextElement(focused) {
                return focused
            }

            // Prefer an explicitly focused editable descendant first.
            if let focusedEditable = findEditableText(
                root: focused,
                preferFocused: true,
                limit: 2_000
            ) {
                return focusedEditable
            }

            // ChatGPT currently focuses an AXWebArea while the message box is a
            // descendant AXTextArea that does not report AXFocused=true.
            if let descendantComposer = findEditableText(
                root: focused,
                preferFocused: false,
                limit: 2_000
            ) {
                return descendantComposer
            }
        }

        return findComposerInApplication(processIdentifier: processIdentifier)
    }

    public static func fieldValue(processIdentifier: Int32) -> String? {
        guard let focused = focusedComposer(processIdentifier: processIdentifier) else {
            return nil
        }
        return textAttribute(focused, kAXValueAttribute)
    }

    private static func findComposerInApplication(processIdentifier: Int32) -> AXUIElement? {
        activateEnhancedAccessibility(processIdentifier: processIdentifier)
        let application = AXUIElementCreateApplication(processIdentifier)
        let root = elementAttribute(application, kAXFocusedWindowAttribute) ?? application
        return findEditableText(root: root, preferFocused: false, limit: 4_000)
    }

    private static func findEditableText(
        root: AXUIElement,
        preferFocused: Bool,
        limit: Int
    ) -> AXUIElement? {
        var queue = [root]
        var index = 0
        var fallback: AXUIElement?

        while index < queue.count, index < limit {
            let element = queue[index]
            index += 1

            if isEditableTextElement(element) {
                if !preferFocused || boolAttribute(element, kAXFocusedAttribute) == true {
                    return element
                }
                if fallback == nil || looksLikeMessageComposer(element) {
                    fallback = element
                }
            }

            if let children = elementsAttribute(element, kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
        }

        return preferFocused ? nil : fallback
    }

    private static func looksLikeMessageComposer(_ element: AXUIElement) -> Bool {
        let probes = [
            textAttribute(element, kAXValueAttribute),
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXTitleAttribute),
            stringAttribute(element, kAXPlaceholderValueAttribute),
        ]
        .compactMap { $0?.lowercased() }

        return probes.contains { value in
            value.contains("message") || value.contains("ask") || value.contains("chat")
        }
    }

    public static func collectWindowText(processIdentifier: Int32, maximumElements: Int = 10_000) -> String {
        activateEnhancedAccessibility(processIdentifier: processIdentifier)
        let application = AXUIElementCreateApplication(processIdentifier)
        var roots: [AXUIElement] = []
        if let windows = elementsAttribute(application, kAXWindowsAttribute), !windows.isEmpty {
            roots.append(contentsOf: windows)
        } else if let focused = elementAttribute(application, kAXFocusedWindowAttribute) {
            roots.append(focused)
        } else {
            roots.append(application)
        }

        // Depth-first preorder preserves document order. Breadth-first visitation
        // emits nested list items after later sibling markers, which drops ChatGPT
        // bullet content from the marked handoff span.
        var stack = Array(roots.reversed())
        var strings: [String] = []
        var visited = 0
        var byteCount = 0
        let maximumCollectedBytes = 4 * 1_024 * 1_024

        while let element = stack.popLast(),
              visited < maximumElements,
              byteCount < maximumCollectedBytes
        {
            visited += 1

            for attribute in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
                if let value = stringAttribute(element, attribute), !value.isEmpty {
                    // Skip duplicate Accessibility mirrors of the same visible text.
                    if strings.last != value {
                        strings.append(value)
                        byteCount += value.lengthOfBytes(using: .utf8)
                    }
                }
            }

            if let children = elementsAttribute(element, kAXChildrenAttribute), !children.isEmpty {
                stack.append(contentsOf: children.reversed())
            }
        }

        return strings.joined(separator: "\n")
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

    private static func elementsAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private static func textAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        stringAttribute(element, attribute)
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute)
        let acceptedRoles = [kAXTextAreaRole as String, kAXTextFieldRole as String]
        guard acceptedRoles.contains(role ?? "") else { return false }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success else {
            return false
        }
        return settable.boolValue
    }
}
