.PHONY: test

test:
	mkdir -p .build
	swiftc -parse-as-library -o .build/CSVImporterTests \
		Sources/AttendanceTracker/AttendanceModels.swift \
		Sources/AttendanceTracker/CSVImporter.swift \
		Sources/AttendanceTracker/AttendanceEmailTemplate.swift \
		Sources/AttendanceTracker/XLSXImporter.swift \
		Sources/AttendanceTracker/OutlookAppleScript.swift \
		Tests/AttendanceTrackerTests/CSVImporterTests.swift
	.build/CSVImporterTests
