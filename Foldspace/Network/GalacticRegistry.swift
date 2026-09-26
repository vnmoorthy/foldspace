import Foundation
import Observation

// MARK: - Configuration
//
// The Galactic Registry is a Butterbase app. Its `events` table is exposed through the
// auto-generated REST API at `<host>/v1/<appID>/<table>` (see backend/README.md for the
// schema and curl examples). The app runs in `public` access mode, so anonymous inserts and
// selects need no API key, anon token or Authorization header.
//
// HOW TO POINT THE GAME AT ANOTHER APP: copy the `app_id` returned by Butterbase `init_app`
// into `appID` below (and update `dashboardURL`). That is the only edit needed. Change `host`
// only for a self-hosted Butterbase. If you ever switch the app to `authenticated` access
// mode, put a bearer token into `authorizationHeader` ("Bearer bb_sk_...").
enum RegistryConfig {
    static let host = "https://api.butterbase.ai"
    static let appID = "app_a7c3jfpp8stm"
    static let table = "events"
    static let dashboardURL = "https://dragnet.butterbase.dev"
    static let authorizationHeader: String? = nil
    /// How many recent events `refresh()` pulls (and the dashboard shows).
    static let recentLimit = 25
    /// Per-request timeout. Short on purpose: the game never waits on the network.
    static let timeout: TimeInterval = 8
    /// Failed inserts are queued in memory and retried on the next `refresh()`.
    static let maxPending = 50

    static var apiBase: String { "\(host)/v1/\(appID)" }
    static var eventsEndpoint: String { "\(apiBase)/\(table)" }
}

// MARK: - Wire types (must match the `events` table)

enum RegistryEvent: String, Codable, Sendable {
    case claimed, destroyed, warped, driveAssembled, coreSample, passedBlackHole, reachedAndromeda
}

extension RegistryEvent {
    /// Short HUD label.
    var label: String {
        switch self {
        case .claimed: return "CLAIMED"
        case .destroyed: return "DESTROYED"
        case .warped: return "WARPED"
        case .driveAssembled: return "DRIVE ONLINE"
        case .coreSample: return "CORE SAMPLE"
        case .passedBlackHole: return "SLINGSHOT"
        case .reachedAndromeda: return "ANDROMEDA"
        }
    }

    /// SF Symbol for feeds.
    var symbol: String {
        switch self {
        case .claimed: return "flag.fill"
        case .destroyed: return "burst.fill"
        case .warped: return "arrow.triangle.swap"
        case .driveAssembled: return "gearshape.2.fill"
        case .coreSample: return "sun.max.fill"
        case .passedBlackHole: return "circle.circle"
        case .reachedAndromeda: return "sparkles"
        }
    }

    /// Past-tense phrase for log lines: "NOVA-7 planted a beacon on earth".
    var verb: String {
        switch self {
        case .claimed: return "planted a beacon on"
        case .destroyed: return "shattered"
        case .warped: return "folded space to"
        case .driveAssembled: return "assembled the warp drive at"
        case .coreSample: return "sampled the core of"
        case .passedBlackHole: return "slingshot around"
        case .reachedAndromeda: return "reached"
        }
    }
}

struct RegistryEntry: Codable, Identifiable, Sendable {
    var id: String
    var callsign: String
    var event: RegistryEvent
    var body: String
    var energy: Int
    var created_at: String
}

extension RegistryEntry {
    var date: Date? { RegistryDates.parse(created_at) }
    /// "now", "42 sec. ago", "3 hr. ago" — for feeds.
    var relativeTime: String {
        guard let d = date else { return "—" }
        if Date().timeIntervalSince(d) < 5 { return "now" }
        return RegistryDates.relative.localizedString(for: d, relativeTo: Date())
    }
    var headline: String { "\(callsign) \(event.verb) \(body)" }
}

