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
        let surname = value[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
        let forename = value[value.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surname.isEmpty, !forename.isEmpty else { return nil }
        return AttendanceEmailName(forename: forename, fullName: "\(forename) \(surname)")
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
}
