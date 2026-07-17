import AppKit
import Foundation

public final class ResponseScanner: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<String, Error>) -> Void

    private let queue = DispatchQueue(label: "io.chatrelay.ChatRelay.response-scanner")
    private var timer: DispatchSourceTimer?
    private var deadline: Date?
    private var lastError: Error?
    private var stableCandidate: String?
    private var stableHits = 0
    private var pollCount = 0
    private let lock = NSLock()
    /// About 3 seconds of unchanged successful extracts at the 0.75s poll interval.
    private let requiredStableHits = 4
    /// Minimum hits before a timeout may still save the best complete extract.
    private let minimumTimeoutHits = 2

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
            pollCount = 0
        }

        timer.schedule(deadline: .now() + 0.5, repeating: 0.75, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let deadline = lock.withLock({ self.deadline }), Date() >= deadline {
                let (candidate, hits, storedError) = lock.withLock {
                    (stableCandidate, stableHits, lastError)
                }
                if let candidate, hits >= minimumTimeoutHits {
                    finish(.success(candidate), completion: completion)
                } else {
                    finish(
                        .failure(storedError ?? HandoffValidationError.missingMarkers),
                        completion: completion
                    )
                }
                return
            }

            let poll = lock.withLock { () -> Int in
                pollCount += 1
                return pollCount
            }

            // Chromium-based chat apps often expose an empty Accessibility tree while
            // backgrounded. Periodically raise the target so nested content stays readable.
            if poll == 1 || poll % 8 == 0 {
                Self.ensureTargetReadable(target)
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
                    if let stableCandidate {
                        if content.utf8.count > stableCandidate.utf8.count {
                            // Prefer longer complete extracts as nested details appear.
                            self.stableCandidate = content
                            stableHits = 1
                            return false
                        }
                        if content.utf8.count < stableCandidate.utf8.count {
                            // Ignore transient shrinks from virtualization or flaky AX reads.
                            return false
                        }
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
                // Keep the best complete candidate across transient incomplete snapshots.
                lock.withLock {
                    lastError = error
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
            pollCount = 0
            return current
        }
        existing?.cancel()
    }

    private func finish(_ result: Result<String, Error>, completion: @escaping Completion) {
        cancel()
        completion(result)
    }

    private static func ensureTargetReadable(_ target: ChatTarget) {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              !application.isTerminated
        else {
            return
        }
        AccessibilityBridge.activateEnhancedAccessibility(processIdentifier: target.processIdentifier)
        if !application.isActive {
            application.activate()
            usleep(150_000)
        }
    }
}
