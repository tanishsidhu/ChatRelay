import Foundation

public enum ChatCommand: String, Codable, Equatable, Sendable {
    case handoff = "/handoff"
    case resume = "/resume"

    public static func parse(_ text: String) -> ChatCommand? {
        ChatCommand(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
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
