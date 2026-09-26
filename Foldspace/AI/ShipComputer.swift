import Foundation
import Observation

/// One line of the ship-computer transcript.
struct ShipLine: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    enum Role { case ship, commander }
}

enum ShipComputerError: LocalizedError {
    case badURL
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .badURL: return "OpenAI endpoint URL is malformed."
        case .http(let code, let message): return "OpenAI HTTP \(code)\(message.isEmpty ? "" : ": \(message)")"
        case .emptyReply: return "OpenAI returned no text."
        }
    }
}

/// The ship computer. Narrates arrivals, answers the commander and writes the final log.
///
/// Online it calls OpenAI chat completions (`Secrets.openAIModel`) with a strict system prompt and the
/// body's real blurb + facts as the only source material. Offline — no key, no network, an API error,
/// or the 12-second timeout — it speaks with a deterministic voice built from the same facts, so the
/// panel always answers and nothing in the game waits on the network.
@MainActor
@Observable
final class ShipComputer {
    var transcript: [ShipLine] = []
    /// True while any request is in flight (the panel disables ASK / NARRATE).
    var isThinking: Bool { inFlight > 0 }
    /// Set by `commandersLog(save:)`; shown on the Andromeda finale.
    private(set) var commandersLogText: String?
    /// Where the most recent line came from.
    private(set) var lastSource: Source = .offline

    enum Source { case openAI, offline }

    private var inFlight = 0
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private static let endpoint = "https://api.openai.com/v1/chat/completions"
    private static let timeout: TimeInterval = 12
    private static let maxLines = 24

    static let systemPrompt = """
    You are the ship computer of FOLDSPACE, a spacecraft whose hinge folds space. Address the commander \
    in a terse, precise voice: at most two short sentences, scientifically accurate, no exclamation marks, \
    no emoji. Never invent numbers, names or facts — use only the facts provided in the message. If the \
    question cannot be answered from those facts, say so in one sentence.
    """

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Self.timeout
        cfg.timeoutIntervalForResource = Self.timeout
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// True when an OpenAI key is configured (the offline voice is used otherwise).
    var isOnline: Bool { Secrets.hasOpenAI }

    /// Caption for the console panel.
    var statusLine: String {
        Secrets.hasOpenAI ? "OPENAI · \(Secrets.openAIModel.uppercased())" : "OFFLINE VOICE · NO API KEY"
    }

    // MARK: - Verbs

    /// Two sentences about the body we just reached. Bound to the NARRATE button.
    func narrateArrival(body: CelestialBody, system: StarSystem, act: Act) async {
        guard !isThinking else { return }
        let location = system.id == SystemID.sol
            ? "in the Solar System"
            : "in the \(system.name) system, \(system.formattedDistance) from Sol"
        let prompt = "We have just established orbit around \(body.name) \(location), during \(act.title). "
            + "Narrate the arrival for the commander in at most two sentences, using only the facts below.\n\n"
            + factSheet(body: body, system: system)
        let fallback = Self.offlineArrival(body: body, system: system)
        await speak(prompt: prompt, fallback: fallback)
    }

