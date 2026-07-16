import Testing
@testable import HandoffCore

@Test func matchesInstalledBundleIdentifiers() {
    #expect(ChatProvider.matching(bundleIdentifier: "com.openai.codex") == .chatGPT)
    #expect(ChatProvider.matching(bundleIdentifier: "com.anthropic.claudefordesktop") == .claude)
    #expect(ChatProvider.matching(bundleIdentifier: "com.google.GeminiMacOS") == .gemini)
}

@Test func rejectsUnrelatedBundleIdentifier() {
    #expect(ChatProvider.matching(bundleIdentifier: "com.apple.Safari") == nil)
}
