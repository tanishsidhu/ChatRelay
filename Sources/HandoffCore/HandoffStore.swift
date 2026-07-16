import Darwin
import Foundation

public struct HandoffStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        ChatRelayConfiguration.load().handoffFileURL
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public func save(content rawContent: String, source: ChatProvider, handoffID: UUID = UUID(), date: Date = Date()) throws {
        let content = try HandoffParser.validateContent(rawContent)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let document = """
        ---
        schema_version: \(HandoffProtocol.schemaVersion)
        handoff_id: \(handoffID.uuidString)
        source: \(source.rawValue)
        saved_at: \(formatter.string(from: date))
        ---
        \(content)

        """

        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory()
        let temporaryURL = directory.appendingPathComponent(".CURRENT_HANDOFF.\(UUID().uuidString).tmp")

        do {
            try Data(document.utf8).write(to: temporaryURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )

            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    public func load() throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard let document = String(data: data, encoding: .utf8) else {
            throw HandoffValidationError.invalidStoredDocument
        }
        return try HandoffParser.validateStoredDocument(document)
    }
}
