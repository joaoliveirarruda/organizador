import Foundation

/// One line read from a bank statement, before it becomes a transaction.
public struct StatementLine: Hashable, Sendable {
    public var date: Date
    public var amountCents: Int
    public var description: String
    /// Stable identity of the line, used to skip it when the same statement is imported again.
    public var key: String
}

public enum StatementImportError: Error, LocalizedError, Equatable {
    case unrecognized
    case missingColumns

    public var errorDescription: String? {
        switch self {
        case .unrecognized:
            "Não reconheci o arquivo. Use o extrato em OFX ou CSV exportado pelo banco."
        case .missingColumns:
            "O CSV precisa ter colunas de data e de valor (por exemplo \"Data\" e \"Valor\")."
        }
    }
}

/// Reads OFX and CSV bank statements.
public enum StatementImporter {
    /// Parses an OFX or CSV statement. `invertSigns` is for credit card CSVs that list purchases as positive.
    public static func parse(_ text: String, invertSigns: Bool = false, calendar: Calendar) throws -> [StatementLine] {
        let lines: [StatementLine]
        if text.range(of: "<OFX>", options: .caseInsensitive) != nil
            || text.range(of: "<STMTTRN>", options: .caseInsensitive) != nil {
            lines = parseOFX(text, calendar: calendar)
        } else {
            lines = try parseCSV(text, calendar: calendar)
        }
        guard invertSigns else { return lines }
        return lines.map { line in
            var copy = line
            copy.amountCents = -line.amountCents
            return copy
        }
    }

    /// Turns statement lines into new transactions, skipping lines already imported and
    /// reusing the category of earlier transactions with the same description.
    public static func newTransactions(
        from lines: [StatementLine],
        existing: [MoneyTransaction]
    ) -> (transactions: [MoneyTransaction], duplicates: Int) {
        let existingKeys = Set(existing.compactMap(\.importKey))
        var categoryByDescription: [String: UUID] = [:]
        for transaction in existing.sorted(by: { $0.date < $1.date }) {
            if let categoryID = transaction.categoryID {
                categoryByDescription[normalized(transaction.description)] = categoryID
            }
        }

        var result: [MoneyTransaction] = []
        var duplicates = 0
        for line in lines {
            if existingKeys.contains(line.key) {
                duplicates += 1
                continue
            }
            result.append(MoneyTransaction(
                date: line.date,
                amountCents: line.amountCents,
                description: line.description,
                categoryID: categoryByDescription[normalized(line.description)],
                importKey: line.key
            ))
        }
        return (result, duplicates)
    }

    // MARK: - OFX

    static func parseOFX(_ text: String, calendar: Calendar) -> [StatementLine] {
        var lines: [StatementLine] = []
        var occurrences: [String: Int] = [:]
        var searchStart = text.startIndex

        while let open = text.range(of: "<STMTTRN>", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            let rest = open.upperBound..<text.endIndex
            // OFX 1.x (SGML) often omits closing tags, so a block also ends at the next transaction.
            let ends = [
                text.range(of: "</STMTTRN>", options: .caseInsensitive, range: rest),
                text.range(of: "<STMTTRN>", options: .caseInsensitive, range: rest),
                text.range(of: "</BANKTRANLIST>", options: .caseInsensitive, range: rest),
            ].compactMap { $0 }
            let end = ends.min { $0.lowerBound < $1.lowerBound }
            let blockEnd = end?.lowerBound ?? text.endIndex
            let block = String(text[open.upperBound..<blockEnd])
            searchStart = blockEnd

            let fields = ofxFields(block)
            guard let dateText = fields["DTPOSTED"], let date = parseOFXDate(dateText, calendar: calendar),
                  let amountText = fields["TRNAMT"], let cents = parseOFXAmount(amountText)
            else { continue }
            let memo = fields["MEMO"].map(unescapeXML) ?? ""
            let name = fields["NAME"].map(unescapeXML) ?? ""
            let description = !memo.isEmpty ? memo : (!name.isEmpty ? name : "Transação")

            let key: String
            if let fitID = fields["FITID"], !fitID.isEmpty {
                key = "ofx:\(fitID)|\(dayString(date, calendar: calendar))|\(cents)"
            } else {
                key = fallbackKey(date: date, cents: cents, description: description, calendar: calendar, occurrences: &occurrences)
            }
            lines.append(StatementLine(date: date, amountCents: cents, description: description, key: key))
        }
        return lines
    }

