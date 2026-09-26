import Foundation
import Observation
import CoreMotion
import QuartzCore

/// Where the hinge angle is coming from.
enum HingeSource: String, CaseIterable, Identifiable, Sendable {
    case simulated   // on-screen hinge control (Xcode simulator / any iPhone)
    case motion      // CoreMotion pitch on a non-folding iPhone – tilt the phone like a lid
    case duo         // native iPhone Duo hinge via `onHingeChange` (requires the DUO_SDK build flag)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .simulated: return "Simulated hinge"
        case .motion: return "Motion (tilt)"
        case .duo: return "iPhone Duo hinge"
        }
    }
}

/// The single source of truth for the hinge angle.
/// Every source (`HingeSourceModifier`, `HingeSimulatorControl`, CoreMotion) calls `ingest(angle:)`;
/// the engine derives velocity, posture and the discrete `HingeGesture`s that drive the game.
@MainActor
@Observable
final class HingeEngine {

    // MARK: - Published state
    private(set) var angle: Double = 110
    private(set) var velocity: Double = 0
    private(set) var posture: HingePosture = .laptop
    private(set) var lastGesture: HingeGesture?
    private(set) var lastGestureAt: TimeInterval = 0
    private(set) var pumpCount: Int = 0
    var source: HingeSource = .simulated {
        didSet { sourceDidChange() }
    }

    /// When true the engine counts open/shut oscillations and emits `.pump` / `.pumpComplete`.
    var pumpModeEnabled: Bool = false {
        didSet { if pumpModeEnabled { resetPumps() } }
    }
    var pumpTarget: Int = 4

    /// Gesture sink. FlightController installs itself here.
    var onGesture: ((HingeGesture) -> Void)?

    /// Normalised fold amount: 0 = flat, 1 = closed. Handy for shaders/animations.
    var fold: Double { 1 - angle / 180 }

    // MARK: - Internals
    private var history: [HingeSample] = []
    private let historyWindow: TimeInterval = 2.5
    private var lastPosture: HingePosture = .laptop
    private var hopStartedAt: TimeInterval?
    private var hopMinAngle: Double = 180
    private var closeStartedAt: TimeInterval?
    private var closeStartAngle: Double = 0
    private var squeezeActive = false
    private var pumpLastExtremeAngle: Double = 110
    private var pumpDirection: Int = 0 // +1 opening, −1 closing
    private var flatSettled = false
    private let motion = CMMotionManager()

    init() {}

    // MARK: - Ingest

    /// Feed a new absolute angle (degrees, 0...180). Safe to call at any rate.
    func ingest(angle raw: Double, timestamp: TimeInterval = CACurrentMediaTime()) {
        let a = min(180, max(0, raw))
        let prev = history.last
        var v = 0.0
        if let prev, timestamp > prev.timestamp {
            let dt = timestamp - prev.timestamp
            // light smoothing so the velocity readout isn't jittery
            let instant = (a - prev.angle) / dt
            v = prev.velocity * 0.35 + instant * 0.65
        }
        let sample = HingeSample(angle: a, velocity: v, timestamp: timestamp)
        history.append(sample)
        history.removeAll { timestamp - $0.timestamp > historyWindow }

        angle = a
        velocity = v
        let newPosture = HingePosture.from(angle: a)
        detectGestures(sample: sample, newPosture: newPosture)
        if newPosture != posture {
            lastPosture = posture
            posture = newPosture
        }
    }

    /// Nudge the angle by a delta (used by the on-screen drag handle).
    func nudge(by delta: Double) {
        ingest(angle: angle + delta)
    }

    /// Animate the angle to a target over `duration` seconds (used by simulator buttons & demos).
    func animate(to target: Double, duration: TimeInterval = 0.6) {
        let start = angle
        let t0 = CACurrentMediaTime()
        let steps = max(2, Int(duration * 60))
        Task { @MainActor [weak self] in
            for i in 1...steps {
                let p = Double(i) / Double(steps)
                let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                self?.ingest(angle: start + (target - start) * eased, timestamp: t0 + duration * p)
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
            }
        }
    }

    func resetPumps() {
        pumpCount = 0
        pumpDirection = 0
        pumpLastExtremeAngle = angle
    }

    // MARK: - Gesture detection

    private func emit(_ g: HingeGesture, at t: TimeInterval) {
        lastGesture = g
        lastGestureAt = t
        onGesture?(g)
    }

