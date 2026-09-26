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
        // iOS 27.1: `onHingeChange(isEnabled:_:)` calls the closure with the old and new
        // `DeviceHingeContext`. `context.hinge` is an optional `DeviceHinge` (nil = no hinge)
        // with `angle: Angle` (180° when flat) and `status: .closed / .partiallyOpen / .fullyOpen`.
        // Apple's guidance: use the hinge for interactions and effects, never for layout —
        // layout comes from size classes, reserved regions and ArrangementView.
        content
            .onHingeChange { _, newContext in
                guard let hinge = newContext.hinge else { return }
                engine.source = .duo
                engine.ingest(angle: hinge.angle.degrees)
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

    /// The physical fold, if the system reports one. On iPhone Duo (iOS 27.1) this is the active
    /// `.division` reserved region from `GeometryProxy.reservedRegions(kind:)`; everywhere else it is
    /// the modelled seam at the vertical midpoint.
    static func seamRect(in size: CGSize, proxy: GeometryProxy) -> CGRect {
        #if DUO_SDK
        if let fold = proxy.reservedRegions(kind: .division).first(where: { $0.isActive }) {
            return fold.frame
        }
        #endif
        return seamRect(in: size)
    }

    /// Camera cut-outs (`.occlusion` reserved regions) to keep HUD readouts away from.
    static func occlusions(proxy: GeometryProxy) -> [CGRect] {
        #if DUO_SDK
        return proxy.reservedRegions(kind: .occlusion).map(\.frame)
        #else
        return []
        #endif
    }
}
