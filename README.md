# Attendance Tracker

A native macOS app for reviewing student attendance summary CSVs. Imported report history and the student roster are stored locally on this Mac.

## Run

Requires macOS 14 or newer and the Swift command-line tools.

From this directory, build and launch the native Mac app:

```sh
./run.sh
```

The app accepts comma-separated CSV and tab-separated exports. It finds the student header row even when report metadata appears above it. The report metadata must include a period in `dd/MM/yyyy To dd/MM/yyyy` form; the app reads the dates from that row and rejects files without a readable period.

The required student columns (header spelling is case-insensitive) are:

- `Student No`
- `Student Name`
- `Possible Attendance`
- `Total Attendance`

These columns are optional:

- `Authorised Absence` (optional)
- `Unauthorised Absence` (optional)
- `% Attended` (optional; displayed attendance is calculated from Total ÷ Possible)
- `Year` and `Email` (optional; otherwise matched from the bundled roster)

For screenshots and demonstrations, import [Examples/DemoAttendance.csv](Examples/DemoAttendance.csv). It contains fictional students with `DEMO` IDs and no email addresses.

Each import is saved as a separate report. Students whose roster lists only COM668 are excluded from report views, summaries, and exports. Use **Export Low-Attendance CSV** to export the remaining students below the selected threshold. The export includes the report date range. If no students meet both criteria, the app displays a message instead of creating an empty file. Imported reports are stored under `~/Library/Application Support/AttendanceTracker/`.

Place `StudentRoster.csv` at `~/Library/Application Support/AttendanceTracker/StudentRoster.csv`. The app reads it automatically at launch; it is not bundled with the app or needed in the GitHub repository. The roster supplies Year and Email, matched by `Student ID` and `Student No`, and its Modules column is used to exclude students taking only COM668. Keep this file local because it contains personal data.

Place `Names.xlsx` at `~/Library/Application Support/AttendanceTracker/Names.xlsx`, alongside `StudentRoster.csv`. Its first worksheet must include `Student No`, `Surname`, and `Forename` columns. The app matches names by student number and uses the workbook's `Surname` and `Forename` fields for student lists and email drafts. Standalone one-letter words are omitted. If a student number is not present in the workbook, the app falls back to the roster's Name field and then the report name. The workbook is read locally and is not copied into the repository.

The sidebar slider sets the low-attendance threshold used by the report summary and CSV export. Attendance Tracker sends no notifications; importing reports and creating email drafts remain manual actions.

Use **Email Attendance** to select a date range and one or more students with valid email addresses. Only complete report periods within the selected range are included; each report's attendance values are shown separately. Use the **Mail Merge** section to edit the shared message before submitting; the template is saved locally and used for future drafts. The `{{forename}}` and `{{name}}` placeholders use the workbook's `Forename` and `Surname` fields; `{{name}}` is rendered as `Surname, Forename`. If no workbook match exists, the roster name and then report name are used. `{{start_date}}`, `{{end_date}}`, and `{{attendance_details}}` insert the date range and selected attendance reports. With automatic sending unchecked, submitting opens individual prefilled drafts in the configured macOS email app. Checking **Send automatically with Microsoft Outlook** sends one individual email per selected student after a final recipient-count confirmation; macOS may ask permission for Attendance Tracker to control Outlook. Emails are never sent to other students as CC or BCC recipients.

Double-click anywhere on a student's row to open a prefilled attendance email for the currently selected report.

Click any student table column heading to sort by that field; click it again to reverse the sort order.

## Test

```sh
make test
```
