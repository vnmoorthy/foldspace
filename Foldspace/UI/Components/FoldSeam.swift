import SwiftUI

/// The physical fold between windshield and console.
///
/// On iPhone Duo this band is Apple's `.division` reserved region (the hinge itself), so it never
/// hosts anything interactive — it only reads as hardware: a dark gradient, a 1 px cyan hinge line
/// with tick marks, and the live hinge angle at the right edge.
struct FoldSeam: View {
    @Environment(HingeEngine.self) private var hinge

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.95), Theme.panel, Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Tick marks: every 24 pt, a longer one every fourth.
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = 12
                var index = 0
                while x < size.width {
                    let h: CGFloat = index % 4 == 0 ? 6 : 3
                    path.move(to: CGPoint(x: x, y: size.height / 2 - h / 2))
                    path.addLine(to: CGPoint(x: x, y: size.height / 2 + h / 2))
                    x += 24
                    index += 1
                }
                context.stroke(path, with: .color(Theme.accent.opacity(0.28)), lineWidth: 1)
            }

            // The hinge line.
            Rectangle()
                .fill(Theme.accent.opacity(0.75))
                .frame(height: 1)
                .shadow(color: Theme.accent.opacity(0.9), radius: 3)

            HStack {
                Text("FOLD")
                    .font(.mono(7, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.dim.opacity(0.85))
                    .padding(.horizontal, 3)
                    .background(Theme.panel)
                    .padding(.leading, 6)
                Spacer()
                Text(String(format: "%3.0f°", hinge.angle))
                    .font(.mono(8, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent.opacity(0.95))
                    .padding(.horizontal, 3)
                    .background(Theme.panel)
                    .padding(.trailing, 6)
            }
        }
        .frame(height: FoldGeometry.seamThickness)
        .clipped()
        .allowsHitTesting(false)
    }
}
