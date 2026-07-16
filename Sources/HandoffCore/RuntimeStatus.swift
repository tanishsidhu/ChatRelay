import Foundation

public struct RuntimeStatus: Codable, Equatable, Sendable {
    public let processIdentifier: Int32
    public let startedAt: Date
    public let accessibilityTrusted: Bool
    public let eventMonitorActive: Bool
    public let loginItemEnabled: Bool

    public init(
        processIdentifier: Int32,
        startedAt: Date,
        accessibilityTrusted: Bool,
        eventMonitorActive: Bool,
        loginItemEnabled: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.startedAt = startedAt
        self.accessibilityTrusted = accessibilityTrusted
        self.eventMonitorActive = eventMonitorActive
        self.loginItemEnabled = loginItemEnabled
    }

    public static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ChatRelay", isDirectory: true)
        .appendingPathComponent("runtime-status.json")

    public func write(to url: URL = Self.fileURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL = fileURL) -> RuntimeStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RuntimeStatus.self, from: data)
    }
}
