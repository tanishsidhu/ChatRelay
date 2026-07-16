import AppKit

public enum ChatProvider: String, Codable, CaseIterable, Sendable {
    case chatGPT = "chatgpt"
    case claude
    case gemini

    public var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    public var bundleIdentifiers: Set<String> {
        switch self {
        case .chatGPT:
            // The currently installed ChatGPT build uses com.openai.codex.
            // Keep the conventional identifier as a forward-compatible alias.
            ["com.openai.codex", "com.openai.chat"]
        case .claude:
            ["com.anthropic.claudefordesktop"]
        case .gemini:
            ["com.google.GeminiMacOS"]
        }
    }

    public static func matching(bundleIdentifier: String?) -> ChatProvider? {
        guard let bundleIdentifier else { return nil }
        return allCases.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }
}

public struct InstalledChatApp: Codable, Equatable, Sendable {
    public let provider: ChatProvider
    public let bundleIdentifier: String
    public let path: String
    public let version: String?

    public init(provider: ChatProvider, bundleIdentifier: String, path: String, version: String?) {
        self.provider = provider
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.version = version
    }
}

public enum InstalledAppDiscovery {
    public static func discover(
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> [InstalledChatApp] {
        let names = ["ChatGPT.app", "Claude.app", "Gemini.app"]

        return names.compactMap { name in
            let url = applicationsDirectory.appendingPathComponent(name, isDirectory: true)
            guard let bundle = Bundle(url: url),
                  let identifier = bundle.bundleIdentifier,
                  let provider = ChatProvider.matching(bundleIdentifier: identifier)
            else {
                return nil
            }

            return InstalledChatApp(
                provider: provider,
                bundleIdentifier: identifier,
                path: url.path,
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            )
        }
    }
}
