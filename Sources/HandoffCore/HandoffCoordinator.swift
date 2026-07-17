import Foundation

public final class HandoffCoordinator: @unchecked Sendable {
    public typealias NotificationHandler = @Sendable (_ title: String, _ body: String) -> Void

    private let store: HandoffStore
    private let scanner: ResponseScanner
    private let stateLock = NSLock()
    private var busy = false
    private let notify: NotificationHandler

    public init(
        store: HandoffStore = HandoffStore(),
        scanner: ResponseScanner = ResponseScanner(),
        notify: @escaping NotificationHandler
    ) {
        self.store = store
        self.scanner = scanner
        self.notify = notify
    }

    public func handle(_ command: ChatCommand, target: ChatTarget) {
        switch command {
        case .handoff:
            beginHandoff(target: target)
        case .resume:
            resume(target: target)
        }
    }

    private func beginHandoff(target: ChatTarget) {
        guard stateLock.withLock({
            guard !busy else { return false }
            busy = true
            return true
        }) else {
            notify("Handoff already running", "Wait for the current handoff to finish.")
            return
        }

        let markers = HandoffMarkers()
        let prompt = HandoffPromptBuilder.handoffPrompt(markers: markers)

        do {
            notify(
                "Handoff started",
                "Keep \(target.provider.displayName) visible until ChatRelay saves the context file."
            )
            try ComposerWriter.replaceAndSubmit(prompt, target: target)
        } catch {
            stateLock.withLock { busy = false }
            notify("Handoff failed", error.localizedDescription)
            return
        }

        scanner.start(target: target, markers: markers) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(content):
                do {
                    try store.save(content: content, source: target.provider)
                    notify("Handoff saved", "The current \(target.provider.displayName) conversation is ready to resume.")
                } catch {
                    notify("Handoff not saved", error.localizedDescription)
                }
            case let .failure(error):
                notify("Handoff failed", error.localizedDescription)
            }
            stateLock.withLock { busy = false }
        }
    }

    private func resume(target: ChatTarget) {
        guard stateLock.withLock({
            guard !busy else { return false }
            busy = true
            return true
        }) else {
            notify("ChatRelay busy", "Wait for the current handoff or resume to finish.")
            return
        }
        defer { stateLock.withLock { busy = false } }

        let document: String
        do {
            document = try store.load()
        } catch {
            notify("Resume unavailable", error.localizedDescription)
            return
        }

        let prompt = HandoffPromptBuilder.resumePrompt(storedDocument: document)
        do {
            try ComposerWriter.replaceAndSubmit(prompt, target: target)
            notify("Resume submitted", "The latest handoff was sent to \(target.provider.displayName).")
        } catch {
            notify("Resume failed", error.localizedDescription)
        }
    }
}
