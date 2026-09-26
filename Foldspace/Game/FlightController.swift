import Foundation
import QuartzCore

/// Turns hinge gestures into game verbs and runs the 60 Hz flight loop.
///
/// The hinge IS the ship: dip = hop, smooth close = warp, squeeze = Nova Lance charge, snap open =
/// fire, pump = Fold Core, and during a sun dive the closing angle is the dive depth.
@MainActor
final class FlightController {
    private let store: GameStore
    private let hinge: HingeEngine
    private var loop: Task<Void, Never>?
    private var lastTick: TimeInterval = CACurrentMediaTime()
    private var lastRumble: TimeInterval = 0

    init(store: GameStore, hinge: HingeEngine) {
        self.store = store
        self.hinge = hinge
    }

    /// Installs the gesture sink and starts the tick loop. Safe to call more than once.
    func start() {
        hinge.onGesture = { [weak self] gesture in
            self?.handle(gesture)
        }
        loop?.cancel()
        lastTick = CACurrentMediaTime()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        hinge.onGesture = nil
    }

    // MARK: - Gestures → verbs

    private func handle(_ gesture: HingeGesture) {
        switch gesture {
        case .hop:
            store.hopToNextBody()
            if case .hopping = store.phase { Haptics.tap() }

        case .warpClose(let quality):
            // Closing the phone inside a star means "go deeper", never "warp away".
            if case .sunDive = store.phase { break }
            let before = store.phase
            store.beginWarp(quality: quality)
            if store.phase != before { Haptics.heavy() }

        case .squeezeBegan:
            store.beginWeaponCharge()
            if case .weaponCharging = store.phase { Haptics.tap() }

        case .snapOpen:
            let wasCharging: Bool = {
                if case .weaponCharging = store.phase { return true }
                return false
            }()
            store.fireWeapon()
            if wasCharging {
                if case .weaponFiring = store.phase { Haptics.heavy() } else { Haptics.warning() }
            }

        case .squeezeCancelled:
            if case .weaponCharging = store.phase { Haptics.warning() }
            store.cancelWeaponCharge()

        case .pump(let count):
            store.recordPump(count: count, target: hinge.pumpTarget)
            if case .foldCoreCharging = store.phase { Haptics.tap() }

        case .pumpComplete:
            store.foldCoreCharged()
            if case .foldCoreCharging = store.phase { Haptics.success() }

        case .laidFlat, .liftedFromFlat:
            // RootView swaps the galaxy map in/out purely from posture; just acknowledge.
            Haptics.tap()
        }
    }

    // MARK: - 60 Hz tick

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0.001, now - lastTick))
        lastTick = now

        // Pump counting only while the Fold Core is charging (the engine resets its count on enable).
        let wantsPumpMode = store.phase == .foldCoreCharging
        if hinge.pumpModeEnabled != wantsPumpMode {
            hinge.pumpModeEnabled = wantsPumpMode
        }

        switch store.phase {
        case .weaponCharging:
            if hinge.posture == .closed {
                // The squeeze turned into a full close — the lance can't fire from the outer display.
                store.cancelWeaponCharge()
                return
            }
            store.updateWeaponCharge(hingeAngle: hinge.angle, dt: dt)
            if now - lastRumble > 0.25 {
                lastRumble = now
                Haptics.rumble(intensity: 0.25 + 0.75 * store.weaponCharge)
            }

        case .sunDive:
            // angle 120° → depth 0 (corona), angle 12° → depth 1 (core)
            let depth = max(0, min(1, (120 - hinge.angle) / 108))
            store.updateSunDive(depth: depth, dt: dt)
            if hinge.angle > 130, depth <= 0 {
                store.endSunDive()
                if case .orbit = store.phase { Haptics.success() }
            } else if depth > 0.02, now - lastRumble > 0.4 {
                lastRumble = now
                Haptics.rumble(intensity: 0.2 + 0.8 * depth)
            }

        default:
            break
        }
    }
}
