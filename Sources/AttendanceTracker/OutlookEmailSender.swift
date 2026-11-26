import AppKit
import Foundation

enum OutlookEmailSender {
    private static let outlookBundleIdentifier = "com.microsoft.Outlook"

    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: outlookBundleIdentifier) != nil
    }

    static func send(_ messages: [OutlookEmailMessage]) throws {
        for (index, message) in messages.enumerated() {
            do {
                try send(message)
            } catch {
                throw OutlookEmailSenderError.failed(
                    sentCount: index,
                    totalCount: messages.count,
                    detail: error.localizedDescription
                )
            }
        }
    }

    private static func send(_ message: OutlookEmailMessage) throws {
        guard let script = NSAppleScript(source: OutlookAppleScript.sendMessageSource(for: message)) else {
            throw OutlookEmailSenderError.couldNotPrepareScript("The Outlook sending script could not be created.")
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            throw OutlookEmailSenderError.couldNotPrepareScript(errorMessage(in: errorInfo))
        }
        errorInfo = nil
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw OutlookEmailSenderError.couldNotPrepareScript(errorMessage(in: errorInfo))
        }
    }

    private static func errorMessage(in errorInfo: NSDictionary?) -> String {
        errorInfo?["NSAppleScriptErrorMessage"] as? String ?? "Microsoft Outlook did not accept the send request."
    }
}

private enum OutlookEmailSenderError: LocalizedError {
    case couldNotPrepareScript(String)
    case failed(sentCount: Int, totalCount: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .couldNotPrepareScript(let detail):
            return "Could not send email through Microsoft Outlook. If macOS asks for permission, allow Attendance Tracker to control Outlook in System Settings > Privacy & Security > Automation. \(detail)"
        case .failed(let sentCount, let totalCount, let detail):
            if sentCount == 0 {
                return "Outlook could not send any of the \(totalCount) emails. \(detail)"
            }
            return "Outlook stopped after confirming \(sentCount) of \(totalCount) emails. Check Outlook's Sent Items before retrying. \(detail)"
        }
    }
}
