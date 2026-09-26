import SwiftUI
#if canImport(Sentry)
import Sentry
#endif

/// FOLDSPACE — the hinge is the ship.
///
/// One `GameStore` (progress + flight phase), one `HingeEngine` (angle → posture → gestures), one
/// `FlightController` (gestures → game verbs, 60 Hz tick) and one `ShipComputer` (OpenAI narration with
/// an offline voice) live for the whole app. Every view reads them from the environment; no view takes
/// init parameters.
///
/// Sponsor stack — all optional, all read from Secrets.plist (Config/Secrets.swift):
/// Supabase → `GalacticRegistry`, OpenAI → `ShipComputer`, Sentry → started here + `Telemetry`.
@main
struct FoldspaceApp: App {
    @State private var store = GameStore()
    @State private var hinge = HingeEngine()
    @State private var ship = ShipComputer()
    @State private var flight: FlightController?

    init() {
        #if canImport(Sentry)
        if Secrets.hasSentry {
            SentrySDK.start { options in
                options.dsn = Secrets.sentryDSN
                options.tracesSampleRate = 1.0
                options.enableAutoPerformanceTracing = true
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hinge)
                .environment(ship)
                // Native iPhone Duo hinge (`onHingeChange`) when built with DUO_SDK; a no-op otherwise,
                // in which case HingeSimulatorControl / CoreMotion feed the engine.
                .hingeSource(hinge)
                .preferredColorScheme(.dark)
                .onAppear { boot() }
        }
    }

    /// Wires the Galactic Registry and the flight controller exactly once per launch.
    private func boot() {
        if store.registry == nil {
            let registry = GalacticRegistry(callsign: store.save.callsign)
            store.registry = registry
            Task { @MainActor in
                await registry.refresh()
            }
        }
        if flight == nil {
            let controller = FlightController(store: store, hinge: hinge)
            controller.start()
            flight = controller
            Telemetry.breadcrumb(Secrets.summary, category: "launch")
        }
    }
}
