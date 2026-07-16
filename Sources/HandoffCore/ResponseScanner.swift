import Foundation

public final class ResponseScanner: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<String, Error>) -> Void

    private let queue = DispatchQueue(label: "io.chatrelay.ChatRelay.response-scanner")
    private var timer: DispatchSourceTimer?
    private var deadline: Date?
    private let lock = NSLock()

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
        }

        timer.schedule(deadline: .now() + 0.5, repeating: 0.75, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if let deadline = lock.withLock({ self.deadline }), Date() >= deadline {
                finish(.failure(HandoffValidationError.missingMarkers), completion: completion)
                return
            }

            let text = AccessibilityBridge.collectWindowText(
                processIdentifier: target.processIdentifier
            )
            guard text.contains(markers.end) else { return }

            do {
                let content = try HandoffParser.extract(from: text, markers: markers)
                finish(.success(content), completion: completion)
            } catch HandoffValidationError.missingMarkers {
                return
            } catch {
                finish(.failure(error), completion: completion)
            }
        }
        timer.resume()
    }

    public func cancel() {
        let existing = lock.withLock { () -> DispatchSourceTimer? in
            let current = timer
            timer = nil
            deadline = nil
            return current
        }
        existing?.cancel()
    }

    private func finish(_ result: Result<String, Error>, completion: @escaping Completion) {
        cancel()
        completion(result)
    }
}