    private func detectGestures(sample s: HingeSample, newPosture: HingePosture) {
        let t = s.timestamp

        // --- HOP: dip below 70° from the cockpit zone and return above 85° within 1.5 s (never below 30°)
        if hopStartedAt == nil, posture == .laptop || posture == .open, s.angle < 70, angle >= 70 || history.count < 2 {
            hopStartedAt = t
            hopMinAngle = s.angle
        }
        if let started = hopStartedAt {
            hopMinAngle = min(hopMinAngle, s.angle)
            if s.angle < 30 || t - started > 1.5 {
                hopStartedAt = nil // became a close / squeeze, or too slow
            } else if s.angle > 85, hopMinAngle < 65 {
                hopStartedAt = nil
                emit(.hop, at: t)
            }
        }

        // --- SQUEEZE (weapon charge) / SNAP OPEN (fire)
        if !squeezeActive, newPosture == .peek, s.velocity <= 0, !pumpModeEnabled {
            squeezeActive = true
            emit(.squeezeBegan, at: t)
        } else if squeezeActive, s.angle >= 45 {
            squeezeActive = false
            // decide between snap and slow release using the last 250 ms of history
            let recent = history.filter { t - $0.timestamp < 0.25 }
            let peakV = recent.map(\.velocity).max() ?? s.velocity
            if peakV > 250 || s.velocity > 250 {
                snapPending = t
            } else {
                emit(.squeezeCancelled, at: t)
            }
        } else if squeezeActive, newPosture == .closed {
            squeezeActive = false // turned into a close
        }
        if let sp = snapPending {
            if s.angle > 100 {
                snapPending = nil
                emit(.snapOpen, at: t)
            } else if t - sp > 0.6 || s.velocity < 0 {
                snapPending = nil
                emit(.squeezeCancelled, at: t)
            }
        }

        // --- WARP CLOSE: from ≥ 60° down to closed
        if closeStartedAt == nil, s.velocity < -5, s.angle >= 60 {
            closeStartedAt = t
            closeStartAngle = s.angle
        }
        if let started = closeStartedAt {
            if s.velocity > 5, s.angle > 20 {
                closeStartedAt = nil // reopened → not a close
            } else if newPosture == .closed {
                closeStartedAt = nil
                if closeStartAngle >= 60 {
                    let avg = (closeStartAngle - s.angle) / max(0.05, t - started)
                    emit(.warpClose(quality: Self.warpQuality(avgSpeed: avg)), at: t)
                }
            } else if t - started > 6 {
                closeStartedAt = nil
            }
        }

        // --- PUMP: count direction reversals with ≥ 40° swings
        if pumpModeEnabled {
            let dir = s.velocity > 15 ? 1 : (s.velocity < -15 ? -1 : 0)
            if dir != 0, dir != pumpDirection {
                let swing = abs(s.angle - pumpLastExtremeAngle)
                if pumpDirection != 0, swing >= 40 {
                    pumpCount += 1
                    emit(.pump(count: pumpCount), at: t)
                    if pumpCount >= pumpTarget {
                        emit(.pumpComplete, at: t)
                    }
                }
                pumpDirection = dir
                pumpLastExtremeAngle = s.angle
            }
        }

        // --- FLAT
        if !flatSettled, s.angle >= 170, abs(s.velocity) < 40 {
            flatSettled = true
            emit(.laidFlat, at: t)
        } else if flatSettled, s.angle < 160 {
            flatSettled = false
            emit(.liftedFromFlat, at: t)
        }
    }

    private var snapPending: TimeInterval?

    /// 1.0 for a smooth 60–160°/s close, tapering to 0.2 for slams (> 320°/s) and 0.3 for crawls (< 20°/s).
    static func warpQuality(avgSpeed: Double) -> Double {
        switch avgSpeed {
        case ..<20: return 0.3
        case ..<60: return 0.3 + 0.7 * (avgSpeed - 20) / 40
        case ...160: return 1.0
        case ...320: return 1.0 - 0.8 * (avgSpeed - 160) / 160
        default: return 0.2
        }
    }

    // MARK: - CoreMotion source (tilt a normal iPhone like a lid)

    private func sourceDidChange() {
        stopMotion()
        if source == .motion { startMotion() }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // pitch: 0 when flat on a table, ~π/2 when upright. Map upright → 90°, flat → 180°, face down → 0°.
            let pitch = data.attitude.pitch // −π/2 ... π/2
            let deg = 180 - (pitch / (.pi / 2)) * 90
            self.ingest(angle: deg)
        }
    }

    private func stopMotion() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }
}
