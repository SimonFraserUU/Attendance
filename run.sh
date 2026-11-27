#!/bin/sh
set -eu

cd "$(dirname "$0")"
app=".build/AttendanceTracker.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"

swiftc -O \
    -sdk "$(xcrun --show-sdk-path)" \
    -target "$(uname -m)-apple-macosx14.0" \
    -o "$app/Contents/MacOS/AttendanceTracker" \
    Sources/AttendanceTracker/AttendanceModels.swift \
    Sources/AttendanceTracker/CSVImporter.swift \
    Sources/AttendanceTracker/AttendanceEmailTemplate.swift \
    Sources/AttendanceTracker/XLSXImporter.swift \
    Sources/AttendanceTracker/OutlookAppleScript.swift \
    Sources/AttendanceTracker/OutlookEmailSender.swift \
    Sources/AttendanceTracker/AttendanceStore.swift \
    Sources/AttendanceTracker/LocalNotifications.swift \
    Sources/AttendanceTracker/AttendanceTrackerApp.swift \
    -framework AppKit \
    -framework UserNotifications

cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AttendanceTracker.icns "$app/Contents/Resources/AttendanceTracker.icns"

installed="$HOME/Applications/AttendanceTracker.app"
mkdir -p "$HOME/Applications"
ditto "$app" "$installed"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed"
mdimport "$installed" >/dev/null 2>&1 || true
open "$installed"
