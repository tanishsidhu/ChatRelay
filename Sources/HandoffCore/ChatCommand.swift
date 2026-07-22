import Foundation

public enum ChatCommand: String, Codable, Equatable, Sendable {
    case handoff = "\\handoff"
    case resume = "\\resume"

    public static func parse(_ text: String) -> ChatCommand? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // ChatGPT sometimes keeps a leading newline from the composer placeholder.
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{200B}\u{FEFF}"))
        if let command = ChatCommand(rawValue: normalized) {
            return command
        }
        // Accept the legacy slash form so older muscle memory still works.
        switch normalized {
        case "/handoff":
            return .handoff
        case "/resume":
            return .resume
        default:
            return nil
        }
    }
}

public struct ChatTarget: Codable, Equatable, Sendable {
    public let provider: ChatProvider
    public let processIdentifier: Int32
    public let bundleIdentifier: String
    public let localizedName: String

    public init(
        provider: ChatProvider,
        processIdentifier: Int32,
        bundleIdentifier: String,
        localizedName: String
    ) {
        self.provider = provider
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}
