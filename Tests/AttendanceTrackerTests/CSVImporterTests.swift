import Foundation

@main
struct CSVImporterTests {
    static func main() throws {
        try parsesQuotedNamesAndCalculatesAttendance()
        try parsesAcademicReportMetadataAndTabSeparatedRows()
        try parsesStudentRoster()
        try decodesReportsSavedBeforeRosterFieldsExisted()
        try rejectsDuplicateRosterIDs()
        try exportsOnlyStudentsBelowThreshold()
        try excludesCOM668OnlyStudentsFromReports()
        try rejectsSpreadsheetWithoutReportPeriod()
        try rejectsDuplicateStudentNumbers()
        try rejectsAttendanceGreaterThanPossible()
        try exportsAReportThatCanBeImportedAgain()
        try parsesDemoAttendanceDataset()
        try rendersAttendanceEmailTemplatePlaceholders()
        try parsesRosterNameForEmailPersonalization()
        try removesSingleLetterNameWords()
        try parsesForenamesFromWorkbookColumns()
        try generatesSafeOutlookMailMergeScripts()
        print("All 17 tests passed.")
    }

    private static func rendersAttendanceEmailTemplatePlaceholders() throws {
        let rendered = AttendanceEmailTemplate.render(
            "Hello {{forename}} ({{name}}), {{start_date}} to {{end_date}}:\n{{attendance_details}}",
            forename: "Alex",
            fullName: "Alex Example",
            startDate: "1 January 2026",
            endDate: "31 January 2026",
            attendanceDetails: "Attendance: 9 of 10"
        )
        try expect(
            rendered == "Hello Alex (Alex Example), 1 January 2026 to 31 January 2026:\nAttendance: 9 of 10",
            "Expected all supported email template placeholders to be replaced."
        )
    }

    private static func parsesRosterNameForEmailPersonalization() throws {
        let name = AttendanceEmailTemplate.name(fromRosterValue: "Smith, Mary Jane")
        try expect(name?.forename == "Mary Jane", "Expected the full forename after the comma.")
        try expect(name?.fullName == "Mary Jane Smith", "Expected the merge name in forename-surname order.")
        try expect(
            AttendanceEmailTemplate.name(fromRosterValue: "Incomplete") == nil,
            "Expected names without a comma to use the report-name fallback."
        )
    }

    private static func removesSingleLetterNameWords() throws {
        try expect(
            AttendanceEmailTemplate.displayName("Smith, Mary J.") == "Smith, Mary",
            "Expected one-letter initials to be removed from displayed roster names."
        )
        try expect(
            AttendanceEmailTemplate.displayName("Alex Example") == "Example, Alex",
            "Expected forename-surname names to be displayed as surname, forename."
        )
        let name = AttendanceEmailTemplate.name(fromRosterValue: "Smith, Mary J.")
        try expect(name?.forename == "Mary", "Expected one-letter initials to be removed from email forenames.")
        try expect(
            AttendanceEmailTemplate.displayName("J. Smith") == "Smith",
            "Expected one-letter initials to be removed from names without a roster comma."
        )
    }

    private static func parsesForenamesFromWorkbookColumns() throws {
        let sharedStrings = """
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>Student No</t></si>
          <si><t>Surname</t></si>
          <si><t>Forename</t></si>
          <si><t>10001</t></si>
          <si><t>Example</t></si>
          <si><t>Alex</t></si>
        </sst>
        """
        let worksheet = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="s"><v>0</v></c>
              <c r="B1" t="s"><v>1</v></c>
              <c r="C1" t="s"><v>2</v></c>
            </row>
            <row r="2">
              <c r="A2" t="s"><v>3</v></c>
              <c r="B2" t="s"><v>4</v></c>
              <c r="C2" t="s"><v>5</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
        let names = try XLSXImporter.parseNames(
            sharedStringsXML: Data(sharedStrings.utf8),
            worksheetXML: Data(worksheet.utf8)
        )
        try expect(names["10001"]?.forename == "Alex", "Expected the workbook Forename field to be used.")
        try expect(names["10001"]?.displayName == "Example, Alex", "Expected workbook names in surname-forename order.")
        try expect(names["10001"]?.emailName == "Example, Alex", "Expected the email full name to use surname-forename order with a comma.")
    }

    private static func generatesSafeOutlookMailMergeScripts() throws {
        let message = OutlookEmailMessage(
            recipient: "alex@example.com",
            subject: "Attendance \"update\"",
            body: "Hello Alex,\nYour attendance is 90%."
        )
        let source = OutlookAppleScript.sendMessageSource(for: message)
        try expect(source.contains("tell application id \"com.microsoft.Outlook\""), "Expected the Outlook bundle identifier.")
        try expect(source.contains("make new to recipient"), "Expected an individual To recipient.")
        try expect(source.contains("Attendance \\\"update\\\""), "Expected quotes to be escaped in the subject.")
        try expect(source.contains("linefeed"), "Expected message newlines to be preserved.")
        try expect(source.contains("send outgoingMessage"), "Expected the generated script to send the message.")
    }

