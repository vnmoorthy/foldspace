import Foundation
import Observation

// MARK: - Configuration
//
// The Galactic Registry is a Supabase project: one Postgres table, `public.events`, exposed through
// PostgREST at `<SUPABASE_URL>/rest/v1/events`. Row-level security lets the anon role INSERT and
// SELECT and nothing else (supabase/migrations/20260926000000_events.sql). The URL and anon key come
// from Secrets.plist via `Secrets`; with no credentials the registry is simply offline and the game
// plays exactly the same. Setup, schema and curl examples: supabase/README.md.
enum RegistryConfig {
    static let table = "events"
    /// Rows shown in feeds (HUD + docs/registry.html).
    static let recentLimit = 25
    /// Rows pulled per refresh; the stat tiles are computed in-app from this window.
    static let statsWindow = 500
    /// Per-request timeout. Short on purpose: the game never waits on the network.
    static let timeout: TimeInterval = 8
    /// Failed inserts are queued in memory (bounded) and retried on the next send or refresh.
    static let maxPending = 50
    /// UserDefaults key for the device-scoped callsign used while the save still says "COMMANDER".
    static let callsignKey = "foldspace.registry.callsign"
    static let placeholderCallsign = "COMMANDER"

    static var eventsEndpoint: String { "\(Secrets.supabaseURL)/rest/v1/\(table)" }
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

    /// Derives the tiles from a window of entries (newest first); `recent` keeps the first `recentLimit`.
    static func compute(from window: [RegistryEntry]) -> GalacticStats {
        GalacticStats(
            commanders: Set(window.map(\.callsign)).count,
            claimed: window.filter { $0.event == .claimed }.count,
            destroyed: window.filter { $0.event == .destroyed }.count,
            andromedaArrivals: window.filter { $0.event == .reachedAndromeda }.count,
            recent: Array(window.prefix(RegistryConfig.recentLimit))
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
    case notConfigured
    case badURL
    case http(Int, String)
    case badPayload

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase URL / anon key missing from Secrets.plist."
        case .badURL: return "Registry URL is malformed."
        case .http(let code, let body): return "Registry HTTP \(code)\(body.isEmpty ? "" : ": \(body)")"
        case .badPayload: return "Registry returned an unexpected payload."
        }
    }
}

// MARK: - Client

/// Talks to the Galactic Registry (Supabase PostgREST). Fully optional: every call degrades to
/// `isOnline == false` and the game keeps running offline. Local events are echoed into `stats`
/// immediately so the HUD feed reacts before (or without) the network.
@MainActor
@Observable
final class GalacticRegistry {
    var stats: GalacticStats?
    var isOnline: Bool
    var callsign: String

    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var pendingCount: Int = 0
    private(set) var isRefreshing = false

    /// Last fetched window (newest first) plus optimistic local echoes.
    @ObservationIgnored private var window: [RegistryEntry] = []
    @ObservationIgnored private var pending: [Payload] = []
    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Exactly the columns the anon INSERT accepts (`id` / `created_at` are server defaults).
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

    init(callsign: String) {
        self.callsign = Self.resolveCallsign(callsign)
        self.isOnline = Secrets.hasSupabase
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

    /// True when Secrets.plist carries a Supabase URL + anon key.
    var isConfigured: Bool { Secrets.hasSupabase }

    /// One-line HUD readout.
    var statusLine: String {
        if !Secrets.hasSupabase { return "REGISTRY OFFLINE · NO SUPABASE KEYS" }
        if !isOnline {
            return pendingCount > 0 ? "REGISTRY OFFLINE · \(pendingCount) QUEUED" : "REGISTRY OFFLINE"
        }
        if let s = stats { return "REGISTRY ONLINE · \(s.commanders) CMDR" }
        return "REGISTRY ONLINE"
    }

    // MARK: Callsign

    /// A save that still says "COMMANDER" gets a device-scoped callsign ("NOVA-4821"), generated once
    /// and kept in UserDefaults so the registry can tell commanders apart. Custom callsigns pass through.
    private static func resolveCallsign(_ requested: String) -> String {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.uppercased() != RegistryConfig.placeholderCallsign {
            return trimmed
        }
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: RegistryConfig.callsignKey), !saved.isEmpty {
            return saved
        }
        let generated = generateCallsign()
        defaults.set(generated, forKey: RegistryConfig.callsignKey)
        return generated
    }