    /// `<TAG>value` pairs inside a transaction block (first occurrence of each tag).
    private static func ofxFields(_ block: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "<([A-Za-z0-9.]+)>([^<\\r\\n]*)") else { return [:] }
        var fields: [String: String] = [:]
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        for match in regex.matches(in: block, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: block),
                  let valueRange = Range(match.range(at: 2), in: block)
            else { continue }
            let tag = block[tagRange].uppercased()
            let value = block[valueRange].trimmingCharacters(in: .whitespaces)
            if fields[tag] == nil, !value.isEmpty { fields[tag] = value }
        }
        return fields
    }

    /// "20261028120000[-3:BRT]" or "20261028" → that day.
    static func parseOFXDate(_ text: String, calendar: Calendar) -> Date? {
        let digits = Array(text.prefix(8))
        guard digits.count == 8, let year = Int(String(digits[0..<4])),
              let month = Int(String(digits[4..<6])), let day = Int(String(digits[6..<8]))
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// OFX uses "." for decimals, but some banks write ",".
    static func parseOFXAmount(_ text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized) else { return nil }
        return Int((value * 100).rounded())
    }

    private static func unescapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - CSV

    static func parseCSV(_ text: String, calendar: Calendar) throws -> [StatementLine] {
        let rows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerRow = rows.first else { throw StatementImportError.unrecognized }

        let candidates: [Character] = [";", ",", "\t"]
        let delimiter = candidates.max { a, b in
            headerRow.filter { $0 == a }.count < headerRow.filter { $0 == b }.count
        } ?? ","
        let header = splitCSVRow(headerRow, delimiter: delimiter).map(folded)

        func column(_ names: [String]) -> Int? {
            header.firstIndex { cell in names.contains { cell.contains($0) } }
        }
        guard let dateColumn = column(["data", "date"]),
              let amountColumn = column(["valor", "amount", "value", "quantia"])
        else { throw StatementImportError.missingColumns }
        let descriptionColumn = column(["descri", "hist", "title", "titulo", "memo", "lancamento", "estabelecimento", "detalhe"])

        var lines: [StatementLine] = []
        var occurrences: [String: Int] = [:]
        for row in rows.dropFirst() {
            let cells = splitCSVRow(row, delimiter: delimiter)
            guard cells.indices.contains(dateColumn), cells.indices.contains(amountColumn),
                  let date = parseCSVDate(cells[dateColumn], calendar: calendar),
                  let cents = parseAmountCents(cells[amountColumn])
            else { continue }
            let description = descriptionColumn
                .flatMap { cells.indices.contains($0) ? cells[$0].trimmingCharacters(in: .whitespaces) : nil }
                .flatMap { $0.isEmpty ? nil : $0 } ?? "Transação"
            let key = fallbackKey(date: date, cents: cents, description: description, calendar: calendar, occurrences: &occurrences)
            lines.append(StatementLine(date: date, amountCents: cents, description: description, key: key))
        }
        return lines
    }

    static func splitCSVRow(_ row: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var cell = ""
        var inQuotes = false
        var previousWasQuote = false
        for char in row {
            if char == "\"" {
                if inQuotes {
                    inQuotes = false
                    previousWasQuote = true
                } else if previousWasQuote {
                    // An escaped quote ("") inside a quoted cell.
                    cell.append("\"")
                    inQuotes = true
                    previousWasQuote = false
                } else {
                    inQuotes = true
                }
                continue
            }
            previousWasQuote = false
            if char == delimiter && !inQuotes {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(char)
            }
        }
        cells.append(cell)
        return cells
    }

    /// "28/10/2026", "28/10/26", "2026-10-28" (a time after the date is ignored).
    static func parseCSVDate(_ text: String, calendar: Calendar) -> Date? {
        let token = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = token.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let year: Int
        let month: Int
        let day: Int
        if parts[0] > 31 {
            year = parts[0]
            month = parts[1]
            day = parts[2]
        } else {
            day = parts[0]
            month = parts[1]
            year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Reads "R$ 1.234,56", "-45,90", "1,234.56", "(12.00)" and similar into cents.
    public static func parseAmountCents(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if value.hasPrefix("(") && value.hasSuffix(")") {
            negative = true
            value = String(value.dropFirst().dropLast())
        }
        value = value
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        if value.hasPrefix("-") {
            negative.toggle()
            value.removeFirst()
        } else if value.hasPrefix("+") {
            value.removeFirst()
        }

        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Whichever separator comes last is the decimal one.
            value = comma > dot
                ? value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : value.replacingOccurrences(of: ",", with: "")
        case (.some, nil):
            value = value.filter { $0 == "," }.count > 1
                ? value.replacingOccurrences(of: ",", with: "")
                : value.replacingOccurrences(of: ",", with: ".")
        case let (nil, dot?):
            let decimals = value.distance(from: dot, to: value.endIndex) - 1
            if value.filter({ $0 == "." }).count > 1 || decimals == 3 {
                value = value.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }

        guard !value.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "." }), let number = Double(value) else {
            return nil
        }
        let cents = Int((number * 100).rounded())
        return negative ? -cents : cents
    }

    // MARK: - Helpers

    /// Key for lines without a bank id: day, amount and description, plus a counter so two
    /// identical purchases on the same day stay separate.
    private static func fallbackKey(
        date: Date,
        cents: Int,
        description: String,
        calendar: Calendar,
        occurrences: inout [String: Int]
    ) -> String {
        let base = "\(dayString(date, calendar: calendar))|\(cents)|\(normalized(description))"
        let count = occurrences[base, default: 0]
        occurrences[base] = count + 1
        return "line:\(base)#\(count)"
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Lowercase description without accents, digits or punctuation, for matching similar lines.
    static func normalized(_ text: String) -> String {
        let letters = folded(text).map { $0.isLetter ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }
}
