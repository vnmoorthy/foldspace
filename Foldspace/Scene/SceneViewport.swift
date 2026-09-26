import SwiftUI
import SceneKit

/// The windshield: a transparent `SCNView` showing the hologram in the fold.
///
/// Sits in the top half of `CockpitView` (`FoldGeometry.topHalf`) with `HUDOverlay` layered on top.
/// The bottom edge of this view is the fold seam — on a real iPhone Duo that is Apple's `.division`
/// reserved region, the physical crease — and `SpaceScene` anchors the body's floor there.
/// Touches pass straight through (`isUserInteractionEnabled = false`) so the console's probe drag can
/// cross the fold into the hologram.
struct SceneViewport: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    var body: some View {
        SceneViewportRepresentable(
            celestialBody: store.currentBody,
            system: store.currentSystem,
            hingeAngle: hinge.angle,
            transitProgress: store.transitProgress,
            transitActive: store.phase.isTransit,
            weaponCharge: store.weaponCharge,
            shatterTarget: store.shatterEvent?.target,
            shatterAt: store.shatterEvent?.at
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Plain-value bridge into UIKit. All game state arrives as parameters so the coordinator can diff it
/// and only poke `SpaceScene` when something actually changed (the hinge angle updates at 60 Hz).
private struct SceneViewportRepresentable: UIViewRepresentable {
    let celestialBody: CelestialBody
    let system: StarSystem
    let hingeAngle: Double
    let transitProgress: Double
    let transitActive: Bool
    let weaponCharge: Double
    let shatterTarget: String?
    let shatterAt: Date?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let space = context.coordinator.space
        view.scene = space.scene
        view.pointOfView = space.cameraNode
        view.backgroundColor = .clear            // let the cockpit gradient show through
        view.isOpaque = false
        space.scene.background.contents = nil
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false  // SpaceScene brings its own key / fill / rim lights
        view.isJitteringEnabled = false
        view.showsStatistics = false
        view.isUserInteractionEnabled = false
        view.isPlaying = true                    // keep actions + particles running
        view.rendersContinuously = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.apply(self)
    }

    @MainActor
    final class Coordinator {
        let space = SpaceScene()
        private var lastBodyID: String?
        private var lastSystemID: String?
        private var lastAngle: Double = .nan
        private var lastTransitActive = false
        private var lastTransitProgress: Double = -1
        private var lastWeaponCharge: Double = -1
        private var lastShatterAt: Date?
        private var primed = false

        func apply(_ v: SceneViewportRepresentable) {
            // Body / system
            if v.celestialBody.id != lastBodyID || v.system.id != lastSystemID {
                let animated = lastBodyID != nil
                lastBodyID = v.celestialBody.id
                lastSystemID = v.system.id
                space.show(body: v.celestialBody, system: v.system, animated: animated)
            }

            // Hinge → camera rig
            if lastAngle.isNaN || abs(v.hingeAngle - lastAngle) > 0.05 {
                lastAngle = v.hingeAngle
                space.setHinge(angle: v.hingeAngle)
            }

            // Warp / hop streaks
            if v.transitActive != lastTransitActive || abs(v.transitProgress - lastTransitProgress) > 0.004 {
                lastTransitActive = v.transitActive
                lastTransitProgress = v.transitProgress
                space.setWarp(progress: v.transitProgress, active: v.transitActive)
            }

            // Nova Lance charge glow
            if abs(v.weaponCharge - lastWeaponCharge) > 0.003 {
                lastWeaponCharge = v.weaponCharge
                space.setWeaponCharge(v.weaponCharge)
            }

            // One-shot shatter, keyed on the event's timestamp. The very first update only records the
            // current value so a stale event from a previous session doesn't fire on launch.
            if !primed {
                primed = true
                lastShatterAt = v.shatterAt
            } else if let at = v.shatterAt, at != lastShatterAt {
                lastShatterAt = at
                space.shatter(bodyID: v.shatterTarget ?? v.celestialBody.id)
            }
        }
    }
}