    private static func parsesDemoAttendanceDataset() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Examples/DemoAttendance.csv"))
        let report = try CSVImporter.parseReport(data: data)
        try expect(report.students.count == 20, "Expected the demo dataset to contain 20 students.")
        try expect(report.students.allSatisfy { $0.studentNumber.hasPrefix("DEMO") }, "Expected demo student IDs.")
        try expect(
            report.students.allSatisfy { $0.email?.isEmpty ?? true },
            "Expected the demo dataset to contain no email addresses."
        )
        try expect(
            report.students.filter { $0.attendancePercentage < 0.8 }.count == 8,
            "Expected the demo dataset to include a range of low-attendance students."
        )
    }

    private static func parsesAcademicReportMetadataAndTabSeparatedRows() throws {
        let tsv = """
        Report: Academic Report - Period: 21/09/2026  To 26/10/2026 - Generated: 28/10/2026 11:19:48
        Faculty: All - School: All - Course : BT_BSc Hons Computing Systems PT (8332) Y1 -  Module  : All
        Student No\tStudent Name\tPossible Attendance\tTotal Attendance\tAuthorised Absence\tUnauthorised Absence\t% Attended
        10001\tAlex Example\t20\t18\t1\t1\t90%
        """

        let imported = try CSVImporter.parseReport(data: Data(tsv.utf8))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd/MM/yyyy"

        try expect(imported.students.count == 1, "Expected the student header to be found after metadata rows.")
        try expect(imported.students[0].studentNumber == "10001", "Expected tab-separated student number.")
        try expect(imported.periodStart == formatter.date(from: "21/09/2026"), "Expected period start to be read from metadata.")
        try expect(imported.periodEnd == formatter.date(from: "26/10/2026"), "Expected period end to be read from metadata.")
    }

    private static func parsesQuotedNamesAndCalculatesAttendance() throws {
        let csv = """
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Possible Attendance,Total Attendance,Authorised Absence,Unauthorised Absence,% Attended
        10001,"Alex, Example",20,18,1,1,90%
        """

        let students = try CSVImporter.parse(data: Data(("\u{feff}" + csv).utf8))
        try expect(students.count == 1, "Expected one student.")
        try expect(students[0].name == "Alex, Example", "Expected quoted name to be parsed.")
        try expect(abs(students[0].attendancePercentage - 0.9) < 0.0001, "Attendance should be computed from totals.")
        try expect(students[0].suppliedPercentage == 0.9, "Expected supplied percentage to be parsed.")
    }

    private static func parsesStudentRoster() throws {
        let csv = """
        Year,Student ID,Name,Programme,Email,Modules
        Y1,10001,"Example, Alex",Computing,alex@example.com,COM668
        Y2,10002,"Example, Sam",Computing,sam@example.com,"COM661, COM668"
        """

        let roster = try CSVImporter.parseRoster(data: Data(("\u{feff}" + csv).utf8))
        try expect(roster.count == 2, "Expected two roster entries.")
        try expect(roster["10001"]?.year == "Y1", "Expected student year to be parsed.")
        try expect(roster["10001"]?.name == "Example, Alex", "Expected the roster name to be parsed.")
        try expect(roster["10001"]?.email == "alex@example.com", "Expected student email to be parsed.")
        try expect(roster["10001"]?.isOnlyTaking(module: "COM668") == true, "Expected a student taking only COM668 to be identified.")
        try expect(roster["10002"]?.isOnlyTaking(module: "COM668") == false, "Expected students taking other modules to remain eligible.")
    }

    private static func decodesReportsSavedBeforeRosterFieldsExisted() throws {
        let json = """
        {
          "studentNumber": "10001",
          "name": "Alex Example",
          "possibleAttendance": 20,
          "totalAttendance": 18,
          "authorisedAbsence": 1,
          "unauthorisedAbsence": 1,
          "suppliedPercentage": 0.9
        }
        """
        let student = try JSONDecoder().decode(AttendanceStudent.self, from: Data(json.utf8))
        try expect(student.year == nil && student.email == nil, "Expected saved reports without roster fields to remain readable.")
    }

    private static func rejectsDuplicateRosterIDs() throws {
        let csv = """
        Year,Student ID,Email,Modules
        Y1,10001,alex@example.com,COM668
        Y2,10001,alex2@example.com,COM661
        """

        do {
            _ = try CSVImporter.parseRoster(data: Data(csv.utf8))
            throw TestFailure(description: "Duplicate roster IDs should be rejected.")
        } catch let error as AttendanceImportError {
            try expect(error.localizedDescription.contains("Student ID appears more than once"), "Expected duplicate roster ID validation.")
        }
    }

    private static func exportsOnlyStudentsBelowThreshold() throws {
        let students = try CSVImporter.parse(data: Data("""
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Possible Attendance,Total Attendance
        10001,Alex Example,10,7
        10002,Sam Sample,10,6
        10003,Taylor Example,10,9
        """.utf8))
        let date = Date(timeIntervalSince1970: 1_759_276_800)
        let report = AttendanceReport(
            id: UUID(),
            importedAt: date,
            periodStart: date,
            periodEnd: date,
            students: students
        )
        let roster = try CSVImporter.parseRoster(data: Data("""
        Year,Student ID,Email,Modules
        Y1,10001,alex@example.com,COM668
        Y1,10002,sam@example.com,"COM661, COM668"
        Y1,10003,taylor@example.com,COM672
        """.utf8))
        let com668OnlyStudentNumbers = Set(roster.compactMap { studentNumber, entry in
            entry.isOnlyTaking(module: "COM668") ? studentNumber : nil
        })

        let exported = try CSVImporter.parse(
            data: CSVImporter.lowAttendanceCSVData(
                for: report,
                threshold: 0.8,
                excludingStudentNumbers: com668OnlyStudentNumbers
            )
        )
        try expect(exported.count == 1, "Expected export to include only students below the threshold.")
        try expect(exported[0].studentNumber == "10002", "Expected excluded students not to be exported.")
    }

    private static func excludesCOM668OnlyStudentsFromReports() throws {
        let students = try CSVImporter.parse(data: Data("""
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Possible Attendance,Total Attendance
        10001,Alex Example,10,7
        10002,Sam Sample,10,8
        """.utf8))
        let date = Date(timeIntervalSince1970: 1_759_276_800)
        let report = AttendanceReport(
            id: UUID(),
            importedAt: date,
            periodStart: date,
            periodEnd: date,
            students: students
        )
        let roster = try CSVImporter.parseRoster(data: Data("""
        Year,Student ID,Email,Modules
        Y1,10001,alex@example.com,COM668
        Y1,10002,sam@example.com,"COM661, COM668"
        """.utf8))

        let filtered = report.excludingStudentsTakingOnly(module: "COM668", accordingTo: roster)
        try expect(filtered.students.count == 1, "Expected COM668-only students to be removed from the report.")
        try expect(filtered.students[0].studentNumber == "10002", "Expected students taking other modules to remain.")
    }

    private static func rejectsSpreadsheetWithoutReportPeriod() throws {
        let csv = """
        Student No,Student Name,Possible Attendance,Total Attendance
        10001,Alex Example,20,18
        """

        do {
            _ = try CSVImporter.parseReport(data: Data(csv.utf8))
            throw TestFailure(description: "A report without its spreadsheet period should be rejected.")
        } catch AttendanceImportError.invalidPeriodMetadata {
            return
        }
    }

    private static func rejectsDuplicateStudentNumbers() throws {
        let csv = """
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Possible Attendance,Total Attendance
        10001,Alex Example,20,18
        10001,Sam Sample,20,17
        """

        do {
            _ = try CSVImporter.parse(data: Data(csv.utf8))
            throw TestFailure(description: "Duplicate student numbers should be rejected.")
        } catch let error as AttendanceImportError {
            try expect(error.localizedDescription.contains("appears more than once"), "Expected duplicate ID validation.")
        }
    }

    private static func rejectsAttendanceGreaterThanPossible() throws {
        let csv = """
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Possible Attendance,Total Attendance
        10001,Alex Example,10,11
        """

        do {
            _ = try CSVImporter.parse(data: Data(csv.utf8))
            throw TestFailure(description: "Attendance greater than possible should be rejected.")
        } catch let error as AttendanceImportError {
            try expect(error.localizedDescription.contains("cannot exceed"), "Expected impossible totals validation.")
        }
    }

    private static func exportsAReportThatCanBeImportedAgain() throws {
        let students = try CSVImporter.parse(data: Data("""
        Report: Academic Report - Period: 21/09/2026 To 26/10/2026
        Student No,Student Name,Year,Email,Possible Attendance,Total Attendance
        10001,"Alex, Example",Y1,alex@example.com,20,18
        """.utf8))
        let start = Date(timeIntervalSince1970: 1_759_276_800)
        let report = AttendanceReport(
            id: UUID(),
            importedAt: start,
            periodStart: start,
            periodEnd: start,
            students: students
        )

        let exported = try CSVImporter.parse(data: CSVImporter.csvData(for: report))
        try expect(exported.count == 1, "Expected exported report to re-import.")
        try expect(exported[0].name == "Alex, Example", "Expected commas in names to round-trip.")
        try expect(exported[0].year == "Y1", "Expected student year to round-trip.")
        try expect(exported[0].email == "alex@example.com", "Expected student email to round-trip.")
        try expect(exported[0].attendancePercentage == 0.9, "Expected attendance totals to round-trip.")
        let reimportedReport = try CSVImporter.parseReport(data: CSVImporter.csvData(for: report))
        let expectedStart = Calendar.current.startOfDay(for: report.periodStart)
        try expect(reimportedReport.periodStart == expectedStart, "Expected report period to round-trip.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(description: message)
        }
    }
}

private struct TestFailure: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}
