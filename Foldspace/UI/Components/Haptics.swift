import UIKit

/// Haptic vocabulary for the cockpit. Generators are kept alive so repeated taps stay snappy.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notifier = UINotificationFeedbackGenerator()

    /// Small confirmation: chip tap, hop, hinge control.
    static func tap() {
        light.impactOccurred()
    }

    /// Big moment: warp close, weapon fire, probe crossing the fold.
    static func heavy() {
        heavyGenerator.impactOccurred(intensity: 1.0)
    }

    /// Beacon planted, core charged, repair done.
    static func success() {
        notifier.notificationOccurred(.success)
    }

    /// Something went wrong or was cancelled.
    static func warning() {
        notifier.notificationOccurred(.warning)
    }

    /// Continuous rumble (sun dive heat, weapon charge). `intensity` 0...1.
    static func rumble(intensity: Double) {
        let clamped = CGFloat(max(0, min(1, intensity)))
        guard clamped > 0.02 else { return }
        rigid.impactOccurred(intensity: clamped)
    }
}
