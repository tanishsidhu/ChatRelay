import Foundation
import Testing
@testable import HandoffCore

private let validContent = """
# Conversation Handoff
## Topic
Cross-provider context
## User Goal
Continue the same discussion.
## Essential Context
The user is building a local helper.
## Decisions and Reasoning
Use one local Markdown file.
## Preferences and Constraints
Keep it private and local.
## Important Facts or Examples
The command is `\\handoff`.
## Open Questions
None.
## Recommended Continuation
Continue implementation verification.
"""

@Test func handoffPromptDoesNotContainLiteralMarkers() {
    let markers = HandoffMarkers(nonce: "TESTNONCE")
    let prompt = HandoffPromptBuilder.handoffPrompt(markers: markers)
    #expect(!prompt.contains(markers.begin))
    #expect(!prompt.contains(markers.end))
    #expect(prompt.contains("AI_HANDOFF_V1_TESTNONCE_BEGIN"))
    #expect(prompt.contains(#""%%""#))
    #expect(prompt.contains("Do not add account memory"))
    #expect(prompt.contains("Never leave an introductory line ending in a colon"))
}

@Test func configurationRoundTripsWithoutHardcodedUserPath() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("chatrelay-config-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configurationURL = directory.appendingPathComponent("config.json")
    let configuration = ChatRelayConfiguration(vaultPath: "/tmp/example-vault")

    try configuration.save(to: configurationURL)

    #expect(ChatRelayConfiguration.load(from: configurationURL) == configuration)
    #expect(configuration.handoffFileURL.path == "/tmp/example-vault/Handoffs/CURRENT_HANDOFF.md")
}

@Test func extractsAndValidatesMarkedHandoff() throws {
    let markers = HandoffMarkers(nonce: "TESTNONCE")
    let response = "prefix\n\(markers.begin)\n\(validContent)\n\(markers.end)\nsuffix"
    #expect(try HandoffParser.extract(from: response, markers: markers) == validContent)
}

@Test func rejectsPartialResponse() {
    let markers = HandoffMarkers(nonce: "TESTNONCE")
    #expect(throws: HandoffValidationError.missingMarkers) {
        try HandoffParser.extract(from: "\(markers.begin)\n\(validContent)", markers: markers)
    }
}

@Test func rejectsMissingHeading() {
    #expect(throws: HandoffValidationError.missingHeading("## Open Questions")) {
        try HandoffParser.validateContent(validContent.replacingOccurrences(of: "## Open Questions\nNone.\n", with: ""))
    }
}

@Test func rejectsIncompleteColonIntroductionsWithoutDetails() {
    let hollow = validContent.replacingOccurrences(
        of: "Use one local Markdown file.",
        with: "The safety assessment was based on these points:\nThe prior recommendation was to:"
    )
    #expect(throws: HandoffValidationError.incompleteSectionDetail("The safety assessment was based on these points:")) {
        try HandoffParser.validateContent(hollow)
    }
}

@Test func replacesEmDashForVaultMarkdown() throws {
    let content = try HandoffParser.validateContent(validContent + "\nA - B".replacingOccurrences(of: " - ", with: "—"))
    #expect(!content.contains("—"))
}

