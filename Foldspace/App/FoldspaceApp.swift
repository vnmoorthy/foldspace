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
            applyDemoStateIfRequested()
        }
    }

    /// Stage-demo / screenshot hook. Launch with the environment variable FOLDSPACE_DEMO set to one of
    /// cockpit · galaxy · outer · warp · sun · weapon · blackhole · andromeda to jump straight to that
    /// moment, e.g. `SIMCTL_CHILD_FOLDSPACE_DEMO=blackhole xcrun simctl launch booted com.vnmoorthy.foldspace`.
    private func applyDemoStateIfRequested() {
        guard let demo = ProcessInfo.processInfo.environment["FOLDSPACE_DEMO"]?.lowercased(), !demo.isEmpty else { return }
        let store = self.store
        let hinge = self.hinge
        Task { @MainActor in
            // Let the first frame render so the views exist before we drive state.
            try? await Task.sleep(nanoseconds: 400_000_000)
            switch demo {
            case "cockpit":
                store.demoSkip(to: .warp)
                hinge.ingest(angle: 110)
            case "galaxy":
                store.demoSkip(to: .warp)
                store.targetSystemID = SystemID.trappist1
                hinge.ingest(angle: 180)
            case "outer":
                store.demoSkip(to: .warp)
                hinge.ingest(angle: 0)
            case "warp":
                store.demoSkip(to: .warp)
                store.targetSystemID = SystemID.alphaCentauri
                hinge.ingest(angle: 0)
                store.beginWarp(quality: 1)
            case "sun":
                store.demoSkip(to: .warp)
                store.save.systemID = SystemID.sol
                store.save.bodyID = BodyID.earth
                hinge.ingest(angle: 110)
                store.beginSunDive()
                hinge.ingest(angle: 40)
            case "weapon":
                store.demoSkip(to: .core)
                store.save.systemID = SystemID.sol
                store.save.bodyID = BodyID.earth
                store.phase = .orbit
                hinge.ingest(angle: 110)
                store.beginWeaponCharge()
                store.weaponCharge = 0.8
                hinge.ingest(angle: 25)
            case "blackhole":
                store.demoSkip(to: .core)
                hinge.ingest(angle: 110)
                store.phase = .blackHole
            case "andromeda":
                store.demoSkip(to: .core)
                store.save.reachedAndromeda = true
                hinge.ingest(angle: 110)
                store.phase = .andromeda
            default:
                break
            }
            store.log("DEMO STATE: \(demo.uppercased())")
        }
    }
}
