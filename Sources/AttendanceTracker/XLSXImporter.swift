import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct StudentNameRecord: Equatable {
    let surname: String
    let forename: String

    var displayName: String {
        let surname = AttendanceEmailTemplate.displayName(surname)
        let forename = AttendanceEmailTemplate.displayName(forename)
        if surname.isEmpty { return forename }
        if forename.isEmpty { return surname }
        return "\(surname), \(forename)"
    }

    var emailName: String {
        displayName
    }
}

enum XLSXImporter {
    static func parseNames(at url: URL) throws -> [String: StudentNameRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XLSXImporterError.workbookNotFound
        }
        let listing = try runUnzip(["-Z", "-1", url.path])
        let members = Set(String(decoding: listing, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init))
        let worksheetPath = "xl/worksheets/sheet1.xml"
        guard members.contains(worksheetPath) else {
            throw XLSXImporterError.missingWorksheet
        }
        let sharedStringsXML = members.contains("xl/sharedStrings.xml")
            ? try runUnzip(["-p", url.path, "xl/sharedStrings.xml"])
            : nil
        let worksheetXML = try runUnzip(["-p", url.path, worksheetPath])
        return try parseNames(sharedStringsXML: sharedStringsXML, worksheetXML: worksheetXML)
    }

    static func parseNames(
        sharedStringsXML: Data?,
        worksheetXML: Data
    ) throws -> [String: StudentNameRecord] {
        let sharedStrings = try sharedStringsXML.map(parseSharedStrings) ?? []
        let rows = try parseWorksheet(worksheetXML, sharedStrings: sharedStrings)
        guard let headerIndex = rows.firstIndex(where: { row in
            let headers = row.values.map(normalize)
            return headers.contains("studentno") && headers.contains("forename")
        }) else {
            throw XLSXImporterError.missingColumns
        }
        let header = rows[headerIndex]
        guard let studentNumberColumn = uniqueColumn("studentno", in: header),
              let forenameColumn = uniqueColumn("forename", in: header) else {
            throw XLSXImporterError.missingColumns
        }
        let surnameColumn = uniqueColumn("surname", in: header)

        var records: [String: StudentNameRecord] = [:]
        for (index, row) in rows.enumerated() where index > headerIndex {
            guard row.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            guard let rawNumber = row[studentNumberColumn]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawNumber.isEmpty else {
                throw XLSXImporterError.missingStudentNumber(row: index + 1)
            }
            guard let forename = row[forenameColumn]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !forename.isEmpty else {
                continue
            }
            guard records[rawNumber] == nil else {
                throw XLSXImporterError.duplicateStudentNumber(rawNumber)
            }
            let surname = surnameColumn.flatMap { row[$0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            records[rawNumber] = StudentNameRecord(surname: surname, forename: forename)
        }
        guard !records.isEmpty else {
            throw XLSXImporterError.noNames
        }
        return records
    }

    private static func runUnzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw XLSXImporterError.couldNotReadWorkbook(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XLSXImporterError.couldNotReadWorkbook(
                String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return data
    }

    private static func parseSharedStrings(_ data: Data) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XLSXImporterError.invalidXML(parser.parserError?.localizedDescription ?? "Invalid shared strings data.")
        }
        return delegate.strings
    }

    private static func parseWorksheet(_ data: Data, sharedStrings: [String]) throws -> [[Int: String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XLSXImporterError.invalidXML(parser.parserError?.localizedDescription ?? "Invalid worksheet data.")
        }
        if let invalidSharedString = delegate.invalidSharedStringIndex {
            throw XLSXImporterError.invalidXML("Invalid shared string index \(invalidSharedString).")
        }
        return delegate.rows
    }

    private static func uniqueColumn(_ name: String, in row: [Int: String]) -> Int? {
        let matches = row.filter { normalize($0.value) == name }.map(\.key)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    fileprivate static func columnIndex(from reference: String) -> Int? {
        var index = 0
        var foundLetter = false
        for scalar in reference.unicodeScalars {
            let value = scalar.value
            guard (65...90).contains(value) || (97...122).contains(value) else { break }
            let uppercase = value >= 97 ? value - 32 : value
            index = index * 26 + Int(uppercase - 64)
            foundLetter = true
        }
        return foundLetter ? index - 1 : nil
    }
}

private enum XLSXImporterError: LocalizedError {
    case workbookNotFound
    case missingWorksheet
    case missingColumns
    case missingStudentNumber(row: Int)
    case duplicateStudentNumber(String)
    case noNames
    case invalidXML(String)
    case couldNotReadWorkbook(String)

    var errorDescription: String? {
        switch self {
        case .workbookNotFound:
            return "Names.xlsx was not found in ~/Library/Application Support/AttendanceTracker/."
        case .missingWorksheet:
            return "Names.xlsx does not contain a first worksheet."
        case .missingColumns:
            return "The first worksheet must contain Student No and Forename columns."
        case .missingStudentNumber(let row):
            return "Names.xlsx row \(row) is missing a Student No value."
        case .duplicateStudentNumber(let number):
            return "Student No \(number) appears more than once in Names.xlsx."
        case .noNames:
            return "Names.xlsx does not contain any student forenames."
        case .invalidXML(let detail):
            return "Could not parse Names.xlsx: \(detail)"
        case .couldNotReadWorkbook(let detail):
            return "Could not read Names.xlsx: \(detail)"
        }
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var currentString: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            currentString = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentString?.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "si", let currentString else { return }
        strings.append(currentString)
        self.currentString = nil
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private(set) var rows: [[Int: String]] = []
    private(set) var invalidSharedStringIndex: String?
    private var currentRow: [Int: String]?
    private var currentColumn: Int?
    private var currentCellType = ""
    private var currentCellText = ""
    private var isReadingText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRow = [:]
        case "c":
            currentColumn = attributeDict["r"].flatMap(XLSXImporter.columnIndex(from:))
            currentCellType = attributeDict["t"] ?? ""
            currentCellText = ""
        case "v", "t":
            isReadingText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingText {
            currentCellText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v", "t":
            isReadingText = false
        case "c":
            if let currentColumn, var currentRow {
                if currentCellType == "s" {
                    if let index = Int(currentCellText), sharedStrings.indices.contains(index) {
                        currentRow[currentColumn] = sharedStrings[index]
                    } else {
                        invalidSharedStringIndex = currentCellText
                    }
                } else {
                    currentRow[currentColumn] = currentCellText
                }
                self.currentRow = currentRow
            }
            currentColumn = nil
            currentCellType = ""
            currentCellText = ""
        case "row":
            if let currentRow {
                rows.append(currentRow)
            }
            currentRow = nil
        default:
            break
        }
    }
}
