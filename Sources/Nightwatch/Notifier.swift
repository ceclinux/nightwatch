import UserNotifications
import SkyCore

enum Notifier {
    static func requestAuthorisation() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Whether macOS will deliver a notification now. Alerts are only worked out, and recorded as sent, when it will: a
    /// notification posted before the person has answered the prompt is dropped, and must not count as sent (v0.6.10).
    static func authorised() async -> Bool {
        [.authorized, .provisional].contains(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// The heads-up's buttons (#57): "Open plan" opens Targets, "Not tonight" silences the rest of the night.
    static let headsUpCategory = "nightwatch.headsUp", openPlan = "open-plan", notTonight = "not-tonight"
    static func registerActions() {
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(
            identifier: headsUpCategory,
            actions: [UNNotificationAction(identifier: openPlan, title: L10n.text("Open plan"), options: [.foreground]),
                      UNNotificationAction(identifier: notTonight, title: L10n.text("Not tonight"), options: [])],
            intentIdentifiers: [])])
    }

    static func post(_ n: AlertNotification) {
        let content = UNMutableNotificationContent()
        if let night = n.planNight { content.categoryIdentifier = headsUpCategory; content.userInfo = ["night": night] }
        content.title = n.title
        content.body = n.body
        content.sound = n.kind == .go || n.kind == .aurora ? .default : nil   // aurora is brief: worth a sound (v0.6.6)
        let req = UNNotificationRequest(identifier: "nightwatch-\(n.kind)-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
