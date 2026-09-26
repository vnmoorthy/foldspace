import SwiftUI

/// FOLDSPACE — the hinge is the ship.
///
/// One `GameStore` (progress + flight phase), one `HingeEngine` (angle → posture → gestures) and one
/// `FlightController` (gestures → game verbs, 60 Hz tick) live for the whole app. Every view reads
/// them from the environment; no view takes init parameters.
@main
struct FoldspaceApp: App {
    @State private var store = GameStore()
    @State private var hinge = HingeEngine()
    @State private var flight: FlightController?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hinge)
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
        }
    }
}