    static func generateCallsign() -> String {
        let stars = ["NOVA", "VEGA", "LYRA", "RIGEL", "DENEB", "ALTAIR", "SPICA", "MIRA", "ATLAS", "HELIX", "ORION", "DRACO"]
        let star = stars.randomElement() ?? "NOVA"
        return "\(star)-\(Int.random(in: 1000...9999))"
    }

    // MARK: Record (fire-and-forget)

    /// Posts an event. Returns immediately; the game never waits on the network. The entry is echoed
    /// into the local feed at once; on failure it stays queued (bounded) and is retried by the next
    /// `record` or `refresh`.
    func record(_ event: RegistryEvent, body: String, energy: Int) {
        let payload = Payload(callsign: callsign, event: event.rawValue, body: body, energy: energy)
        echo(payload)
        guard Secrets.hasSupabase else {
            isOnline = false
            return
        }
        enqueue(payload)
        Task { [weak self] in
            await self?.flushPending()
        }
    }

    private func enqueue(_ payload: Payload) {
        pending.append(payload)
        if pending.count > RegistryConfig.maxPending {
            pending.removeFirst(pending.count - RegistryConfig.maxPending)
        }
        pendingCount = pending.count
    }

    /// Optimistic local echo so the HUD feed updates before the next refresh.
    private func echo(_ p: Payload) {
        guard let event = RegistryEvent(rawValue: p.event) else { return }
        let entry = RegistryEntry(id: "local-\(UUID().uuidString)", callsign: p.callsign, event: event,
                                  body: p.body, energy: p.energy,
                                  created_at: RegistryDates.string(from: Date()))
        window.insert(entry, at: 0)
        if window.count > RegistryConfig.statsWindow {
            window.removeLast(window.count - RegistryConfig.statsWindow)
        }
        stats = GalacticStats.compute(from: window)
    }

    // MARK: Refresh

    /// Flushes queued inserts, then pulls the latest `statsWindow` events and recomputes the tiles.
    func refresh() async {
        guard Secrets.hasSupabase else {
            isOnline = false
            lastError = RegistryError.notConfigured.localizedDescription
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flushPending()
        do {
            let rows = try await fetchWindow()
            window = rows
            stats = GalacticStats.compute(from: rows)
            markOnline()
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

    /// Posts queued payloads in order; stops at the first failure and leaves the rest queued.
    private func flushPending() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let next = pending.first {
            do {
                try await post(next)
                if !pending.isEmpty { pending.removeFirst() }
                pendingCount = pending.count
                markOnline()
            } catch {
                markOffline(error)
                return
            }
        }
    }

    private func markOnline() {
        isOnline = true
        lastError = nil
    }

    private func markOffline(_ error: Error) {
        isOnline = false
        lastError = error.localizedDescription
        Telemetry.breadcrumb("Registry offline: \(error.localizedDescription)", category: "registry")
    }

    // MARK: HTTP (Supabase PostgREST)

    private func fetchWindow() async throws -> [RegistryEntry] {
        guard var comps = URLComponents(string: RegistryConfig.eventsEndpoint) else { throw RegistryError.badURL }
        comps.queryItems = [
            URLQueryItem(name: "select", value: "id,callsign,event,body,energy,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(RegistryConfig.statsWindow)),
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
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.timeoutInterval = RegistryConfig.timeout
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw RegistryError.http(http.statusCode, snippet)
        }
    }

    /// PostgREST returns a bare JSON array of rows.
    private func decodeRows(_ data: Data) throws -> [RegistryEntry] {
        guard let rows = try? decoder.decode([RawRow].self, from: data) else { throw RegistryError.badPayload }
        return rows.compactMap(Self.entry(from:))
    }

    private static func entry(from raw: RawRow) -> RegistryEntry? {
        guard let id = raw.id, let callsign = raw.callsign, let body = raw.body,
              let rawEvent = raw.event, let event = RegistryEvent(rawValue: rawEvent) else { return nil }
        return RegistryEntry(id: id, callsign: callsign, event: event, body: body,
                             energy: raw.energy ?? 0, created_at: raw.created_at ?? "")
    }
}
