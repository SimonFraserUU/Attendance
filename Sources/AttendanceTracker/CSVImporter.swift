import Foundation

enum CSVImporter {
    static func parse(data: Data) throws -> [AttendanceStudent] {
        try parseReport(data: data).students
    }

    static func parseReport(data: Data) throws -> ImportedAttendanceCSV {
        guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw AttendanceImportError.emptyFile
        }
        if text.first == "\u{feff}" {
            text.removeFirst()
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard let headerLine = text.split(separator: "\n").first(where: {
            let normalized = normalize(String($0))
            return normalized.contains("studentno") && normalized.contains("studentname")
        }) else {
            throw AttendanceImportError.emptyFile
        }
        let delimiter: Character = headerLine.filter { $0 == "\t" }.count > headerLine.filter { $0 == "," }.count
            ? "\t"
            : ","
        let rows = try parseRows(text, delimiter: delimiter)
        guard let headerIndex = rows.firstIndex(where: { row in
            let normalized = row.map(normalize)
            return normalized.contains("studentno") && normalized.contains("studentname")
        }), let header = rows[safe: headerIndex] else {
            throw AttendanceImportError.missingColumns(["Student No", "Student Name"])
        }
        let period = try parsePeriodMetadata(rows.prefix(headerIndex).map { $0.joined(separator: " ") }.joined(separator: " "))

        var columns: [String: Int] = [:]
        for (index, name) in header.enumerated() {
            let key = normalize(name)
            guard !key.isEmpty else { continue }
            guard columns[key] == nil else {
                throw AttendanceImportError.invalidRow(1, "The header \(name) appears more than once.")
            }
            columns[key] = index
        }
        let aliases: [String: [String]] = [
            "student number": ["studentno", "studentnumber", "studentid", "id"],
            "student name": ["studentname", "name"],
            "possible attendance": ["possibleattendance", "possible"],
            "total attendance": ["totalattendance", "attendance"],
            "authorised absence": ["authorisedabsence", "authorizedabsence"],
            "unauthorised absence": ["unauthorisedabsence", "unauthorizedabsence"],
            "percentage attended": ["attended", "percentageattended", "attendedpercentage"],
            "year": ["year"],
            "email": ["email", "emailaddress"]
        ]
        let required = ["student number", "student name", "possible attendance", "total attendance"]
        let indexes: [String: Int] = aliases.compactMapValues { names in
            names.compactMap { columns[normalize($0)] }.first
        }
        let missing = required.filter { indexes[$0] == nil }
        guard missing.isEmpty else {
            throw AttendanceImportError.missingColumns(missing)
        }

        let dataRows = rows.dropFirst(headerIndex + 1).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard !dataRows.isEmpty else {
            throw AttendanceImportError.noStudents
        }

        var students: [AttendanceStudent] = []
        var seenNumbers = Set<String>()
        for (offset, row) in dataRows.enumerated() {
            let rowNumber = headerIndex + offset + 2
            func value(_ key: String) -> String? {
                guard let index = indexes[key], row.indices.contains(index) else { return nil }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let number = value("student number"), !number.isEmpty else {
                throw AttendanceImportError.invalidRow(rowNumber, "Student No is missing.")
            }
            guard let name = value("student name"), !name.isEmpty else {
                throw AttendanceImportError.invalidRow(rowNumber, "Student Name is missing.")
            }
            guard seenNumbers.insert(number).inserted else {
                throw AttendanceImportError.invalidRow(rowNumber, "Student No \(number) appears more than once.")
            }

            let possible = try parseNumber(value("possible attendance"), column: "Possible Attendance", row: rowNumber)
            let total = try parseNumber(value("total attendance"), column: "Total Attendance", row: rowNumber)
            let authorised = try parseOptionalNumber(value("authorised absence"), column: "Authorised Absence", row: rowNumber)
            let unauthorised = try parseOptionalNumber(value("unauthorised absence"), column: "Unauthorised Absence", row: rowNumber)
            let suppliedPercentage = try parsePercentage(value("percentage attended"), row: rowNumber)

            guard possible > 0 else {
                throw AttendanceImportError.invalidRow(rowNumber, "Possible Attendance must be greater than zero.")
            }
            guard total <= possible else {
                throw AttendanceImportError.invalidRow(rowNumber, "Total Attendance cannot exceed Possible Attendance.")
            }

            students.append(AttendanceStudent(
                studentNumber: number,
                name: name,
                possibleAttendance: possible,
                totalAttendance: total,
                authorisedAbsence: authorised,
                unauthorisedAbsence: unauthorised,
                suppliedPercentage: suppliedPercentage,
                year: value("year"),
                email: value("email")
            ))
        }
        return ImportedAttendanceCSV(students: students, periodStart: period.0, periodEnd: period.1)
    }

    static func parseRoster(data: Data) throws -> [String: StudentRosterEntry] {
        guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw AttendanceImportError.emptyFile
        }
        if text.first == "\u{feff}" {
            text.removeFirst()
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard let headerLine = text.split(separator: "\n").first else {
            throw AttendanceImportError.emptyFile
        }
        let delimiter: Character = headerLine.filter { $0 == "\t" }.count > headerLine.filter { $0 == "," }.count
            ? "\t"
            : ","
        let rows = try parseRows(text, delimiter: delimiter)
        guard let headerIndex = rows.firstIndex(where: { row in
            let normalized = row.map(normalize)
            return normalized.contains("studentid") && normalized.contains("year")
                && normalized.contains("email") && normalized.contains("modules")
        }), let header = rows[safe: headerIndex] else {
            throw AttendanceImportError.missingColumns(["Year", "Student ID", "Email", "Modules"])
        }

        var columns: [String: Int] = [:]
        for (index, name) in header.enumerated() {
            let key = normalize(name)
            guard !key.isEmpty else { continue }
            guard columns[key] == nil else {
                throw AttendanceImportError.invalidRow(headerIndex + 1, "The header \(name) appears more than once.")
            }
            columns[key] = index
        }
        guard let idIndex = columns["studentid"],
              let yearIndex = columns["year"],
              let emailIndex = columns["email"],
              let modulesIndex = columns["modules"] else {
            throw AttendanceImportError.missingColumns(["Year", "Student ID", "Email", "Modules"])
        }
        let dataRows = rows.dropFirst(headerIndex + 1).filter {
            $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard !dataRows.isEmpty else {
            throw AttendanceImportError.noStudents
        }

        var entries: [String: StudentRosterEntry] = [:]
        for (offset, row) in dataRows.enumerated() {
            let rowNumber = headerIndex + offset + 2
            func value(at index: Int) -> String? {
                guard row.indices.contains(index) else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            guard let studentNumber = value(at: idIndex) else {
                throw AttendanceImportError.invalidRow(rowNumber, "Student ID is missing.")
            }
            guard entries[studentNumber] == nil else {
                throw AttendanceImportError.invalidRow(rowNumber, "Student ID appears more than once.")
            }
            entries[studentNumber] = StudentRosterEntry(
                year: value(at: yearIndex),
                email: value(at: emailIndex),
                modules: value(at: modulesIndex)
            )
        }
        return entries
    }

    static func csvData(for report: AttendanceReport) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.isLenient = false
        let start = formatter.string(from: report.periodStart)
        let end = formatter.string(from: report.periodEnd)
        var lines = [
            "Report: Academic Report - Period: \(start) To \(end)",
            "Student No,Student Name,Year,Email,Possible Attendance,Total Attendance,Authorised Absence,Unauthorised Absence,% Attended"
        ]
        for student in report.students {
            let values = [
                student.studentNumber,
                student.name,
                student.year ?? "",
                student.email ?? "",
                formatNumber(student.possibleAttendance),
                formatNumber(student.totalAttendance),
                formatNumber(student.authorisedAbsence),
                formatNumber(student.unauthorisedAbsence),
                String(format: "%.1f%%", student.attendancePercentage * 100)
            ]
            lines.append(values.map(escapeCSV).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func lowAttendanceCSVData(
        for report: AttendanceReport,
        threshold: Double,
        excludingStudentNumbers: Set<String> = []
    ) -> Data {
        let filteredReport = AttendanceReport(
            id: report.id,
            importedAt: report.importedAt,
            periodStart: report.periodStart,
            periodEnd: report.periodEnd,
            students: report.studentsBelowThreshold(threshold).filter {
                !excludingStudentNumbers.contains($0.studentNumber)
            }
        )
        return csvData(for: filteredReport)
    }

    private static func parseRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    guard field.isEmpty else {
                        throw AttendanceImportError.invalidRow(rows.count + 1, "Unexpected quote in an unquoted field.")
                    }
                    inQuotes = true
                case delimiter:
                    row.append(field)
                    field = ""
                case "\n", "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                    if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                        index += 1
                    }
                default:
                    field.append(character)
                }
            }
            index += 1
        }
        guard !inQuotes else {
            throw AttendanceImportError.invalidRow(rows.count + 1, "A quoted field is not closed.")
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func parsePeriodMetadata(_ metadata: String) throws -> (Date, Date) {
        guard let marker = metadata.range(of: "Period:", options: .caseInsensitive) else {
            throw AttendanceImportError.invalidPeriodMetadata
        }
        let afterMarker = metadata[marker.upperBound...]
        let periodText: Substring
        if let generated = afterMarker.range(of: " - Generated:", options: .caseInsensitive) {
            periodText = afterMarker[..<generated.lowerBound]
        } else {
            periodText = afterMarker
        }
        guard let separator = periodText.range(of: "To", options: .caseInsensitive) else {
            throw AttendanceImportError.invalidPeriodMetadata
        }
        let startText = periodText[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = periodText[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.isLenient = false
        guard let start = formatter.date(from: startText), let end = formatter.date(from: endText), start <= end else {
            throw AttendanceImportError.invalidPeriodMetadata
        }
        return (start, end)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetterOrNumber)
    }

    private static func parseNumber(_ value: String?, column: String, row: Int) throws -> Double {
        guard let value, let number = Double(value.replacingOccurrences(of: ",", with: "")),
              number.isFinite, number >= 0 else {
            throw AttendanceImportError.invalidRow(row, "\(column) must be a non-negative number.")
        }
        return number
    }

    private static func parseOptionalNumber(_ value: String?, column: String, row: Int) throws -> Double {
        guard let value, !value.isEmpty else { return 0 }
        return try parseNumber(value, column: column, row: row)
    }

    private static func parsePercentage(_ value: String?, row: Int) throws -> Double? {
        guard let value, !value.isEmpty else { return nil }
        let cleaned = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let number = Double(cleaned), number.isFinite, (0...100).contains(number) else {
            throw AttendanceImportError.invalidRow(row, "% Attended must be a percentage from 0 to 100.")
        }
        return number / 100
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value, value > Double(Int.min), value < Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
