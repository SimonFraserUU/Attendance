import Foundation
import UserNotifications

@MainActor
enum LocalNotifications {
    static func sendLowAttendanceAlert(report: AttendanceReport, threshold: Double) async throws {
        let lowCount = report.students.filter { $0.attendancePercentage < threshold }.count
        guard lowCount > 0 else { return }

        try await requestPermission()
        let content = UNMutableNotificationContent()
        content.title = "Low attendance alert"
        content.body = "\(lowCount) student\(lowCount == 1 ? "" : "s") fell below \(Int(threshold * 100))% attendance for the imported period."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    static func setWeeklySummary(enabled: Bool, report: AttendanceReport?, threshold: Double) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-attendance-summary"])
        guard enabled, let report else { return }

        try await requestPermission()
        let lowCount = report.students.filter { $0.attendancePercentage < threshold }.count
        let content = UNMutableNotificationContent()
        content.title = "Weekly attendance summary"
        content.body = "\(report.students.count) students · \(Int(report.averageAttendance * 100))% average attendance · \(lowCount) below threshold."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 9, weekday: 2),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "weekly-attendance-summary",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    private static func requestPermission() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw NotificationError.permissionDenied
        }
    }
}

private enum NotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Notification permission is off. Enable notifications for Attendance Tracker in System Settings to receive alerts."
    }
}
