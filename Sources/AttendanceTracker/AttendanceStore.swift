import Foundation
import Combine

@MainActor
final class AttendanceStore: ObservableObject {
    @Published private(set) var reports: [AttendanceReport] = []
    @Published var storageError: String?

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AttendanceTracker", isDirectory: true)
        fileURL = directory.appendingPathComponent("reports.json")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                reports = try JSONDecoder().decode([AttendanceReport].self, from: data)
                    .sorted { $0.importedAt > $1.importedAt }
            }
        } catch {
            storageError = "Could not load saved reports: \(error.localizedDescription)"
        }
    }

    func addReport(students: [AttendanceStudent], start: Date, end: Date) throws -> AttendanceReport {
        guard start <= end else { throw AttendanceImportError.invalidPeriod }
        let report = AttendanceReport(
            id: UUID(),
            importedAt: Date(),
            periodStart: Calendar.current.startOfDay(for: start),
            periodEnd: Calendar.current.startOfDay(for: end),
            students: students
        )
        let updated = ([report] + reports).sorted { $0.importedAt > $1.importedAt }
        try persist(updated)
        reports = updated
        return report
    }

    func applyStudentRoster(_ roster: [String: StudentRosterEntry]) throws {
        let updated = reports.map { report in
            AttendanceReport(
                id: report.id,
                importedAt: report.importedAt,
                periodStart: report.periodStart,
                periodEnd: report.periodEnd,
                students: report.students.map { student in
                    student.merging(rosterEntry: roster[student.studentNumber])
                }
            )
        }
        guard updated != reports else { return }
        try persist(updated)
        reports = updated
    }

    func deleteReport(_ report: AttendanceReport) throws {
        let updated = reports.filter { $0.id != report.id }
        try persist(updated)
        reports = updated
    }

    private func persist(_ reports: [AttendanceReport]) throws {
        let data = try JSONEncoder().encode(reports)
        try data.write(to: fileURL, options: .atomic)
    }
}
