import SwiftUI
import Foundation
import UserNotifications
import SkyCore
import PhoneCore

/// The real notification centre behind PhoneCore's protocol: alerts due now are posted at once, later ones are queued with a
/// time trigger. Every refresh replaces the whole queue, so a downgraded forecast cancels what it had promised.
public struct UserNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private let now: @Sendable () -> Date
    /// `now` is the app's clock, so a demo clock shifts the queue's triggers with it.
    public init(center: UNUserNotificationCenter = .current(), now: @escaping @Sendable () -> Date = { Date() }) { self.center = center; self.now = now }

    public func isAuthorised() async -> Bool {
        let s = await center.notificationSettings().authorizationStatus
        return s == .authorized || s == .provisional
    }

    public func post(_ n: AlertNotification) async {
        guard await isAuthorised() else { return }
        let content = Self.content(title: n.title, body: n.body)
        try? await center.add(UNNotificationRequest(identifier: "now.\(UUID().uuidString)", content: content, trigger: nil))
    }

    public func replaceScheduled(_ alerts: [ScheduledAlert]) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { !$0.hasPrefix("now.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard await isAuthorised() else { return }
        for a in alerts where a.fireDate > now() {
            NSLog("Nightwatch queued %@ for %@", a.id, a.fireDate.description)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, a.fireDate.timeIntervalSince(now())), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: a.id, content: Self.content(title: a.title, body: a.body), trigger: trigger))
        }
    }

    private static func content(title: String, body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title.plainDashes; c.body = body.plainDashes; c.sound = .default
        return c
    }
}

/// Where permission stands, for the one prompt the app shows. Asked only after the user has seen the verdict, and only when
/// they press the button (never at launch).
@MainActor
public final class NotificationPermission: ObservableObject {
    @Published public private(set) var status: UNAuthorizationStatus = .notDetermined
    public init() { Task { await refresh() } }

    public func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }

    public func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }
}

/// The card on Tonight that asks for alerts: why first, then the system prompt. Gone once decided either way.
public struct AlertsPrompt: View {
    @ObservedObject var permission: NotificationPermission
    let onGranted: () -> Void
    public init(permission: NotificationPermission, onGranted: @escaping () -> Void) { self.permission = permission; self.onGranted = onGranted }
    @Environment(\.phoneTheme) private var theme

    public var body: some View {
        if permission.status == .notDetermined {
            Card(glass: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Be told when it is worth going out").font(.callout.weight(.medium))
                    Text("An alert an hour before dark, another before the clear window opens, and a note if the forecast turns. Nothing else, and never during your quiet hours.")
                        .font(.footnote).secondary().fixedSize(horizontal: false, vertical: true)
                    PillButton(title: "Turn on alerts") {
                        Task {
                            await permission.request()
                            if permission.status == .authorized { Haptic.success(); onGranted() } else { Haptic.warning() }
                        }
                    }
                }
            }
        }
    }
}
