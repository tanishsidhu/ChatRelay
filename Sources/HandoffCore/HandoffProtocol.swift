import Foundation

public enum HandoffProtocol {
    public static let schemaVersion = 1
    public static let maximumWords = 1_500
    public static let maximumBytes = 32 * 1_024

    public static let requiredHeadings = [
        "# Conversation Handoff",
        "## Topic",
        "## User Goal",
        "## Essential Context",
        "## Decisions and Reasoning",
        "## Preferences and Constraints",
        "## Important Facts or Examples",
        "## Open Questions",
        "## Recommended Continuation",
    ]
}

public struct HandoffMarkers: Equatable, Sendable {
    public let nonce: String
    public let begin: String
    public let end: String

    public init(nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")) {
        self.nonce = nonce
        begin = "<<<AI_HANDOFF_V1_\(nonce)_BEGIN>>>"
        end = "<<<AI_HANDOFF_V1_\(nonce)_END>>>"
    }
}

public enum HandoffValidationError: LocalizedError, Equatable {
    case missingMarkers
    case emptyContent
    case missingHeading(String)
    case tooManyWords(Int)
    case tooManyBytes(Int)
    case invalidStoredDocument

    public var errorDescription: String? {
        switch self {
        case .missingMarkers:
            "The model response did not contain the complete handoff markers."
        case .emptyContent:
            "The generated handoff was empty."
        case let .missingHeading(heading):
            "The generated handoff is missing \(heading)."
        case let .tooManyWords(count):
            "The generated handoff has \(count) words, above the 1,500 word limit."
        case let .tooManyBytes(count):
            "The generated handoff has \(count) bytes, above the 32 KB limit."
        case .invalidStoredDocument:
            "The current handoff file is not a valid schema version 1 document."
        }
    }
}

public enum HandoffParser {
    public static func extract(from text: String, markers: HandoffMarkers) throws -> String {
        guard let beginRange = text.range(of: markers.begin, options: .backwards),
              let endRange = text.range(
                of: markers.end,
                options: [],
                range: beginRange.upperBound..<text.endIndex
              )
        else {
            throw HandoffValidationError.missingMarkers
        }

        let content = String(text[beginRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try validateContent(content)
    }

    public static func extractLatest(from text: String) throws -> String {
        let pattern = #"<<<AI_HANDOFF_V1_([A-Za-z0-9]+)_BEGIN>>>"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.matches(in: text, range: range).last,
              match.numberOfRanges == 2,
              let nonceRange = Range(match.range(at: 1), in: text)
        else {
            throw HandoffValidationError.missingMarkers
        }
        return try extract(from: text, markers: HandoffMarkers(nonce: String(text[nonceRange])))
    }

    public static func validateContent(_ rawContent: String) throws -> String {
        let content = restoreRenderedHeadings(in: rawContent)
            .replacingOccurrences(of: "—", with: " - ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw HandoffValidationError.emptyContent
        }

        for heading in HandoffProtocol.requiredHeadings where !content.contains(heading) {
            throw HandoffValidationError.missingHeading(heading)
        }

        let wordCount = content.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount <= HandoffProtocol.maximumWords else {
            throw HandoffValidationError.tooManyWords(wordCount)
        }

        let byteCount = content.lengthOfBytes(using: .utf8)
        guard byteCount <= HandoffProtocol.maximumBytes else {
            throw HandoffValidationError.tooManyBytes(byteCount)
        }

        return content
    }

    private static func restoreRenderedHeadings(in rawContent: String) -> String {
        var lines = rawContent.components(separatedBy: .newlines)
        for heading in HandoffProtocol.requiredHeadings where !rawContent.contains(heading) {
            let plainHeading = heading.drop(while: { $0 == "#" || $0 == " " })
            if let index = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == plainHeading
            }) {
                lines[index] = heading
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func validateStoredDocument(_ document: String) throws -> String {
        guard document.hasPrefix("---\n"),
              document.contains("schema_version: \(HandoffProtocol.schemaVersion)"),
              let closingRange = document.range(of: "\n---\n", range: document.index(document.startIndex, offsetBy: 4)..<document.endIndex)
        else {
            throw HandoffValidationError.invalidStoredDocument
        }

        let content = String(document[closingRange.upperBound...])
        _ = try validateContent(content)
        guard document.lengthOfBytes(using: .utf8) <= HandoffProtocol.maximumBytes + 2_048 else {
            throw HandoffValidationError.tooManyBytes(document.lengthOfBytes(using: .utf8))
        }
        return document
    }
}
