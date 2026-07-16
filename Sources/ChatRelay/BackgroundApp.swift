import AppKit
import HandoffCore
import ServiceManagement
import UserNotifications

final class BackgroundApp: NSObject, NSApplicationDelegate {
    private let commandMonitor = CommandMonitor()
    private lazy var coordinator = HandoffCoordinator { title, body in
        NotificationService.send(title: title, body: body)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.requestAuthorization()
        registerLoginItemIfPossible()

        let accessibilityTrusted = AccessibilityProbe.isTrusted(prompt: false)
        guard accessibilityTrusted else {
            writeRuntimeStatus(accessibilityTrusted: false, eventMonitorActive: false)
            NotificationService.send(
                title: "ChatRelay needs Accessibility",
                body: "Enable the installed helper in Privacy & Security > Accessibility."
            )
            return
        }

        do {
            try HandoffStore().prepareDirectory()
        } catch {
            NotificationService.send(
                title: "ChatRelay cannot access the vault",
                body: "Allow Documents folder access, then relaunch the helper."
            )
        }

        commandMonitor.onCommand = { [weak self] command, target in
            self?.coordinator.handle(command, target: target)
        }
        let eventMonitorActive = commandMonitor.start()
        writeRuntimeStatus(
            accessibilityTrusted: accessibilityTrusted,
            eventMonitorActive: eventMonitorActive
        )
        if !eventMonitorActive {
            NotificationService.send(
                title: "ChatRelay could not start",
                body: "The keyboard event monitor is unavailable. Recheck Accessibility permission."
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandMonitor.stop()
    }

    private func registerLoginItemIfPossible() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        try? service.register()
    }

    private func writeRuntimeStatus(accessibilityTrusted: Bool, eventMonitorActive: Bool) {
        let status = RuntimeStatus(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(),
            accessibilityTrusted: accessibilityTrusted,
            eventMonitorActive: eventMonitorActive,
            loginItemEnabled: SMAppService.mainApp.status == .enabled
        )
        try? status.write()
    }
}

private enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
