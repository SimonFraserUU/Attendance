import Foundation

struct AttendanceStudent: Identifiable, Codable, Equatable {
    var id: String { studentNumber }

    let studentNumber: String
    let name: String
    let possibleAttendance: Double
    let totalAttendance: Double
    let authorisedAbsence: Double
    let unauthorisedAbsence: Double
    let suppliedPercentage: Double?
    var year: String? = nil
    var email: String? = nil

    var attendancePercentage: Double {
        guard possibleAttendance > 0 else { return 0 }
        return totalAttendance / possibleAttendance
    }

    func merging(rosterEntry: StudentRosterEntry?) -> AttendanceStudent {
        guard let rosterEntry else { return self }
        var updated = self
        updated.year = rosterEntry.year ?? year
        updated.email = rosterEntry.email ?? email
        return updated
    }
}

struct StudentRosterEntry: Equatable {
    let year: String?
    let email: String?
    let modules: String?

    func isOnlyTaking(module: String) -> Bool {
        let moduleCodes = Set((modules ?? "").split(separator: ",").compactMap { value -> String? in
            let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return code.isEmpty ? nil : code
        })
        return moduleCodes.count == 1 && moduleCodes.contains(module.uppercased())
    }
}

struct AttendanceReport: Identifiable, Codable, Equatable {
    let id: UUID
    let importedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let students: [AttendanceStudent]

    var averageAttendance: Double {
        guard !students.isEmpty else { return 0 }
        return students.reduce(0) { $0 + $1.attendancePercentage } / Double(students.count)
    }

    func studentsBelowThreshold(_ threshold: Double) -> [AttendanceStudent] {
        students.filter { $0.attendancePercentage < threshold }
    }

    func excludingStudentsTakingOnly(module: String, accordingTo roster: [String: StudentRosterEntry]) -> AttendanceReport {
        let includedStudents = students.filter {
            roster[$0.studentNumber]?.isOnlyTaking(module: module) != true
        }
        return AttendanceReport(
            id: id,
            importedAt: importedAt,
            periodStart: periodStart,
            periodEnd: periodEnd,
            students: includedStudents
        )
    }
}

struct ImportedAttendanceCSV {
    let students: [AttendanceStudent]
    let periodStart: Date
    let periodEnd: Date
}

enum AttendanceImportError: LocalizedError {
    case emptyFile
    case missingColumns([String])
    case invalidRow(Int, String)
    case noStudents
    case invalidPeriod
    case invalidPeriodMetadata
    case missingStudentRoster

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected CSV file is empty."
        case .missingColumns(let columns):
            return "Missing required column(s): \(columns.joined(separator: ", "))."
        case .invalidRow(let row, let reason):
            return "Row \(row): \(reason)"
        case .noStudents:
            return "The CSV contains a header but no student rows."
        case .invalidPeriod:
            return "The period start date must be on or before the end date."
        case .invalidPeriodMetadata:
            return "The report's period could not be read. Expected dates in day/month/year format."
        case .missingStudentRoster:
            return "StudentRoster.csv was not found in ~/Library/Application Support/AttendanceTracker/."
        }
    }
}
