import AppKit
import Foundation
import HandoffCore

private struct Arguments {
    let probe: Bool
    let recover: Bool
    let promptForPermission: Bool
    let outputURL: URL
    let provider: ChatProvider?

    init(_ values: [String]) {
        probe = values.contains("--probe")
        recover = values.contains("--recover")
        promptForPermission = values.contains("--prompt-for-permission")

        if let index = values.firstIndex(of: "--provider"), values.indices.contains(index + 1) {
            provider = ChatProvider(rawValue: values[index + 1])
        } else {
            provider = nil
        }

        if let index = values.firstIndex(of: "--output"), values.indices.contains(index + 1) {
            outputURL = URL(fileURLWithPath: values[index + 1])
        } else {
            outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("chatrelay-accessibility-probe.json")
        }
    }
}

private let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

if arguments.recover {
    guard AccessibilityProbe.isTrusted(prompt: false),
          let provider = arguments.provider,
          let application = NSWorkspace.shared.runningApplications.first(where: {
              ChatProvider.matching(bundleIdentifier: $0.bundleIdentifier) == provider
          }),
          let target = AccessibilityBridge.target(for: application)
    else {
        exit(2)
    }

    do {
        let windowText = AccessibilityBridge.collectWindowText(
            processIdentifier: target.processIdentifier
        )
        let content = try HandoffParser.extractLatest(from: windowText)
        try HandoffStore().save(content: content, source: provider)
        exit(EXIT_SUCCESS)
    } catch {
        exit(EXIT_FAILURE)
    }
}

guard arguments.probe else {
    let application = NSApplication.shared
    let delegate = BackgroundApp()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
    exit(EXIT_SUCCESS)
}

let report = AccessibilityProbe.run(
    promptForPermission: arguments.promptForPermission,
    targetProvider: arguments.provider
)

do {
    try AccessibilityProbe.write(report, to: arguments.outputURL)
    exit(report.accessibilityTrusted ? EXIT_SUCCESS : 2)
} catch {
    exit(EXIT_FAILURE)
}
