import AppKit
import UniformTypeIdentifiers

private struct StudentEmailCandidate {
    let studentNumber: String
    let name: String
    let email: String?

    var recipient: String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        return trimmed
    }
}

@main
struct AttendanceTrackerApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store = AttendanceStore()
    private var window: NSWindow!
    private var historyTable: NSTableView!
    private var studentTable: NSTableView!
    private var displayedStudents: [AttendanceStudent] = []
    private var thresholdSlider: NSSlider!
    private var thresholdLabel: NSTextField!
    private var summaryLabel: NSTextField!
    private var studentsLabel: NSTextField!
    private var averageLabel: NSTextField!
    private var lowCountLabel: NSTextField!
    private var reportTitleLabel: NSTextField!
    private var emptyState: NSTextField!
    private var studentRoster: [String: StudentRosterEntry] = [:]
    private var selectedReportID: UUID?
    private var emailPanel: NSPanel?
    private var emailStartPicker: NSDatePicker?
    private var emailEndPicker: NSDatePicker?
    private var emailStudentTable: NSTableView?
    private var emailSelectionButton: NSButton?
    private var emailSubmitButton: NSButton?
    private var emailStudentCountLabel: NSTextField?
    private var emailCandidates: [StudentEmailCandidate] = []
    private var selectedEmailStudentNumbers = Set<String>()

    private var selectedReport: AttendanceReport? {
        guard let report = store.reports.first(where: { $0.id == selectedReportID }) ?? store.reports.first else {
            return nil
        }
        return report.excludingStudentsTakingOnly(module: "COM668", accordingTo: studentRoster)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LocalNotifications.removeWeeklySummary()
        buildWindow()
        selectedReportID = store.reports.first?.id
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        do {
            let rosterURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AttendanceTracker", isDirectory: true)
                .appendingPathComponent("StudentRoster.csv")
            guard FileManager.default.fileExists(atPath: rosterURL.path) else {
                throw AttendanceImportError.missingStudentRoster
            }
            studentRoster = try CSVImporter.parseRoster(data: Data(contentsOf: rosterURL))
            try store.applyStudentRoster(studentRoster)
        } catch {
            showMessage(title: "Could not load student roster", detail: error.localizedDescription)
        }
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Attendance Tracker"
        window.minSize = NSSize(width: 940, height: 620)
        window.center()

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "AttendanceTrackerSplitView"
        splitView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = splitView

        let sidebar = buildSidebar()
        let content = buildContent()
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(content)
        sidebar.widthAnchor.constraint(equalToConstant: 270).isActive = true
    }

    private func buildSidebar() -> NSView {
        let title = NSTextField(labelWithString: "Attendance")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let subtitle = secondaryLabel("LOCAL REPORTS")
        subtitle.font = .systemFont(ofSize: 10, weight: .semibold)

        let historyTitle = NSTextField(labelWithString: "REPORT HISTORY")
        historyTitle.font = .systemFont(ofSize: 10, weight: .semibold)
        historyTitle.textColor = .secondaryLabelColor

        historyTable = NSTableView()
        historyTable.headerView = nil
        historyTable.rowHeight = 58
        historyTable.intercellSpacing = NSSize(width: 0, height: 4)
        historyTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("period")))
        historyTable.dataSource = self
        historyTable.delegate = self
        let historyScroll = NSScrollView()
        historyScroll.documentView = historyTable
        historyScroll.hasVerticalScroller = true
        historyScroll.drawsBackground = false

        thresholdLabel = NSTextField(labelWithString: "LOW ATTENDANCE THRESHOLD      80%")
        thresholdLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        thresholdLabel.textColor = .secondaryLabelColor
        thresholdSlider = NSSlider(value: 80, minValue: 50, maxValue: 95, target: self, action: #selector(thresholdChanged(_:)))
        thresholdSlider.numberOfTickMarks = 10
        thresholdSlider.allowsTickMarkValuesOnly = true
        thresholdSlider.isContinuous = true

        let settings = NSStackView(views: [thresholdLabel, thresholdSlider])
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 10

        let stack = NSStackView(views: [title, subtitle, historyTitle, historyScroll, settings])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(8, after: historyTitle)
        stack.setCustomSpacing(14, after: historyScroll)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
            historyScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            historyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            thresholdSlider.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return container
    }

    private func buildContent() -> NSView {
        let pageTitle = NSTextField(labelWithString: "Attendance reports")
        pageTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        let periodHelp = secondaryLabel("The report period is read from the spreadsheet")
        periodHelp.font = .systemFont(ofSize: 12)

        let importButton = button("Import CSV", symbol: "square.and.arrow.down", action: #selector(importCSV))
        importButton.keyEquivalent = "o"
        importButton.keyEquivalentModifierMask = [.command]

        let heading = verticalStack([pageTitle, periodHelp], spacing: 4)
        let topRow = NSStackView(views: [heading, spacer(), importButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 16

        reportTitleLabel = NSTextField(labelWithString: "Import a CSV report")
        reportTitleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        summaryLabel = secondaryLabel("")
        let reportHeading = verticalStack([reportTitleLabel, summaryLabel], spacing: 5)

        studentsLabel = NSTextField(labelWithString: "—")
        averageLabel = NSTextField(labelWithString: "—")
        lowCountLabel = NSTextField(labelWithString: "—")
        let metrics = NSStackView(views: [
            metricCard("STUDENTS", value: studentsLabel, subtitle: "in this report"),
            metricCard("AVERAGE ATTENDANCE", value: averageLabel, subtitle: "mean across students"),
            metricCard("BELOW THRESHOLD", value: lowCountLabel, subtitle: "students to review")
        ])
        metrics.orientation = .horizontal
        metrics.alignment = .top
        metrics.distribution = .fillEqually
        metrics.spacing = 12

        let studentHeading = NSTextField(labelWithString: "STUDENT ATTENDANCE")
        studentHeading.font = .systemFont(ofSize: 10, weight: .semibold)
        studentHeading.textColor = .secondaryLabelColor

        studentTable = NSTableView()
        studentTable.rowHeight = 30
        studentTable.usesAlternatingRowBackgroundColors = true
        studentTable.dataSource = self
        studentTable.delegate = self
        studentTable.target = self
        studentTable.doubleAction = #selector(openAttendanceEmailForStudent(_:))
        addStudentColumn("Student No", identifier: "number", width: 95)
        addStudentColumn("Student Name", identifier: "name", width: 150)
        addStudentColumn("Year", identifier: "year", width: 60)
        addStudentColumn("Possible", identifier: "possible", width: 80)
        addStudentColumn("Attended", identifier: "total", width: 80)
        addStudentColumn("Authorised", identifier: "authorised", width: 90)
        addStudentColumn("Unauthorised", identifier: "unauthorised", width: 100)
        addStudentColumn("% Attended", identifier: "percentage", width: 120)
        let studentScroll = NSScrollView()
        studentScroll.documentView = studentTable
        studentScroll.hasVerticalScroller = true
        studentScroll.hasHorizontalScroller = true
        studentScroll.borderType = .bezelBorder

        emptyState = NSTextField(labelWithString: "Attendance is calculated from Total ÷ Possible. Reports are stored locally on this Mac.")
        emptyState.font = .systemFont(ofSize: 11)
        emptyState.textColor = .tertiaryLabelColor

        let exportButton = button("Export Low-Attendance CSV", symbol: "square.and.arrow.up", action: #selector(exportCSV))
        let emailButton = button("Email Attendance", symbol: "envelope", action: #selector(openEmailAttendance))
        let deleteButton = button("Delete Report", symbol: "trash", action: #selector(deleteReport))
        let actionRow = NSStackView(views: [exportButton, emailButton, deleteButton, spacer()])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        let contentStack = NSStackView(views: [
            topRow,
            reportHeading,
            metrics,
            studentHeading,
            studentScroll,
            emptyState,
            actionRow
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setCustomSpacing(24, after: topRow)
        contentStack.setCustomSpacing(4, after: studentHeading)
        contentStack.setCustomSpacing(2, after: studentScroll)

        let container = NSView()
        container.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
            studentScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            studentScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            topRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            metrics.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
        return container
    }

    private func refresh() {
        historyTable.reloadData()
        if let index = store.reports.firstIndex(where: { $0.id == selectedReport?.id }) {
            historyTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        thresholdLabel.stringValue = "LOW ATTENDANCE THRESHOLD      \(Int(currentThreshold * 100))%"
        guard let report = selectedReport else {
            reportTitleLabel.stringValue = "Import a CSV report"
            summaryLabel.stringValue = "Your imported reports will appear here."
            studentsLabel.stringValue = "0"
            averageLabel.stringValue = "—"
            lowCountLabel.stringValue = "—"
            reloadStudentTable()
            return
        }
        reportTitleLabel.stringValue = "\(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(report.periodEnd.formatted(date: .abbreviated, time: .omitted))"
        summaryLabel.stringValue = "Imported \(report.importedAt.formatted(date: .abbreviated, time: .shortened))"
        studentsLabel.stringValue = "\(report.students.count)"
        averageLabel.stringValue = report.averageAttendance.formatted(.percent.precision(.fractionLength(1)))
        lowCountLabel.stringValue = "\(report.students.filter { $0.attendancePercentage < currentThreshold }.count)"
        reloadStudentTable()
    }

    private var currentThreshold: Double {
        thresholdSlider.doubleValue / 100
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == historyTable {
            return store.reports.count
        }
        if tableView == emailStudentTable {
            return emailCandidates.count
        }
        return displayedStudents.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView == studentTable else { return }
        reloadStudentTable()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table == historyTable else { return }
        let row = table.selectedRow
        guard store.reports.indices.contains(row) else { return }
        guard selectedReportID != store.reports[row].id else { return }
        selectedReportID = store.reports[row].id
        refresh()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == emailStudentTable {
            guard emailCandidates.indices.contains(row) else { return nil }
            let candidate = emailCandidates[row]
            let emailStatus = candidate.recipient ?? "No valid email address"
            let checkbox = NSButton(
                checkboxWithTitle: "\(candidate.name) (\(candidate.studentNumber)) — \(emailStatus)",
                target: self,
                action: #selector(emailStudentSelectionChanged(_:))
            )
            checkbox.tag = row
            checkbox.state = selectedEmailStudentNumbers.contains(candidate.studentNumber) ? .on : .off
            checkbox.isEnabled = candidate.recipient != nil
            return checkbox
        }

        if tableView == historyTable {
            guard store.reports.indices.contains(row) else { return nil }
            let report = store.reports[row].excludingStudentsTakingOnly(
                module: "COM668",
                accordingTo: studentRoster
            )
            let main = NSTextField(labelWithString: report.periodStart.formatted(date: .abbreviated, time: .omitted))
            main.font = .systemFont(ofSize: 12, weight: .medium)
            let detail = NSTextField(labelWithString: "\(report.students.count) students · \(report.averageAttendance.formatted(.percent.precision(.fractionLength(0)))) average")
            detail.font = .systemFont(ofSize: 10)
            detail.textColor = .secondaryLabelColor
            let cell = NSStackView(views: [main, detail])
            cell.orientation = .vertical
            cell.alignment = .leading
            cell.spacing = 4
            return cell
        }

        guard displayedStudents.indices.contains(row),
              let identifier = tableColumn?.identifier.rawValue else { return nil }
        let student = displayedStudents[row]
        let text: String
        switch identifier {
        case "number": text = student.studentNumber
        case "name": text = student.name
        case "year": text = student.year ?? ""
        case "possible": text = format(student.possibleAttendance)
        case "total": text = format(student.totalAttendance)
        case "authorised": text = format(student.authorisedAbsence)
        case "unauthorised": text = format(student.unauthorisedAbsence)
        case "percentage": text = student.attendancePercentage.formatted(.percent.precision(.fractionLength(1)))
        default: return nil
        }
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        if identifier == "percentage", student.attendancePercentage < currentThreshold {
            field.textColor = .systemOrange
        }
        return field
    }

    @objc private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, UTType(filenameExtension: "tsv") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let imported = try CSVImporter.parseReport(data: Data(contentsOf: url))
            let report = try store.addReport(
                students: imported.students.map { student in
                    student.merging(rosterEntry: studentRoster[student.studentNumber])
                },
                start: imported.periodStart,
                end: imported.periodEnd
            )
            selectedReportID = report.id
            refresh()
        } catch {
            showMessage(title: "Could not import CSV", detail: error.localizedDescription)
        }
    }

    @objc private func exportCSV() {
        guard let report = selectedReport else { return }
        let lowAttendanceStudents = report.studentsBelowThreshold(currentThreshold)
        guard !lowAttendanceStudents.isEmpty else {
            showMessage(
                title: "No eligible low-attendance students",
                detail: "No students below the current \(Int(currentThreshold * 100))% threshold remain after excluding students taking only COM668."
            )
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "low-attendance-\(dateKey(report.periodStart))-to-\(dateKey(report.periodEnd)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVImporter.lowAttendanceCSVData(for: report, threshold: currentThreshold).write(to: url, options: .atomic)
        } catch {
            showMessage(title: "Could not export CSV", detail: error.localizedDescription)
        }
    }

    @objc private func openEmailAttendance() {
        guard !store.reports.isEmpty else {
            showMessage(title: "No attendance reports", detail: "Import at least one attendance report before preparing student emails.")
            return
        }

        let reports = store.reports
        let earliestDate = reports.map(\.periodStart).min() ?? Date()
        let latestDate = reports.map(\.periodEnd).max() ?? earliestDate
        selectedEmailStudentNumbers.removeAll()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Email Attendance"
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let title = NSTextField(labelWithString: "Prepare attendance emails")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let description = secondaryLabel("Choose a date range and select students. Each student gets a separate draft to protect their privacy.")
        description.font = .systemFont(ofSize: 12)

        let startPicker = emailDatePicker(date: earliestDate)
        let endPicker = emailDatePicker(date: latestDate)
        startPicker.target = self
        startPicker.action = #selector(emailDateRangeChanged)
        endPicker.target = self
        endPicker.action = #selector(emailDateRangeChanged)
        emailStartPicker = startPicker
        emailEndPicker = endPicker

        let dateRange = NSStackView(views: [
            labeledControl("From", control: startPicker),
            labeledControl("To", control: endPicker)
        ])
        dateRange.orientation = .horizontal
        dateRange.alignment = .centerY
        dateRange.spacing = 18

        let rangeHelp = secondaryLabel("Only reports whose full period falls within these dates are included.")
        rangeHelp.font = .systemFont(ofSize: 11)

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        emailStudentCountLabel = countLabel

        let selectAllButton = NSButton(
            checkboxWithTitle: "Select all students with a valid email address",
            target: self,
            action: #selector(toggleAllEmailStudents(_:))
        )
        emailSelectionButton = selectAllButton

        let studentsTable = NSTableView()
        studentsTable.headerView = nil
        studentsTable.rowHeight = 26
        studentsTable.dataSource = self
        studentsTable.delegate = self
        let studentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("emailStudent"))
        studentColumn.width = 650
        studentsTable.addTableColumn(studentColumn)
        emailStudentTable = studentsTable

        let studentsScroll = NSScrollView()
        studentsScroll.hasVerticalScroller = true
        studentsScroll.hasHorizontalScroller = true
        studentsScroll.borderType = .bezelBorder
        studentsScroll.documentView = studentsTable

        let cancelButton = button("Cancel", symbol: "xmark", action: #selector(closeEmailAttendance))
        let submitButton = button("Submit", symbol: "envelope", action: #selector(submitEmailAttendance))
        submitButton.keyEquivalent = "\r"
        emailSubmitButton = submitButton
        let actionRow = NSStackView(views: [spacer(), cancelButton, submitButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        let content = NSStackView(views: [
            title, description, dateRange, rangeHelp, countLabel, selectAllButton, studentsScroll, actionRow
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            studentsScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            studentsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            actionRow.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        panel.contentView = container
        emailPanel = panel
        refreshEmailStudentList()
        window.beginSheet(panel)
    }

    @objc private func openAttendanceEmailForStudent(_ sender: NSTableView) {
        guard sender.clickedColumn >= 0,
              sender.tableColumns.indices.contains(sender.clickedColumn),
              sender.tableColumns[sender.clickedColumn].identifier.rawValue == "name",
              displayedStudents.indices.contains(sender.clickedRow),
              let report = selectedReport else { return }

        let student = displayedStudents[sender.clickedRow]
        let candidate = StudentEmailCandidate(
            studentNumber: student.studentNumber,
            name: student.name,
            email: student.email
        )
        guard let recipient = candidate.recipient else {
            showMessage(
                title: "No valid email address",
                detail: "\(student.name) does not have a valid email address in the student roster."
            )
            return
        }
        guard let service = NSSharingService(named: .composeEmail) else {
            showMessage(title: "Email drafts unavailable", detail: "No compatible email composition service is available on this Mac.")
            return
        }

        let emailFont = attendanceEmailFont(warnWhenUnavailable: false)
        service.recipients = [recipient]
        service.subject = "Attendance data: \(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(report.periodEnd.formatted(date: .abbreviated, time: .omitted))"
        let body = attendanceEmailBody(
            for: candidate,
            reports: [(report, student)],
            start: report.periodStart,
            end: report.periodEnd,
            font: emailFont
        )
        service.perform(withItems: [body])
    }

    private func emailDatePicker(date: Date) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = date
        return picker
    }

    private func labeledControl(_ title: String, control: NSControl) -> NSView {
        let label = secondaryLabel(title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    @objc private func emailDateRangeChanged() {
        refreshEmailStudentList()
    }

    private func refreshEmailStudentList() {
        guard let startPicker = emailStartPicker,
              let endPicker = emailEndPicker else { return }

        let start = Calendar.current.startOfDay(for: startPicker.dateValue)
        let end = Calendar.current.startOfDay(for: endPicker.dateValue)
        let reports: [AttendanceReport]
        if start <= end {
            reports = store.reports.filter {
                Calendar.current.startOfDay(for: $0.periodStart) >= start
                    && Calendar.current.startOfDay(for: $0.periodEnd) <= end
            }
        } else {
            reports = []
        }

        var studentsByNumber: [String: AttendanceStudent] = [:]
        for report in reports {
            let visibleReport = report.excludingStudentsTakingOnly(
                module: "COM668",
                accordingTo: studentRoster
            )
            for student in visibleReport.students {
                if let existing = studentsByNumber[student.studentNumber] {
                    if StudentEmailCandidate(
                        studentNumber: student.studentNumber,
                        name: student.name,
                        email: student.email
                    ).recipient != nil,
                       StudentEmailCandidate(
                        studentNumber: student.studentNumber,
                        name: existing.name,
                        email: existing.email
                       ).recipient == nil {
                        studentsByNumber[student.studentNumber] = student
                    }
                } else {
                    studentsByNumber[student.studentNumber] = student
                }
            }
        }
        emailCandidates = studentsByNumber.values
            .map { StudentEmailCandidate(studentNumber: $0.studentNumber, name: $0.name, email: $0.email) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedEmailStudentNumbers.formIntersection(
            Set(emailCandidates.filter { $0.recipient != nil }.map(\.studentNumber))
        )

        emailStudentTable?.reloadData()

        let validCount = emailCandidates.filter { $0.recipient != nil }.count
        let missingCount = emailCandidates.count - validCount
        var countParts = ["\(emailCandidates.count) student\(emailCandidates.count == 1 ? "" : "s") in matching reports"]
        if missingCount > 0 {
            countParts.append("\(missingCount) without a valid email")
        }
        emailStudentCountLabel?.stringValue = start <= end
            ? countParts.joined(separator: " · ")
            : "The start date must be on or before the end date."

        let selectedCount = selectedEmailStudentNumbers.count
        emailSelectionButton?.state = selectedCount == 0
            ? .off
            : (selectedCount == validCount ? .on : .mixed)
        emailSubmitButton?.isEnabled = start <= end && selectedCount > 0
    }

    @objc private func emailStudentSelectionChanged(_ sender: NSButton) {
        guard emailCandidates.indices.contains(sender.tag) else { return }
        let studentNumber = emailCandidates[sender.tag].studentNumber
        if sender.state == .on {
            selectedEmailStudentNumbers.insert(studentNumber)
        } else {
            selectedEmailStudentNumbers.remove(studentNumber)
        }
        refreshEmailStudentList()
    }

    @objc private func toggleAllEmailStudents(_ sender: NSButton) {
        let eligibleNumbers = emailCandidates.filter { $0.recipient != nil }.map(\.studentNumber)
        if sender.state == .on {
            selectedEmailStudentNumbers.formUnion(eligibleNumbers)
        } else {
            selectedEmailStudentNumbers.subtract(eligibleNumbers)
        }
        refreshEmailStudentList()
    }

    @objc private func closeEmailAttendance() {
        guard let panel = emailPanel else { return }
        window.endSheet(panel)
        panel.orderOut(nil)
        clearEmailPanelState()
    }

    @objc private func submitEmailAttendance() {
        guard let startPicker = emailStartPicker, let endPicker = emailEndPicker else { return }
        let start = Calendar.current.startOfDay(for: startPicker.dateValue)
        let end = Calendar.current.startOfDay(for: endPicker.dateValue)
        guard start <= end else {
            showMessage(title: "Invalid date range", detail: "The start date must be on or before the end date.")
            return
        }

        let reports = store.reports.filter {
            Calendar.current.startOfDay(for: $0.periodStart) >= start
                && Calendar.current.startOfDay(for: $0.periodEnd) <= end
        }
        let students = emailCandidates.filter {
            selectedEmailStudentNumbers.contains($0.studentNumber) && $0.recipient != nil
        }
        guard !students.isEmpty else {
            showMessage(title: "No students selected", detail: "Select at least one student with a valid email address.")
            return
        }
        guard NSSharingService(named: .composeEmail) != nil else {
            showMessage(title: "Email drafts unavailable", detail: "No compatible email composition service is available on this Mac.")
            return
        }
        let emailFont = attendanceEmailFont(warnWhenUnavailable: true)

        guard let panel = emailPanel else { return }
        window.endSheet(panel)
        panel.orderOut(nil)
        clearEmailPanelState()

        let subject = "Attendance data: \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
        for student in students {
            guard let recipient = student.recipient else { continue }
            let studentReports = reports.compactMap { report -> (AttendanceReport, AttendanceStudent)? in
                let visibleReport = report.excludingStudentsTakingOnly(
                    module: "COM668",
                    accordingTo: studentRoster
                )
                guard let attendance = visibleReport.students.first(where: { $0.studentNumber == student.studentNumber }) else {
                    return nil
                }
                return (report, attendance)
            }
            guard !studentReports.isEmpty else { continue }

            let body = attendanceEmailBody(
                for: student,
                reports: studentReports,
                start: start,
                end: end,
                font: emailFont
            )
            guard let service = NSSharingService(named: .composeEmail) else {
                showMessage(title: "Could not open all email drafts", detail: "The email composition service became unavailable while preparing drafts.")
                return
            }
            service.recipients = [recipient]
            service.subject = subject
            service.perform(withItems: [body])
        }
    }

    private func attendanceEmailBody(
        for student: StudentEmailCandidate,
        reports: [(AttendanceReport, AttendanceStudent)],
        start: Date,
        end: Date,
        font: NSFont
    ) -> NSAttributedString {
        let forename = student.name
            .split(whereSeparator: \.isWhitespace)
            .last
            .map(String.init) ?? student.name
        var lines = [
            "Hello \(forename),",
            "",
            "Here is your attendance data for \(start.formatted(date: .long, time: .omitted)) to \(end.formatted(date: .long, time: .omitted)).",
            ""
        ]
        for (report, attendance) in reports.sorted(by: { $0.0.periodStart < $1.0.periodStart }) {
            lines.append("Report period: \(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(report.periodEnd.formatted(date: .abbreviated, time: .omitted))")
            lines.append("Attendance: \(format(attendance.totalAttendance)) of \(format(attendance.possibleAttendance)) (\(attendance.attendancePercentage.formatted(.percent.precision(.fractionLength(1)))))")
            lines.append("Authorised absence: \(format(attendance.authorisedAbsence))")
            lines.append("Unauthorised absence: \(format(attendance.unauthorisedAbsence))")
            lines.append("")
        }
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [.font: font])
    }

    private func attendanceEmailFont(warnWhenUnavailable: Bool) -> NSFont {
        if let aptos = NSFont(name: "Aptos", size: 12) {
            return aptos
        }
        if warnWhenUnavailable {
            showMessage(
                title: "Aptos font unavailable",
                detail: "Aptos isn't installed on this Mac. This email draft will use the system font at 12 pt."
            )
        }
        return .systemFont(ofSize: 12)
    }

    private func clearEmailPanelState() {
        emailPanel = nil
        emailStartPicker = nil
        emailEndPicker = nil
        emailStudentTable = nil
        emailSelectionButton = nil
        emailSubmitButton = nil
        emailStudentCountLabel = nil
        emailCandidates = []
        selectedEmailStudentNumbers.removeAll()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow == emailPanel else { return }
        clearEmailPanelState()
    }

    @objc private func deleteReport() {
        guard let report = selectedReport else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this imported report?"
        alert.informativeText = "This removes the report and its student data from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.deleteReport(report)
            selectedReportID = store.reports.first?.id
            refresh()
        } catch {
            showMessage(title: "Could not delete report", detail: error.localizedDescription)
        }
    }

    @objc private func thresholdChanged(_ sender: NSSlider) {
        refresh()
    }

    private func metricCard(_ title: String, value: NSTextField, subtitle: String) -> NSView {
        let titleField = secondaryLabel(title)
        titleField.font = .systemFont(ofSize: 10, weight: .semibold)
        let subtitleField = secondaryLabel(subtitle)
        subtitleField.font = .systemFont(ofSize: 10)
        value.font = .systemFont(ofSize: 27, weight: .semibold)
        let stack = verticalStack([titleField, value, subtitleField], spacing: 6)
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        stack.layer?.cornerRadius = 9
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 108).isActive = true
        return stack
    }

    private func addStudentColumn(_ title: String, identifier: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        studentTable.addTableColumn(column)
    }

    private func reloadStudentTable() {
        let students = selectedReport?.students ?? []
        guard let descriptor = studentTable.sortDescriptors.first,
              let key = descriptor.key else {
            displayedStudents = students
            studentTable.reloadData()
            return
        }

        displayedStudents = students.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch key {
            case "number":
                comparison = lhs.studentNumber.localizedStandardCompare(rhs.studentNumber)
            case "name":
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case "year":
                comparison = (lhs.year ?? "").localizedStandardCompare(rhs.year ?? "")
            case "possible":
                comparison = compare(lhs.possibleAttendance, rhs.possibleAttendance)
            case "total":
                comparison = compare(lhs.totalAttendance, rhs.totalAttendance)
            case "authorised":
                comparison = compare(lhs.authorisedAbsence, rhs.authorisedAbsence)
            case "unauthorised":
                comparison = compare(lhs.unauthorisedAbsence, rhs.unauthorisedAbsence)
            case "percentage":
                comparison = compare(lhs.attendancePercentage, rhs.attendancePercentage)
            default:
                comparison = .orderedSame
            }
            if comparison == .orderedSame {
                return lhs.studentNumber.localizedStandardCompare(rhs.studentNumber) == .orderedAscending
            }
            return descriptor.ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
        studentTable.reloadData()
    }

    private func compare(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func button(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        return button
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    private func showMessage(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
