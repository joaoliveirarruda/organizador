import Foundation

/// Reads and writes `AppData` as one human-readable JSON file.
public struct JSONStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Organizador/data.json` on macOS.
    public static func defaultURL(appName: String = "Organizador") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("data.json")
    }

    /// Returns empty data when the file does not exist yet.
    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        return try Self.makeDecoder().decode(AppData.self, from: data)
    }

    public func save(_ appData: AppData) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.makeEncoder().encode(appData)
        try data.write(to: url, options: .atomic)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeFormatter(fractionalSeconds: true).string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = makeFormatter(fractionalSeconds: true).date(from: text)
                ?? makeFormatter(fractionalSeconds: false).date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Data inválida: \(text)"
            )
        }
        return decoder
    }

    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
