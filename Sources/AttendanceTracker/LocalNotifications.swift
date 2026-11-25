import Foundation
import UserNotifications

@MainActor
enum LocalNotifications {
    static func removeWeeklySummary() {
        let center = UNUserNotificationCenter.current()
        let identifier = "weekly-attendance-summary"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        UserDefaults.standard.removeObject(forKey: "weeklySummaryEnabled")
    }
}
