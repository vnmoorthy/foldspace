import SwiftUI

/// The laptop-posture cockpit: windshield above the fold, console below.
///
/// Layout follows the iPhone Duo inner display opened like a laptop. `FoldGeometry` models the hinge
/// as a horizontal band at the vertical midpoint; on a real Duo that band is Apple's `.division`
/// reserved region reported through GeometryReader — the physical fold — so nothing interactive is
/// placed there. The console is deliberately NOT clipped so the beacon probe can be dragged up
/// across the seam into the hologram.
struct CockpitView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let top = FoldGeometry.topHalf(in: size)
            let seam = FoldGeometry.seamRect(in: size)
            let bottom = FoldGeometry.bottomHalf(in: size)

            ZStack {
                cockpitBackground

                // Windshield: the hologram lives "in the fold", the HUD is drawn over the glass.
                ZStack {
                    SceneViewport()
                    windshieldVignette(size: top.size)
                    HUDOverlay()
                }
                .frame(width: top.width, height: top.height)
                .clipped()
                .position(x: top.midX, y: top.midY)

                FoldSeam()
                    .frame(width: seam.width, height: seam.height)
                    .position(x: seam.midX, y: seam.midY)

                ConsoleView()
                    .frame(width: bottom.width, height: bottom.height)
                    .position(x: bottom.midX, y: bottom.midY)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var cockpitBackground: some View {
        LinearGradient(
            colors: [Theme.bg, Theme.panel, Theme.bg],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Subtle vignette + glass sheen so the scene reads as a windshield, not a video.
    private func windshieldVignette(size: CGSize) -> some View {
        ZStack {
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.55)],
                center: .center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.75
            )
            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            Rectangle()
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
