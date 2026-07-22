import Testing
@testable import HandoffCore

@Test func parsesOnlyExactCommands() {
    #expect(ChatCommand.parse("\\handoff") == .handoff)
    #expect(ChatCommand.parse("  \\resume\n") == .resume)
    #expect(ChatCommand.parse("/handoff") == .handoff)
    #expect(ChatCommand.parse("/resume") == .resume)
    #expect(ChatCommand.parse("\\handoff now") == nil)
    #expect(ChatCommand.parse("hello \\resume") == nil)
    #expect(ChatCommand.parse("\\") == nil)
    #expect(ChatCommand.parse("\n\\handoff") == .handoff)
}