    /// Answers a free-text question about the current body. Bound to the ASK field.
    func answer(_ question: String, body: CelestialBody, system: StarSystem) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        append(.commander, q)
        let prompt = "The commander asks: \"\(q)\"\n"
            + "We are in orbit around \(body.name) in the \(system.name) system. "
            + "Answer in at most two sentences using only the facts below; if they do not cover it, say so.\n\n"
            + factSheet(body: body, system: system)
        let fallback = Self.offlineAnswer(to: q, body: body, system: system)
        await speak(prompt: prompt, fallback: fallback)
    }

    /// The commander's log for the Andromeda finale. Result lands in `commandersLogText`.
    func commandersLog(save: SaveData) async {
        let claimed = save.claimed.count
        let destroyed = save.destroyed.count
        let years = Int(save.earthYearsElapsed.rounded())
        let prompt = "Write the commander's log entry for arriving in the Andromeda Galaxy (M31, about 2.5 million "
            + "light-years from Earth) in at most two sentences, addressed to Commander \(save.callsign). "
            + "Facts: beacons planted on \(claimed) world\(claimed == 1 ? "" : "s"); "
            + "\(destroyed) world\(destroyed == 1 ? "" : "s") destroyed with the Nova Lance; "
            + "\(save.energy) energy in reserve; \(years) Earth years elapsed through time dilation at Sagittarius A*; "
            + "stellar core sample \(save.solarCoreSample ? "secured" : "not taken"); "
            + "Sagittarius A* slingshot \(save.passedSagittariusA ? "completed" : "not attempted"). "
            + "Use only these numbers."
        let fallback = Self.offlineLog(save: save)
        inFlight += 1
        defer { inFlight -= 1 }
        let text = await complete(prompt: prompt) ?? fallback
        commandersLogText = text
        append(.ship, text)
    }

    func clearTranscript() {
        transcript.removeAll()
    }

    // MARK: - Pipeline

    private func speak(prompt: String, fallback: String) async {
        inFlight += 1
        defer { inFlight -= 1 }
        let text = await complete(prompt: prompt) ?? fallback
        append(.ship, text)
    }

    /// nil means "use the offline voice" — no key, or the request failed.
    private func complete(prompt: String) async -> String? {
        guard Secrets.hasOpenAI else {
            lastSource = .offline
            return nil
        }
        do {
            let text = try await requestCompletion(prompt: prompt)
            lastSource = .openAI
            return text
        } catch {
            lastSource = .offline
            Telemetry.capture(error, context: "shipcomputer.openai")
            return nil
        }
    }

    private func append(_ role: ShipLine.Role, _ text: String) {
        transcript.append(ShipLine(role: role, text: text))
        if transcript.count > Self.maxLines {
            transcript.removeFirst(transcript.count - Self.maxLines)
        }
    }

    // MARK: - OpenAI chat completions

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    /// Optionals are omitted from the JSON when nil (synthesized `encodeIfPresent`).
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        var temperature: Double?
        var max_completion_tokens: Int?
        var reasoning_effort: String?
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String?
        }
        let error: APIError?
    }

    private func requestCompletion(prompt: String) async throws -> String {
        guard let url = URL(string: Self.endpoint) else { throw ShipComputerError.badURL }
        let model = Secrets.openAIModel
        var body = ChatRequest(model: model, messages: [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(role: "user", content: prompt),
        ])
        body.max_completion_tokens = 160
        if Self.isReasoningModel(model) {
            // GPT-5 / o-series reject a non-default temperature; keep them fast instead.
            body.reasoning_effort = "low"
        } else {
            body.temperature = 0.6
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let apiMessage = (try? decoder.decode(APIErrorEnvelope.self, from: data))?.error?.message
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw ShipComputerError.http(http.statusCode, apiMessage ?? snippet)
        }
        let reply = try decoder.decode(ChatResponse.self, from: data)
        let raw = reply.choices.first?.message.content ?? ""
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ShipComputerError.emptyReply }
        return Self.clampSentences(content, max: 2)
    }

    /// GPT-5 (except gpt-5-chat) and the o-series are reasoning models with fixed sampling.
    static func isReasoningModel(_ model: String) -> Bool {
        let m = model.lowercased()
        if m.hasPrefix("gpt-5") { return !m.contains("chat") }
        return m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4")
    }

    /// Keeps the first `max` sentences. A period followed by a digit ("4.3 million") is not a boundary.
    static func clampSentences(_ text: String, max: Int) -> String {
        let chars = Array(text)
        var out = ""
        var count = 0
        for (i, ch) in chars.enumerated() {
            out.append(ch)
            guard ch == "." || ch == "!" || ch == "?" else { continue }
            let atEnd = i + 1 >= chars.count
            if atEnd || chars[i + 1] == " " || chars[i + 1] == "\n" {
                count += 1
                if count >= max { break }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fact sheet (the only thing the model may use)

    private func factSheet(body: CelestialBody, system: StarSystem) -> String {
        var lines: [String] = []
        lines.append("FACTS ABOUT \(body.name.uppercased()) (\(Self.kindLabel(body))):")
        lines.append("- Summary: \(body.blurb)")
        for fact in body.facts { lines.append("- \(fact)") }
        if body.kind == .star {
            lines.append(String(format: "- Radius: %.2f solar radii", body.radiusEarths / 109.2))
        } else if body.isPlanetLike {
            lines.append(String(format: "- Radius: %.2f Earth radii", body.radiusEarths))
        }
        if let mass = body.massEarths { lines.append(String(format: "- Mass: %.6g Earth masses", mass)) }
        if let temp = body.temperatureK { lines.append("- Temperature: \(Int(temp)) K") }
        if let days = body.orbitDays { lines.append(String(format: "- Orbital period: %.1f days", days)) }
        if body.habitable { lines.append("- Flagged as a habitable-zone world") }
        lines.append("- Star system: \(system.name), \(system.formattedDistance) from Sol. \(system.lore)")
        return lines.joined(separator: "\n")
    }

    static func kindLabel(_ body: CelestialBody) -> String {
        switch body.kind {
        case .star: return "star"
        case .planet: return "planet"
        case .dwarfPlanet: return "dwarf planet"
        case .blackHole: return "black hole"
        case .galaxy: return "galaxy"
        }
    }

    // MARK: - Offline voice (deterministic, facts only)

    static func offlineArrival(body: CelestialBody, system: StarSystem) -> String {
        let location = system.id == SystemID.sol ? "" : " · \(system.formattedDistance) from Sol"
        let fact = body.facts.first ?? body.blurb
        return "Orbit established: \(body.name)\(location). \(fact)"
    }

    static func offlineAnswer(to question: String, body: CelestialBody, system: StarSystem) -> String {
        let words = Set(tokens(question))
        func asks(_ any: [String]) -> Bool { any.contains { words.contains($0) } }

        // Direct readouts for the numbers we hold.
        if asks(["temperature", "temp", "hot", "cold", "warm", "kelvin", "heat"]), let t = body.temperatureK {
            return "\(body.name) registers about \(Int(t)) K. \(body.facts.first ?? body.blurb)"
        }
        if asks(["mass", "massive", "heavy", "weigh", "weight"]), let m = body.massEarths {
            return "\(body.name) masses about \(formatNumber(m)) Earth masses. \(body.blurb)"
        }
        if asks(["radius", "size", "big", "large", "diameter", "wide", "small"]) {
            if body.kind == .star {
                return "\(body.name) spans about \(String(format: "%.2f", body.radiusEarths / 109.2)) solar radii. \(body.blurb)"
            }
            if body.isPlanetLike {
                return "\(body.name) has a radius of about \(String(format: "%.2f", body.radiusEarths)) Earth radii. \(body.blurb)"
            }
        }
        if asks(["orbit", "year", "period", "day", "days", "revolve"]), let d = body.orbitDays {
            let period = d >= 365 ? String(format: "%.1f Earth years", d / 365.25) : String(format: "%.0f days", d)
            return "\(body.name) completes an orbit every \(period). \(body.facts.first ?? body.blurb)"
        }
        if asks(["distance", "far", "away", "home", "sol", "earth", "light", "ly"]) {
            if system.id == SystemID.sol {
                return "We are still in the Solar System, the home system. \(body.blurb)"
            }
            return "\(system.name) lies \(system.formattedDistance) from Sol. \(system.lore)"
        }
        if asks(["habitable", "life", "live", "alive", "living", "water", "colony", "colonise", "colonize"]) {
            if body.habitable {
                return "\(body.name) is flagged as a habitable-zone world. \(body.facts.first ?? body.blurb)"
            }
            if body.isPlanetLike {
                return "\(body.name) is not flagged habitable in the scan record. \(body.blurb)"
            }
        }
        if asks(["destroy", "shatter", "lance", "fire", "energy", "yield", "claim", "beacon", "worth"]) {
            if body.canBeDestroyed {
                return "Claiming \(body.name) yields \(body.claimYield) energy; destroying it yields \(body.destroyYield) and erases whatever is there. The choice is yours, Commander."
            }
            return "\(body.name) can be claimed for \(body.claimYield) energy; the Nova Lance cannot destroy a \(kindLabel(body))."
        }

        // Otherwise: the recorded fact sharing the most words with the question.
        let stop: Set<String> = ["the", "and", "for", "with", "what", "how", "does", "this", "that", "its",
                                 "about", "tell", "you", "can", "there", "here", "why", "when", "who", "which",
                                 "planet", "star", "system", "are", "was", "were", "have", "has", "from", "into"]
        let keywords = words.filter { $0.count > 2 && !stop.contains($0) }
        var best: (score: Int, text: String)? = nil
        for candidate in body.facts + [body.blurb, system.lore] {
            let score = tokens(candidate).reduce(0) { $0 + (keywords.contains($1) ? 1 : 0) }
            if score > (best?.score ?? 0) { best = (score, candidate) }
        }
        if let best { return best.text }
        return "No data on that in the scan record. What I have: \(body.blurb)"
    }

    static func offlineLog(save: SaveData) -> String {
        let claimed = save.claimed.count
        let destroyed = save.destroyed.count
        let years = Int(save.earthYearsElapsed.rounded())
        var line = (save.callsign.uppercased() == "COMMANDER" ? "Commander: " : "Commander \(save.callsign): ") + "\(claimed) world\(claimed == 1 ? "" : "s") on the beacon network, "
            + "\(destroyed) destroyed, \(save.energy) energy in reserve"
        line += years > 0 ? ", \(years) Earth years behind us." : "."
        line += destroyed == 0
            ? " Every world we passed is still there; Andromeda is ours to explore."
            : " Andromeda is reached; the light of the lost worlds is still travelling home."
        return line
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func formatNumber(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.3g", value)
    }
}
