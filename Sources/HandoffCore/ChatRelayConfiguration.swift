import Foundation

public struct ChatRelayConfiguration: Codable, Equatable, Sendable {
    public let vaultPath: String

    public init(vaultPath: String) {
        self.vaultPath = vaultPath
    }

    public static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ChatRelay", isDirectory: true)
        .appendingPathComponent("config.json")

    public static var defaultVaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Obsidian/Context", isDirectory: true)
    }

    public var vaultURL: URL {
        URL(fileURLWithPath: vaultPath, isDirectory: true).standardizedFileURL
    }

    public var handoffFileURL: URL {
        vaultURL
            .appendingPathComponent("Handoffs", isDirectory: true)
            .appendingPathComponent("CURRENT_HANDOFF.md")
    }

    public static func load(from url: URL = fileURL) -> ChatRelayConfiguration {
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return Self(vaultPath: defaultVaultURL.path)
        }
        return configuration
    }

    public func save(to url: URL = Self.fileURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
