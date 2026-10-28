import Foundation
import Observation
import OrganizadorCore

/// Downloads the user's iCal feed, keeps the last copy on disk for offline use,
/// and refreshes it every 15 minutes.
@MainActor
@Observable
final class CalendarFeed {
    static let refreshInterval: TimeInterval = 15 * 60

    private(set) var events: [ICSEvent] = []
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private var lastAttempt: Date?

    init(cacheURL: URL?) {
        self.cacheURL = cacheURL
        loadCache()
    }

    func occurrences(in window: DateInterval) -> [CalendarEvent] {
        CalendarExpansion.occurrences(of: events, in: window)
    }

    func refreshIfDue(urlString: String) {
        guard !urlString.isEmpty, !isSyncing else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.refreshInterval { return }
        refresh(urlString: urlString)
    }

    func refresh(urlString: String) {
        guard let url = Self.normalizedURL(urlString) else {
            errorMessage = "O link não parece um endereço válido. Use o \"endereço secreto no formato iCal\" do Google Agenda."
            return
        }
        lastAttempt = Date()
        isSyncing = true
        Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw CalendarFeedError.http(http.statusCode)
                }
                guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
                    throw CalendarFeedError.notCalendar
                }
                self?.apply(text: text, data: data)
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Forgets the feed, e.g. when the link is removed.
    func clear() {
        events = []
        lastSync = nil
        errorMessage = nil
        lastAttempt = nil
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
    }

    private func apply(text: String, data: Data) {
        events = ICSParser.parse(text)
        lastSync = Date()
        errorMessage = nil
        isSyncing = false
        if let cacheURL {
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func fail(_ error: Error) {
        isSyncing = false
        errorMessage = "Não foi possível atualizar a agenda: \(error.localizedDescription)"
    }

    private func loadCache() {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let text = String(data: data, encoding: .utf8)
        else { return }
        events = ICSParser.parse(text)
        lastSync = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date
    }

    /// Accepts https and webcal links.
    static func normalizedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("webcal://") {
            trimmed = "https://" + trimmed.dropFirst("webcal://".count)
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil
        else { return nil }
        return url
    }
}

enum CalendarFeedError: LocalizedError {
    case http(Int)
    case notCalendar

    var errorDescription: String? {
        switch self {
        case .http(let status): "o servidor respondeu com erro \(status). Confira se o link está certo."
        case .notCalendar: "o link não devolveu uma agenda no formato iCal."
        }
    }
}