struct GalacticStats: Codable, Sendable {
    var commanders: Int
    var claimed: Int
    var destroyed: Int
    var andromedaArrivals: Int
    var recent: [RegistryEntry]
}

extension GalacticStats {
    static let empty = GalacticStats(commanders: 0, claimed: 0, destroyed: 0, andromedaArrivals: 0, recent: [])

    /// Derives the tiles from a page of entries (the latest `RegistryConfig.recentLimit`).
    static func compute(from entries: [RegistryEntry]) -> GalacticStats {
        GalacticStats(
            commanders: Set(entries.map(\.callsign)).count,
            claimed: entries.filter { $0.event == .claimed }.count,
            destroyed: entries.filter { $0.event == .destroyed }.count,
            andromedaArrivals: entries.filter { $0.event == .reachedAndromeda }.count,
            recent: entries
        )
    }
}

enum RegistryDates {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Accepts "2026-09-26T10:00:00Z", "...00.123Z" and Postgres-style "...00.123456+00:00".
    static func parse(_ s: String) -> Date? {
        if let d = fractional.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        // Trim a fractional part of arbitrary length, keep the zone designator.
        if let dot = s.firstIndex(of: ".") {
            let tail = s[dot...]
            if let zone = tail.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                return plain.date(from: String(s[..<dot]) + String(tail[zone...]))
            }
        }
        return nil
    }

    static func string(from date: Date) -> String { fractional.string(from: date) }
}

enum RegistryError: LocalizedError {
    case badURL
    case http(Int, String)
    case badPayload

    var errorDescription: String? {
        switch self {
        case .badURL: return "Registry URL is malformed."
        case .http(let code, let body): return "Registry HTTP \(code)\(body.isEmpty ? "" : ": \(body)")"
        case .badPayload: return "Registry returned an unexpected payload."
        }
    }
}

// MARK: - Client

/// Talks to the Galactic Registry backend. Fully optional: every call degrades to
/// `isOnline == false` and the game keeps running offline.
@MainActor
@Observable
final class GalacticRegistry {
    var stats: GalacticStats?
    var isOnline: Bool = true
    var callsign: String

    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var pendingCount: Int = 0
    private(set) var isRefreshing = false

    @ObservationIgnored private var pending: [Payload] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private struct Payload: Codable, Sendable {
        var callsign: String
        var event: String
        var body: String
        var energy: Int
    }

    /// Lenient row shape: unknown events or odd id types never break the whole page.
    private struct RawRow: Decodable {
        var id: String?
        var callsign: String?
        var event: String?
        var body: String?
        var energy: Int?
        var created_at: String?

        private enum Keys: String, CodingKey { case id, callsign, event, body, energy, created_at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if let s = try? c.decode(String.self, forKey: .id) {
                id = s
            } else if let n = try? c.decode(Int.self, forKey: .id) {
                id = String(n)
            }
            callsign = try? c.decode(String.self, forKey: .callsign)
            event = try? c.decode(String.self, forKey: .event)
            body = try? c.decode(String.self, forKey: .body)
            if let n = try? c.decode(Int.self, forKey: .energy) {
                energy = n
            } else if let d = try? c.decode(Double.self, forKey: .energy) {
                energy = Int(d)
            }
            created_at = try? c.decode(String.self, forKey: .created_at)
        }
    }

    private struct Envelope: Decodable {
        var data: [RawRow]?
        var rows: [RawRow]?
        var items: [RawRow]?
    }

