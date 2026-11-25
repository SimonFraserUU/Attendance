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

Each import is saved as a separate report. Students whose roster lists only COM668 are excluded from report views, summaries, notifications, and exports. Use **Export Low-Attendance CSV** to export the remaining students below the selected threshold. The export includes the report date range. If no students meet both criteria, the app displays a message instead of creating an empty file. Imported reports are stored under `~/Library/Application Support/AttendanceTracker/`.

Place `StudentRoster.csv` at `~/Library/Application Support/AttendanceTracker/StudentRoster.csv`. The app reads it automatically at launch; it is not bundled with the app or needed in the GitHub repository. The roster supplies Year and Email, matched by `Student ID` and `Student No`, and its Modules column is used to exclude students taking only COM668. Keep this file local because it contains personal data.

The sidebar lets you set the low-attendance threshold and optionally turn on a repeating Monday 9:00 AM summary notification. Low-attendance notifications are sent after import when any student is below the selected threshold. macOS may ask for notification permission.

## Test

```sh
make test
```
