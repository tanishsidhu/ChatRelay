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
        // Percent markers avoid ChatGPT Accessibility splitting angle-bracket tokens
        // into separate HTML-like nodes.
        begin = "%%AI_HANDOFF_V1_\(nonce)_BEGIN%%"
        end = "%%AI_HANDOFF_V1_\(nonce)_END%%"
    }
}

public enum HandoffValidationError: LocalizedError, Equatable {
    case missingMarkers
    case emptyContent
    case missingHeading(String)
    case incompleteSectionDetail(String)
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
        case let .incompleteSectionDetail(line):
            "The generated handoff introduces details without listing them: \(line)"
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
        let normalized = normalizeProviderRenderedMarkers(in: text)
        guard let beginRange = normalized.range(of: markers.begin, options: .backwards),
              let endRange = normalized.range(
                of: markers.end,
                options: [],
                range: beginRange.upperBound..<normalized.endIndex
              )
        else {
            throw HandoffValidationError.missingMarkers
        }

        let content = String(normalized[beginRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try validateContent(content)
    }

    public static func extractLatest(from text: String) throws -> String {
        let normalized = normalizeProviderRenderedMarkers(in: text)
        let pattern = #"%%AI_HANDOFF_V1_([A-Za-z0-9]+)_BEGIN%%|<<<AI_HANDOFF_V1_([A-Za-z0-9]+)_BEGIN>>>"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = expression.matches(in: normalized, range: range).last else {
            throw HandoffValidationError.missingMarkers
        }

        let nonceRange: Range<String.Index>
        if match.numberOfRanges > 1,
           let first = Range(match.range(at: 1), in: normalized),
           match.range(at: 1).location != NSNotFound
        {
            nonceRange = first
        } else if match.numberOfRanges > 2,
                  let second = Range(match.range(at: 2), in: normalized),
                  match.range(at: 2).location != NSNotFound
        {
            nonceRange = second
        } else {
            throw HandoffValidationError.missingMarkers
        }

        return try extract(
            from: normalized,
            markers: HandoffMarkers(nonce: String(normalized[nonceRange]))
        )
    }

    /// Rebuild provider-fragmented markers into the literal begin/end tokens.
    /// Supports percent markers and legacy angle-bracket markers from older chats.
    public static func normalizeProviderRenderedMarkers(in text: String) -> String {
        var result = text

        let percentPattern = #"%\s*%\s*(AI_HANDOFF_V1_[A-Za-z0-9]+_(?:BEGIN|END))\s*%\s*%"#
        if let expression = try? NSRegularExpression(pattern: percentPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "%%$1%%"
            )
        }

        let anglePattern = #"<<\s*<\s*(AI_HANDOFF_V1_[A-Za-z0-9]+_(?:BEGIN|END))\s*>\s*>>"#
        if let expression = try? NSRegularExpression(pattern: anglePattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            // Convert legacy fragments into the current percent marker form.
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "%%$1%%"
            )
        }

        let intactAnglePattern = #"<<<(AI_HANDOFF_V1_[A-Za-z0-9]+_(?:BEGIN|END))>>>"#
        if let expression = try? NSRegularExpression(pattern: intactAnglePattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "%%$1%%"
            )
        }

        return result
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

        if let incomplete = firstIncompleteDetailIntroduction(in: content) {
            throw HandoffValidationError.incompleteSectionDetail(incomplete)
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

    /// Detects Accessibility-truncated sections such as "based on these points:" with no
    /// following detail lines before the next heading.
    public static func firstIncompleteDetailIntroduction(in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            defer { index += 1 }
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  trimmed.hasSuffix(":"),
                  trimmed.count >= 12
            else {
                continue
            }

            var cursor = index + 1
            while cursor < lines.count,
                  lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                cursor += 1
            }

            let next = cursor < lines.count
                ? lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let nextIsHeading = next.hasPrefix("#")
            let nextIsAnotherIntro = next.hasSuffix(":") && !next.hasPrefix("#") && !next.hasPrefix("-")
            let missingDetails = next.isEmpty || nextIsHeading || nextIsAnotherIntro
            if missingDetails {
                return trimmed
            }
        }
        return nil
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