    init(callsign: String) {
        self.callsign = callsign
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = RegistryConfig.timeout
        cfg.timeoutIntervalForResource = RegistryConfig.timeout * 2
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    deinit {
        pollTask?.cancel()
    }

    /// One-line HUD readout.
    var statusLine: String {
        if !isOnline {
            return pendingCount > 0 ? "REGISTRY OFFLINE · \(pendingCount) QUEUED" : "REGISTRY OFFLINE"
        }
        if let s = stats { return "REGISTRY ONLINE · \(s.commanders) CMDR" }
        return "REGISTRY ONLINE"
    }

    // MARK: Record (fire-and-forget)

    /// Posts an event. Returns immediately; the game never waits on the network.
    /// On failure the event is queued (bounded) and retried by the next `refresh()`.
    func record(_ event: RegistryEvent, body: String, energy: Int) {
        let payload = Payload(callsign: callsign, event: event.rawValue, body: body, energy: energy)
        Task { [weak self] in
            await self?.send(payload)
        }
    }

    private func send(_ payload: Payload) async {
        do {
            try await post(payload)
            isOnline = true
            lastError = nil
            echo(payload)
        } catch {
            markOffline(error)
            if pending.count < RegistryConfig.maxPending {
                pending.append(payload)
                pendingCount = pending.count
            }
        }
    }

    /// Optimistic local echo so the HUD feed updates before the next refresh.
    private func echo(_ p: Payload) {
        guard let event = RegistryEvent(rawValue: p.event) else { return }
        var recent = stats?.recent ?? []
        recent.insert(RegistryEntry(id: UUID().uuidString, callsign: p.callsign, event: event,
                                    body: p.body, energy: p.energy,
                                    created_at: RegistryDates.string(from: Date())), at: 0)
        if recent.count > RegistryConfig.recentLimit {
            recent.removeLast(recent.count - RegistryConfig.recentLimit)
        }
        stats = GalacticStats.compute(from: recent)
    }

    // MARK: Refresh

    /// Flushes queued inserts, then pulls the latest `recentLimit` events and recomputes stats.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flushPending()
        do {
            let entries = try await fetchRecent()
            stats = GalacticStats.compute(from: entries)
            isOnline = true
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            markOffline(error)
        }
    }

    /// Periodic refresh for the docked / outer-display screens. Cancel with `stopPolling()`.
    func startPolling(every interval: TimeInterval = 10) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: UInt64(max(1, interval) * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func flushPending() async {
        while let next = pending.first {
            do {
                try await post(next)
                pending.removeFirst()
                pendingCount = pending.count
            } catch {
                markOffline(error)
                return
            }
        }
    }

    private func markOffline(_ error: Error) {
        isOnline = false
        lastError = error.localizedDescription
    }

    // MARK: HTTP

    private func fetchRecent() async throws -> [RegistryEntry] {
        guard var comps = URLComponents(string: RegistryConfig.eventsEndpoint) else { throw RegistryError.badURL }
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,callsign,event,body,energy,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(RegistryConfig.recentLimit)),
        ]
        guard let url = comps.url else { throw RegistryError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        return try decodeRows(data)
    }

    private func post(_ payload: Payload) async throws {
        guard let url = URL(string: RegistryConfig.eventsEndpoint) else { throw RegistryError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        applyHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = RegistryConfig.authorizationHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw RegistryError.http(http.statusCode, snippet)
        }
    }

    /// Accepts a bare JSON array or `{ "data" | "rows" | "items": [...] }`.
    private func decodeRows(_ data: Data) throws -> [RegistryEntry] {
        let rows: [RawRow]
        if let array = try? decoder.decode([RawRow].self, from: data) {
            rows = array
        } else if let env = try? decoder.decode(Envelope.self, from: data),
                  let inner = env.data ?? env.rows ?? env.items {
            rows = inner
        } else {
            throw RegistryError.badPayload
        }
        return rows.compactMap(Self.entry(from:))
    }

    private static func entry(from raw: RawRow) -> RegistryEntry? {
        guard let id = raw.id, let callsign = raw.callsign, let body = raw.body,
              let rawEvent = raw.event, let event = RegistryEvent(rawValue: rawEvent) else { return nil }
        return RegistryEntry(id: id, callsign: callsign, event: event, body: body,
                             energy: raw.energy ?? 0, created_at: raw.created_at ?? "")
    }
}
