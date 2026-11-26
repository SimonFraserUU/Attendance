import Foundation

struct OutlookEmailMessage: Sendable {
    let recipient: String
    let subject: String
    let body: String
}

enum OutlookAppleScript {
    static func sendMessageSource(for message: OutlookEmailMessage) -> String {
        """
        tell application id "com.microsoft.Outlook"
            set outgoingMessage to make new outgoing message with properties {subject:\(stringExpression(message.subject)), plain text content:\(stringExpression(message.body))}
            make new to recipient at outgoingMessage with properties {email address:{address:\(stringExpression(message.recipient))}}
            send outgoingMessage
        end tell
        """
    }

    private static func stringExpression(_ value: String) -> String {
        var expressions: [String] = []
        var literal = ""

        func appendLiteral() {
            guard !literal.isEmpty else { return }
            let escaped = literal
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            expressions.append("\"\(escaped)\"")
            literal = ""
        }

        for character in value {
            switch character {
            case "\r":
                appendLiteral()
                expressions.append("return")
            case "\n":
                appendLiteral()
                expressions.append("linefeed")
            case "\t":
                appendLiteral()
                expressions.append("tab")
            default:
                literal.append(character)
            }
        }
        appendLiteral()
        return expressions.isEmpty ? "\"\"" : expressions.joined(separator: " & ")
    }
}
