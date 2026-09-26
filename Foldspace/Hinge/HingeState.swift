import Foundation

/// Posture of the iPhone Duo hinge, derived from the continuous angle.
/// 0° = fully closed, 180° = fully flat (one 7.6" canvas).
enum HingePosture: String, Codable, Sendable, CaseIterable {
    case closed   // 0°  ... 12°   → outer display only (docked / in transit)
    case peek     // 12° ... 45°   → squeezed: Nova Lance charge zone
    case laptop   // 45° ... 135°  → cockpit (windshield above the fold, console below)
    case open     // 135°... 170°  → wide cockpit
    case flat     // 170°... 180°  → galaxy map on the full inner display

    static func from(angle: Double) -> HingePosture {
        switch angle {
        case ..<12: return .closed
        case ..<45: return .peek
        case ..<135: return .laptop
        case ..<170: return .open
        default: return .flat
        }
    }

    var label: String {
        switch self {
        case .closed: return "CLOSED"
        case .peek: return "SQUEEZED"
        case .laptop: return "COCKPIT"
        case .open: return "OPEN"
        case .flat: return "FLAT"
        }
    }

    var isInnerDisplayActive: Bool { self != .closed }
}

/// A single hinge reading.
struct HingeSample: Sendable, Equatable {
    var angle: Double          // degrees 0...180
    var velocity: Double       // degrees / second (+ opening, − closing)
    var timestamp: TimeInterval
}

/// Discrete gestures recognised from the continuous angle stream.
/// Each one maps to exactly one game verb (see FlightController).
enum HingeGesture: Equatable, Sendable {
    /// Top half dipped from the cockpit zone below 70° and came back within ~1.5 s.
    /// Game verb: HOP to the next planet in the same star system.
    case hop
    /// Phone closed from ≥ 60° to < 12°. `quality` 0...1 rates how smoothly (ideal 60–160°/s).
    /// Game verb: WARP — fold space to the targeted star.
    case warpClose(quality: Double)
    /// Opened from the squeezed zone (< 45°) past 100° at > 250°/s.
    /// Game verb: FIRE the Nova Lance.
    case snapOpen
    /// The n-th open/shut oscillation while the Fold Core is charging.
    case pump(count: Int)
    /// Enough pumps accumulated → Fold Core is charged.
    case pumpComplete
    /// Angle settled ≥ 170°. Game verb: show the galaxy map.
    case laidFlat
    /// Left the flat zone. Game verb: back to the cockpit.
    case liftedFromFlat
    /// Entered the squeezed zone (< 45°) from above and is holding. Game verb: begin weapon charge.
    case squeezeBegan
    /// Left the squeezed zone slowly (no snap). Game verb: cancel weapon charge.
    case squeezeCancelled
}

extension HingeGesture {
    var displayName: String {
        switch self {
        case .hop: return "HOP"
        case .warpClose(let q): return "WARP (\(Int(q * 100))%)"
        case .snapOpen: return "SNAP OPEN"
        case .pump(let n): return "PUMP \(n)"
        case .pumpComplete: return "CORE CHARGED"
        case .laidFlat: return "FLAT"
        case .liftedFromFlat: return "LIFTED"
        case .squeezeBegan: return "SQUEEZE"
        case .squeezeCancelled: return "RELEASE"
        }
    }
}