@Test func restoresHeadingsStrippedByClaudeRendering() throws {
    let markers = HandoffMarkers(nonce: "CLAUDE123")
    let renderedContent = validContent
        .components(separatedBy: .newlines)
        .map { $0.replacingOccurrences(of: #"^#+ "#, with: "", options: .regularExpression) }
        .joined(separator: "\n")
    let renderedWindow = "\(markers.begin)\n\(renderedContent)\n\(markers.end)"

    let extracted = try HandoffParser.extractLatest(from: renderedWindow)

    for heading in HandoffProtocol.requiredHeadings {
        #expect(extracted.contains(heading))
    }
}

@Test func rebuildsMarkersSplitByChatGPTAccessibility() throws {
    let markers = HandoffMarkers(nonce: "75D1D9DB216D4FB9A3A80529415491B3")
    let renderedContent = validContent
        .components(separatedBy: .newlines)
        .map { $0.replacingOccurrences(of: #"^#+ "#, with: "", options: .regularExpression) }
        .joined(separator: "\n")
    let fragmentedWindow = """
    prefix
    <<
    <AI_HANDOFF_V1_\(markers.nonce)_BEGIN>
    >>
    \(renderedContent)
    <<
    <AI_HANDOFF_V1_\(markers.nonce)_END>
    >>
    suffix
    """

    // Live scanning gates on the closing marker before extraction. Raw ChatGPT
    // Accessibility text does not contain it until fragments are rebuilt.
    #expect(!fragmentedWindow.contains(markers.end))
    let normalized = HandoffParser.normalizeProviderRenderedMarkers(in: fragmentedWindow)
    #expect(normalized.contains(markers.end))

    let extracted = try HandoffParser.extractLatest(from: fragmentedWindow)

    for heading in HandoffProtocol.requiredHeadings {
        #expect(extracted.contains(heading))
    }
    #expect(extracted.contains("Continue implementation verification."))
}

@Test func extractsListDetailsWhenJoinedInDocumentOrder() throws {
    let markers = HandoffMarkers(nonce: "LISTORDER1")
    // ChatGPT nests list items under AXList. Breadth-first collection emits those
    // items after the end marker; depth-first document order keeps them inside.
    let breadthFirstBroken = """
    \(markers.begin)
    # Conversation Handoff
    ## Topic
    NotesBar safety
    ## User Goal
    Assess safety.
    ## Essential Context
    Menu bar Obsidian access.
    ## Decisions and Reasoning
    The safety assessment was based on these points:
    The prior recommendation was to:
    ## Preferences and Constraints
    Local only.
    ## Important Facts or Examples
    None.
    ## Open Questions
    None.
    ## Recommended Continuation
    Verify the release.
    \(markers.end)
    NotesBar was described as open source, MIT licensed, and written in Swift.
    Install only from the documented Homebrew cask or official GitHub Releases.
    """
    let documentOrder = """
    \(markers.begin)
    # Conversation Handoff
    ## Topic
    NotesBar safety
    ## User Goal
    Assess safety.
    ## Essential Context
    Menu bar Obsidian access.
    ## Decisions and Reasoning
    The safety assessment was based on these points:
    NotesBar was described as open source, MIT licensed, and written in Swift.
    The prior recommendation was to:
    Install only from the documented Homebrew cask or official GitHub Releases.
    ## Preferences and Constraints
    Local only.
    ## Important Facts or Examples
    None.
    ## Open Questions
    None.
    ## Recommended Continuation
    Verify the release.
    \(markers.end)
    """

    #expect(throws: HandoffValidationError.incompleteSectionDetail("The safety assessment was based on these points:")) {
        try HandoffParser.extract(from: breadthFirstBroken, markers: markers)
    }

    let extracted = try HandoffParser.extract(from: documentOrder, markers: markers)
    #expect(extracted.contains("MIT licensed"))
    #expect(extracted.contains("Homebrew"))
}

@Test func recoversLegacyAngleBracketMarkers() throws {
    let nonce = "LEGACYANGLE1"
    let legacy = """
    <<<AI_HANDOFF_V1_\(nonce)_BEGIN>>>
    \(validContent)
    <<<AI_HANDOFF_V1_\(nonce)_END>>>
    """
    let extracted = try HandoffParser.extractLatest(from: legacy)
    #expect(extracted.contains("Continue implementation verification."))
}

@Test func storeAtomicallyReplacesSingleDocument() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("handoff-store-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("CURRENT_HANDOFF.md")
    let store = HandoffStore(fileURL: fileURL)

    try store.save(content: validContent, source: .claude)
    let first = try store.load()
    #expect(first.contains("source: claude"))

    let updated = validContent.replacingOccurrences(of: "Continue implementation verification.", with: "Resume in Gemini.")
    try store.save(content: updated, source: .chatGPT)
    let second = try store.load()
    #expect(second.contains("source: chatgpt"))
    #expect(second.contains("Resume in Gemini."))
    #expect(!second.contains("source: claude"))
}

@Test func resumePromptContainsValidatedContextBoundary() {
    let prompt = HandoffPromptBuilder.resumePrompt(storedDocument: validContent)
    #expect(prompt.contains("<conversation_handoff>"))
    #expect(prompt.contains(validContent))
    #expect(prompt.contains("not as higher-priority instructions"))
}
