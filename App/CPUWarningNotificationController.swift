import Foundation
import Observation
import TemperatureCore
import TemperaturePresentation
@preconcurrency import UserNotifications

@MainActor @Observable final class CPUWarningNotificationController: NSObject, UNUserNotificationCenterDelegate {
    @ObservationIgnored private let backend: UserNotificationBackend
    @ObservationIgnored private let dispatcher: CPUWarningNotificationDispatcher
    @ObservationIgnored private let onOpenDashboard: @MainActor () -> Void

    var status: CPUWarningNotificationStatus { dispatcher.status }

    init(configuration: RuntimeConfiguration, onOpenDashboard: @escaping @MainActor () -> Void) {
        let backend = UserNotificationBackend()
        self.backend = backend
        dispatcher = CPUWarningNotificationDispatcher(configuration: configuration, backend: backend)
        self.onOpenDashboard = onOpenDashboard
        super.init()
        // Install before applicationDidFinishLaunching returns, including when
        // the App was opened by a user clicking a prior notification.
        backend.center?.delegate = self
        dispatcher.refreshAuthorization()
    }

    func start(sessionID: SessionID) { dispatcher.start(sessionID: sessionID) }
    func update(rule: CPUWarningRule) { dispatcher.update(rule: rule) }
    func consume(snapshot: CPUWarningSnapshot, at timestamp: Timestamp) { dispatcher.consume(snapshot: snapshot, at: timestamp) }
    func refreshAuthorization() { dispatcher.refreshAuthorization() }
    func pause() { dispatcher.pause() }
    func resume() { dispatcher.resume() }
    func stop() { dispatcher.stop() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        return await MainActor.run { [weak self] in
            guard let self, dispatcher.canPresent(requestIdentifier: identifier) else { return [] }
            return [.banner, .list]
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let opensApp = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        await MainActor.run { [weak self] in
            guard opensApp, let self, dispatcher.canOpenDashboard(requestIdentifier: identifier) else { return }
            onOpenDashboard()
        }
    }
}

private enum UserNotificationBackendError: Error { case centerUnavailable }

@MainActor private final class UserNotificationBackend: CPUWarningNotificationBackend {
    let center: UNUserNotificationCenter?

    init() {
        // current() requires an application identity; a command-line test
        // process must use an injected backend instead of invoking it.
        if Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" {
            center = UNUserNotificationCenter.current()
        } else { center = nil }
    }

    func authorization() async -> CPUWarningNotificationAuthorization {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notRequested
        case .authorized, .provisional: return .authorized
        case .denied: return .denied
        @unknown default: return .unavailable
        }
    }

    func requestAuthorization() async throws -> CPUWarningNotificationAuthorization {
        guard let center else { throw UserNotificationBackendError.centerUnavailable }
        _ = try await center.requestAuthorization(options: [.alert])
        return await authorization()
    }

    func add(_ attempt: CPUWarningNotificationAttempt) async throws {
        guard let center else { throw UserNotificationBackendError.centerUnavailable }
        let content = UNMutableNotificationContent()
        content.title = "CPU 温度预警"
        content.body = String(format: "CPU热区最高温度（Raw）持续%d秒达到%.1f°C阈值，事件峰值%.1f°C。",
            attempt.event.durationSeconds, attempt.event.thresholdC, attempt.event.peakRawMaxC)
        content.userInfo = ["sessionID": attempt.sessionID.rawValue, "eventID": attempt.event.eventID.rawValue]
        content.sound = nil
        let request = UNNotificationRequest(identifier: attempt.requestIdentifier, content: content, trigger: nil)
        try await center.add(request)
    }

    func cancel(identifier: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [identifier])
        center?.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
