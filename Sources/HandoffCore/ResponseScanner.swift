import Foundation

public final class ResponseScanner: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<String, Error>) -> Void

    private let queue = DispatchQueue(label: "io.chatrelay.ChatRelay.response-scanner")
    private var timer: DispatchSourceTimer?
    private var deadline: Date?
    private var lastError: Error?
    private var stableCandidate: String?
    private var stableHits = 0
    private let lock = NSLock()
    /// About 3 seconds of unchanged successful extracts at the 0.75s poll interval.
    private let requiredStableHits = 4

    public init() {}

    public func start(
        target: ChatTarget,
        markers: HandoffMarkers,
        timeout: TimeInterval = 300,
        completion: @escaping Completion
    ) {
        cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        lock.withLock {
            self.timer = timer
            deadline = Date().addingTimeInterval(timeout)
            lastError = nil
            stableCandidate = nil
            stableHits = 0
        }

        timer.schedule(deadline: .now() + 0.5, repeating: 0.75, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let deadline = lock.withLock({ self.deadline }), Date() >= deadline {
                let storedError = lock.withLock { () -> Error? in lastError }
                finish(
                    .failure(storedError ?? HandoffValidationError.missingMarkers),
                    completion: completion
                )
                return
            }

            let text = HandoffParser.normalizeProviderRenderedMarkers(
                in: AccessibilityBridge.collectWindowText(
                    processIdentifier: target.processIdentifier
                )
            )
            guard text.contains(markers.end) else { return }

            do {
                let content = try HandoffParser.extract(from: text, markers: markers)
                let shouldFinish = lock.withLock { () -> Bool in
                    lastError = nil
                    if let stableCandidate, content.utf8.count > stableCandidate.utf8.count {
                        // Accessibility often reveals nested list details after the first
                        // structurally valid snapshot. Prefer the longer complete extract.
                        self.stableCandidate = content
                        stableHits = 1
                        return false
                    }
                    if stableCandidate == content {
                        stableHits += 1
                    } else {
                        stableCandidate = content
                        stableHits = 1
                    }
                    return stableHits >= requiredStableHits
                }
                if shouldFinish {
                    finish(.success(content), completion: completion)
                }
            } catch {
                // Keep polling through partial Accessibility snapshots until timeout.
                lock.withLock {
                    lastError = error
                    stableCandidate = nil
                    stableHits = 0
                }
            }
        }
        timer.resume()
    }

    public func cancel() {
        let existing = lock.withLock { () -> DispatchSourceTimer? in
            let current = timer
            timer = nil
            deadline = nil
            lastError = nil
            stableCandidate = nil
            stableHits = 0
            return current
        }
        existing?.cancel()
    }

    private func finish(_ result: Result<String, Error>, completion: @escaping Completion) {
        cancel()
        completion(result)
    }
}
