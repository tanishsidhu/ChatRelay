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
        guard let focused = focusedElement(processIdentifier: processIdentifier) else {
            return nil
        }

        if isEditableTextElement(focused) {
            return focused
        }

        var queue = [focused]
        var index = 0
        while index < queue.count, index < 250 {
            let element = queue[index]
            index += 1
            if isEditableTextElement(element), boolAttribute(element, kAXFocusedAttribute) == true {
                return element
            }
            if let children = elementsAttribute(element, kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    public static func fieldValue(processIdentifier: Int32) -> String? {
        guard let focused = focusedComposer(processIdentifier: processIdentifier) else {
            return nil
        }
        return textAttribute(focused, kAXValueAttribute)
    }

    public static func collectWindowText(processIdentifier: Int32, maximumElements: Int = 10_000) -> String {
        activateEnhancedAccessibility(processIdentifier: processIdentifier)
        let application = AXUIElementCreateApplication(processIdentifier)
        let root = elementAttribute(application, kAXFocusedWindowAttribute) ?? application
        var queue = [root]
        var index = 0
        var strings: [String] = []
        var byteCount = 0
        let maximumCollectedBytes = 4 * 1_024 * 1_024

        while index < queue.count, index < maximumElements, byteCount < maximumCollectedBytes {
            let element = queue[index]
            index += 1

            for attribute in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
                if let value = stringAttribute(element, attribute), !value.isEmpty {
                    strings.append(value)
                    byteCount += value.lengthOfBytes(using: .utf8)
                }
            }

            if let children = elementsAttribute(element, kAXChildrenAttribute) {
                queue.append(contentsOf: children)
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
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func textAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
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
