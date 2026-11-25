import AppKit
import UniformTypeIdentifiers

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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store = AttendanceStore()
    private var window: NSWindow!
    private var historyTable: NSTableView!
    private var studentTable: NSTableView!
    private var thresholdSlider: NSSlider!
    private var thresholdLabel: NSTextField!
    private var weeklySummaryButton: NSButton!
    private var summaryLabel: NSTextField!
    private var studentsLabel: NSTextField!
    private var averageLabel: NSTextField!
    private var lowCountLabel: NSTextField!
    private var reportTitleLabel: NSTextField!
    private var emptyState: NSTextField!
    private var studentRoster: [String: StudentRosterEntry] = [:]
    private var selectedReportID: UUID?

    private var selectedReport: AttendanceReport? {
        guard let report = store.reports.first(where: { $0.id == selectedReportID }) ?? store.reports.first else {
            return nil
        }
        return report.excludingStudentsTakingOnly(module: "COM668", accordingTo: studentRoster)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        if UserDefaults.standard.bool(forKey: "weeklySummaryEnabled"), let report = selectedReport {
            updateWeeklyNotification(for: report)
        }
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

        thresholdLabel = NSTextField(labelWithString: "LOW ATTENDANCE ALERT      80%")
        thresholdLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        thresholdLabel.textColor = .secondaryLabelColor
        thresholdSlider = NSSlider(value: 80, minValue: 50, maxValue: 95, target: self, action: #selector(thresholdChanged))
        thresholdSlider.numberOfTickMarks = 10
        thresholdSlider.allowsTickMarkValuesOnly = true
        weeklySummaryButton = NSButton(checkboxWithTitle: "Weekly summary notification", target: self, action: #selector(weeklySummaryChanged))
        weeklySummaryButton.state = UserDefaults.standard.bool(forKey: "weeklySummaryEnabled") ? .on : .off

        let settings = NSStackView(views: [thresholdLabel, thresholdSlider, weeklySummaryButton])
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
        let deleteButton = button("Delete Report", symbol: "trash", action: #selector(deleteReport))
        let actionRow = NSStackView(views: [exportButton, deleteButton, spacer()])
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
        guard let report = selectedReport else {
            reportTitleLabel.stringValue = "Import a CSV report"
            summaryLabel.stringValue = "Your imported reports will appear here."
            studentsLabel.stringValue = "0"
            averageLabel.stringValue = "—"
            lowCountLabel.stringValue = "—"
            studentTable.reloadData()
            return
        }
        reportTitleLabel.stringValue = "\(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(report.periodEnd.formatted(date: .abbreviated, time: .omitted))"
        summaryLabel.stringValue = "Imported \(report.importedAt.formatted(date: .abbreviated, time: .shortened))"
        studentsLabel.stringValue = "\(report.students.count)"
        averageLabel.stringValue = report.averageAttendance.formatted(.percent.precision(.fractionLength(1)))
        lowCountLabel.stringValue = "\(report.students.filter { $0.attendancePercentage < currentThreshold }.count)"
        thresholdLabel.stringValue = "LOW ATTENDANCE ALERT      \(Int(currentThreshold * 100))%"
        studentTable.reloadData()
    }

    private var currentThreshold: Double {
        thresholdSlider.doubleValue / 100
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == historyTable ? store.reports.count : (selectedReport?.students.count ?? 0)
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

        guard let report = selectedReport, report.students.indices.contains(row),
              let identifier = tableColumn?.identifier.rawValue else { return nil }
        let student = report.students[row]
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
            let filteredReport = report.excludingStudentsTakingOnly(
                module: "COM668",
                accordingTo: studentRoster
            )
            Task {
                do {
                    try await LocalNotifications.sendLowAttendanceAlert(report: filteredReport, threshold: currentThreshold)
                    if weeklySummaryButton.state == .on {
                        try await LocalNotifications.setWeeklySummary(enabled: true, report: filteredReport, threshold: currentThreshold)
                    }
                } catch {
                    showMessage(title: "Report imported, notification not sent", detail: error.localizedDescription)
                }
            }
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

    @objc private func thresholdChanged() {
        refresh()
        guard weeklySummaryButton.state == .on, let report = selectedReport else { return }
        updateWeeklyNotification(for: report)
    }

    @objc private func weeklySummaryChanged() {
        let enabled = weeklySummaryButton.state == .on
        UserDefaults.standard.set(enabled, forKey: "weeklySummaryEnabled")
        guard let report = selectedReport else { return }
        Task {
            do {
                try await LocalNotifications.setWeeklySummary(enabled: enabled, report: report, threshold: currentThreshold)
            } catch {
                weeklySummaryButton.state = .off
                UserDefaults.standard.set(false, forKey: "weeklySummaryEnabled")
                showMessage(title: "Could not update weekly summary", detail: error.localizedDescription)
            }
        }
    }

    private func updateWeeklyNotification(for report: AttendanceReport) {
        Task {
            do {
                let filteredReport = report.excludingStudentsTakingOnly(
                    module: "COM668",
                    accordingTo: studentRoster
                )
                try await LocalNotifications.setWeeklySummary(enabled: true, report: filteredReport, threshold: currentThreshold)
            } catch {
                weeklySummaryButton.state = .off
                UserDefaults.standard.set(false, forKey: "weeklySummaryEnabled")
                showMessage(title: "Could not update weekly summary", detail: error.localizedDescription)
            }
        }
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
        studentTable.addTableColumn(column)
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
