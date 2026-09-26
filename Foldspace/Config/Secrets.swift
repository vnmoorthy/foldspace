import Foundation

/// Sponsor-tool credentials (Supabase · OpenAI · Sentry).
///
/// Values are read once from `Secrets.plist` in the app bundle — a gitignored file the developer
/// creates from `Secrets.example.plist` — and fall back to the example file, whose values are all
/// empty. Every consumer checks `hasSupabase` / `hasOpenAI` / `hasSentry` first, so the game runs
/// fully offline when nothing is configured. A `FOLDSPACE_<KEY>` environment variable (Xcode
/// scheme → Arguments → Environment Variables) overrides either file, which is handy in the simulator.
enum Secrets {
    /// Supabase project URL without a trailing slash, e.g. "https://abcdefgh.supabase.co".
    static let supabaseURL: String = trimmedURL(value("SUPABASE_URL"))
    /// Supabase anon (public) API key. Sent as `apikey` and `Authorization: Bearer`.
    static let supabaseAnonKey: String = value("SUPABASE_ANON_KEY")
    /// OpenAI API key for the ship computer.
    static let openAIKey: String = value("OPENAI_API_KEY")
    /// Chat-completions model. Empty in the plist → "gpt-5-mini".
    static let openAIModel: String = {
        let model = value("OPENAI_MODEL")
        return model.isEmpty ? "gpt-5-mini" : model
    }()
    /// Sentry DSN. Empty → Sentry is never started.
    static let sentryDSN: String = value("SENTRY_DSN")

    static var hasSupabase: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }
    static var hasOpenAI: Bool { !openAIKey.isEmpty }
    static var hasSentry: Bool { !sentryDSN.isEmpty }

    /// Which plist the values came from ("Secrets.plist", "Secrets.example.plist" or "none").
    static var sourceDescription: String { loaded.source }

    /// One-line summary for logs: "Supabase ✓ · OpenAI ✗ · Sentry ✗ (Secrets.example.plist)".
    static var summary: String {
        func mark(_ on: Bool) -> String { on ? "✓" : "✗" }
        return "Supabase \(mark(hasSupabase)) · OpenAI \(mark(hasOpenAI)) · Sentry \(mark(hasSentry)) (\(sourceDescription))"
    }

    // MARK: - Loading

    private struct Loaded {
        var values: [String: String]
        var source: String
    }

    /// Loaded lazily, once. `Secrets.plist` wins over `Secrets.example.plist`.
    private static let loaded: Loaded = {
        for name in ["Secrets", "Secrets.example"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = object as? [String: Any] else { continue }
            var values: [String: String] = [:]
            for (key, raw) in dict {
                if let string = raw as? String {
                    values[key] = string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return Loaded(values: values, source: "\(name).plist")
        }
        return Loaded(values: [:], source: "none")
    }()

    private static func value(_ key: String) -> String {
        if let env = ProcessInfo.processInfo.environment["FOLDSPACE_\(key)"] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return loaded.values[key] ?? ""
    }

    private static func trimmedURL(_ raw: String) -> String {
        var url = raw
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
