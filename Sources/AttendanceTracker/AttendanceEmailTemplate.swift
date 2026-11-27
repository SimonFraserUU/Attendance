import Foundation

struct AttendanceEmailName: Equatable {
    let forename: String
    let fullName: String
}

enum AttendanceEmailTemplate {
    static let defaultsKey = "attendanceEmailTemplate"

    static let defaultTemplate = """
    Hello {{forename}},

    Here is your attendance data for {{start_date}} to {{end_date}}.

    {{attendance_details}}
    """

    static func name(fromRosterValue value: String?) -> AttendanceEmailName? {
        guard let value,
              let comma = value.firstIndex(of: ",") else { return nil }
        let surname = nameWords(in: String(value[..<comma]))
        let forename = nameWords(in: String(value[value.index(after: comma)...]))
        guard !surname.isEmpty, !forename.isEmpty else { return nil }
        return AttendanceEmailName(forename: forename, fullName: "\(forename) \(surname)")
    }

    static func displayName(_ value: String) -> String {
        guard let comma = value.firstIndex(of: ",") else {
            let words = nameWords(in: value)
            let parts = words.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count > 1 else { return words }
            let surname = String(parts.last!)
            let forename = parts.dropLast().map(String.init).joined(separator: " ")
            return "\(surname), \(forename)"
        }
        let surname = nameWords(in: String(value[..<comma]))
        let forename = nameWords(in: String(value[value.index(after: comma)...]))
        if surname.isEmpty { return forename }
        if forename.isEmpty { return surname }
        return "\(surname), \(forename)"
    }

    static func render(
        _ template: String,
        forename: String,
        fullName: String,
        startDate: String,
        endDate: String,
        attendanceDetails: String
    ) -> String {
        template
            .replacingOccurrences(of: "{{forename}}", with: forename)
            .replacingOccurrences(of: "{{name}}", with: fullName)
            .replacingOccurrences(of: "{{start_date}}", with: startDate)
            .replacingOccurrences(of: "{{end_date}}", with: endDate)
            .replacingOccurrences(of: "{{attendance_details}}", with: attendanceDetails)
    }

    private static func nameWords(in value: String) -> String {
        value.split(whereSeparator: \.isWhitespace)
            .filter { word in
                word.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count != 1
            }
            .joined(separator: " ")
    }
}
