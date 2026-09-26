import SwiftUI

/// Attaches the hinge angle source to a view hierarchy.
///
/// On iPhone Duo (Xcode 27.1 SDK, `DUO_SDK` compilation condition set) this uses Apple's
/// `onHingeChange` modifier, which reports hinge status and continuous angle updates
/// (https://bitrig.com/blog/iphone-duo-app-development). Everywhere else the engine is
/// fed by the on-screen `HingeSimulatorControl` or by CoreMotion tilt.
struct HingeSourceModifier: ViewModifier {
    let engine: HingeEngine

    func body(content: Content) -> some View {
        #if DUO_SDK
        content
            .onHingeChange { status in
                // `status` exposes the live hinge angle in degrees (0 = closed, 180 = flat).
                engine.source = .duo
                engine.ingest(angle: status.angle.degrees)
            }
        #else
        content
        #endif
    }
}

extension View {
    func hingeSource(_ engine: HingeEngine) -> some View {
        modifier(HingeSourceModifier(engine: engine))
    }
}

/// Reserved-region helpers. On iPhone Duo, Apple's reserved regions API reports the
/// `.division` (fold) and `.occlusion` (camera) regions through GeometryReader. Until the
/// DUO_SDK is present, we model the fold as a horizontal seam at the vertical midpoint of the
/// inner display, matching the hardware: both halves share one aspect ratio.
enum FoldGeometry {
    /// Height of the physical fold region on the inner display, in points.
    static let seamThickness: CGFloat = 14

    /// Rect of the fold seam for a given inner-display size (landscape-hinge orientation,
    /// i.e. the phone opened like a laptop: top half = windshield, bottom half = console).
    static func seamRect(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: size.height / 2 - seamThickness / 2, width: size.width, height: seamThickness)
    }

    static func topHalf(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height / 2 - seamThickness / 2)
    }

    static func bottomHalf(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: size.height / 2 + seamThickness / 2, width: size.width, height: size.height / 2 - seamThickness / 2)
    }
}
