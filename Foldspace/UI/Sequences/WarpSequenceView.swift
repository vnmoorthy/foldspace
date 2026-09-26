import SwiftUI

/// Transit overlay, shown while `store.phase.isTransit` (hop, warp, or the intergalactic jump).
/// Streaks of light stretch toward the fold seam (screen vertical centre) with intensity `store.transitProgress`;
/// the destination and a light-year counter count up with easing; the BUBBLE STABILITY meter reads
/// `store.lastWarpQuality`. For `.intergalacticJump` the Milky Way silhouette recedes into the fold.
struct WarpSequenceView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    private static let bubbleFrames = VisualAssets.frames(named: "warp-bubble-8x1", columns: 8, rows: 1)
    private static let milkyWay = VisualAssets.image(named: "galaxy-milkyway")
    private static let andromeda = VisualAssets.image(named: "galaxy-andromeda")

    private enum Mode { case hop, warp, intergalactic, idle }

    private var mode: Mode {
        switch store.phase {
        case .hopping: return .hop
        case .warping: return .warp
        case .intergalacticJump: return .intergalactic
        default: return .idle
        }
    }

    /// Human-readable destination for the current transit.
    private var destinationName: String {
        switch store.phase {
        case .hopping(let id):
            return store.currentSystem.body(id)?.name ?? id
        case .warping(let id):
            return store.universe.system(id)?.name ?? store.targetSystem?.name ?? id
        case .intergalacticJump:
            return store.universe.system(SystemID.andromeda)?.name ?? "Andromeda"
        default:
            return store.targetSystem?.name ?? "—"
        }
    }

    /// Distance being folded, in light-years (nil for an in-system hop).
    private var distanceLY: Double? {
        switch store.phase {
        case .warping(let id):
            guard let target = store.universe.system(id) else { return store.targetSystem?.distanceLY }
            return store.universe.distance(from: store.currentSystem, to: target)
        case .intergalacticJump:
            return 2_537_000
        default:
            return nil
        }
    }

    var body: some View {
        let mode = mode
        let progress = store.transitProgress
        let quality = store.lastWarpQuality
        let destination = destinationName
        let distance = distanceLY
        let origin = store.currentSystem.name

        ZStack {
            if mode != .idle {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        drawTransit(context: &context, size: size, t: t, progress: progress, mode: mode, quality: quality)
                    }
                }
                .ignoresSafeArea()

                readouts(mode: mode, progress: progress, quality: quality, destination: destination, distance: distance, origin: origin)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: store.phase) { _, newPhase in
            if newPhase.isTransit { Haptics.tap() }
        }
    }

    // MARK: - Text layer

    private func readouts(mode: Mode, progress: Double, quality: Double, destination: String, distance: Double?, origin: String) -> some View {
        let eased = warpEaseOut(progress)
        let collapsing = mode == .warp && quality < 0.45
        return VStack(spacing: 0) {
            // Top: destination
            VStack(spacing: 4) {
                Text(mode == .hop ? "IN-SYSTEM HOP" : (mode == .intergalactic ? "INTERGALACTIC FOLD" : "FOLDING SPACE"))
                    .font(.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(2)
                Text(destination.uppercased())
                    .font(.mono(mode == .hop ? 20 : 26, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.9), radius: 10)
                    .kerning(3)
                if mode != .hop {
                    Text("FROM \(origin.uppercased())")
                        .font(.mono(10))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.top, 70)

            Spacer()

            // Middle (just below the seam): counter
            VStack(spacing: 6) {
                if let distance {
                    let shown = distance * eased
                    Text(mode == .intergalactic ? "\(warpGrouped(Int(shown.rounded()))) ly" : warpFormatLY(shown))
                        .font(.mono(mode == .intergalactic ? 30 : 34, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 12)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if mode == .intergalactic {
                        Text("OF 2,537,000 ly · \(Int((progress * 100).rounded()))%")
                            .font(.mono(10))
                            .foregroundStyle(Theme.dim)
                    }
                } else {
                    Text("ΔV BURN \(Int((progress * 100).rounded()))%")
                        .font(.mono(26, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 10)
                        .monospacedDigit()
                }
            }
            .padding(.top, 40)

            Spacer()

            // Bottom: bubble stability (warps only) + hinge
            VStack(spacing: 8) {
                if mode != .hop {
                    VStack(spacing: 5) {
                        HStack {
                            Text("BUBBLE STABILITY")
                                .font(.mono(10, weight: .semibold))
                                .kerning(1.5)
                            Spacer()
                            Text(collapsing ? "COLLAPSING" : "\(Int((quality * 100).rounded()))%")
                                .font(.mono(10, weight: .bold))
                        }
                        .foregroundStyle(collapsing ? Theme.danger : Theme.gain)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.08))
                                Rectangle()
                                    .fill(collapsing ? Theme.danger : Theme.gain)
                                    .frame(width: geo.size.width * CGFloat(min(1, max(0.02, quality))))
                                    .shadow(color: (collapsing ? Theme.danger : Theme.gain).opacity(0.8), radius: 6)
                                // Threshold tick at 45%
                                Rectangle().fill(Color.white.opacity(0.7))
                                    .frame(width: 1)
                                    .offset(x: geo.size.width * 0.45)
                            }
                        }
                        .frame(height: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        if collapsing {
                            Text("CLOSED TOO \(quality < 0.3 ? "FAST" : "SLOWLY") — YOU WILL DROP OUT SHORT")
                                .font(.mono(9, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .kerning(1)
                        }
                    }
                    .padding(12)
                    .background(Theme.panel.opacity(0.8))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke((collapsing ? Theme.danger : Theme.accent).opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 28)
                }
                Text("HINGE \(Int(hinge.angle))° · \(hinge.posture.label)")
                    .font(.mono(9))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.bottom, 36)
        }
    }

    // MARK: - Canvas

    private func drawTransit(context: inout GraphicsContext, size: CGSize, t: Double, progress: Double, mode: Mode, quality: Double) {
        let seamY = size.height / 2
        let intensity = mode == .hop ? 0.35 + 0.4 * progress : max(0.08, progress)
        let collapsing = mode == .warp && quality < 0.45

        // Darkening tint that deepens as the fold progresses.
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Theme.bg.opacity(0.35 + 0.55 * intensity)))

        // Seam glow: the fold line itself lights up.
        let bandH = 10 + 80 * intensity
        let band = CGRect(x: 0, y: seamY - bandH / 2, width: size.width, height: bandH)
        let seamColor = collapsing ? Theme.danger : Theme.accent
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [.clear, seamColor.opacity(0.25 + 0.35 * intensity), Color.white.opacity(0.4 + 0.5 * intensity), seamColor.opacity(0.25 + 0.35 * intensity), .clear]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))

        // Eight cached crops: flat → contracted/expanded wall → flat.
        if mode != .hop, Self.bubbleFrames.count == 8 {
            let frame = min(7, Int(max(0, min(1, progress)) * 8))
            let side = min(size.width * 0.92, size.height * 0.72)
            var bubble = context
            bubble.blendMode = .normal
            bubble.opacity = collapsing ? 0.65 : 0.9
            bubble.translateBy(x: size.width / 2 + (collapsing ? CGFloat(sin(t * 23) * 5) : 0), y: seamY)
            // The rendered +x arrow is 13° down from screen-right; point it into the upper fold.
            bubble.rotate(by: .degrees(-103))
            bubble.draw(Image(uiImage: Self.bubbleFrames[frame]),
                        in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }

        // Light streaks converging on the seam from both halves.
        context.blendMode = .plusLighter
        let count = 40 + Int(140 * intensity)
        let speedBase = mode == .hop ? 0.5 : 0.8
        for i in 0..<count {
            let lane = warpHash(i, 1)
            let fromTop = i % 2 == 0
            let jitter = collapsing ? sin(t * 23 + Double(i)) * 6 : 0
            let x = CGFloat(lane) * size.width + CGFloat(jitter)
            let speed = speedBase + warpHash(i, 2) * 1.6 + intensity * 2.2
            let phase = (t * speed + warpHash(i, 3) * 10).truncatingRemainder(dividingBy: 1)
            let travel = pow(phase, 0.55)
            let dist = (1 - travel) * seamY
            let y = fromTop ? seamY - dist : seamY + dist
            let len = (8 + 110 * intensity) * (0.35 + travel)
            let alpha = (0.1 + 0.9 * travel) * (0.3 + 0.7 * intensity)
            let tint = warpHash(i, 4)
            let color = collapsing
                ? Color(red: 1, green: 0.3 + 0.3 * tint, blue: 0.35)
                : Color(red: 0.55 + 0.45 * tint, green: 0.85 + 0.15 * tint, blue: 1)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x, y: fromTop ? y - len : y + len))
            context.stroke(streak, with: .color(color.opacity(alpha)), lineWidth: 1 + CGFloat(intensity) * 1.5)
        }

        // Chromatic aberration rings: same ring drawn three times with R/G/B offsets.
        let centre = CGPoint(x: size.width / 2, y: seamY)
        let offset = 2 + 9 * intensity + (collapsing ? 6 * abs(sin(t * 17)) : 0)
        let channels: [(Color, CGFloat, CGFloat)] = [
            (Color(red: 1, green: 0.15, blue: 0.15), -offset, 0),
            (Color(red: 0.15, green: 1, blue: 0.25), 0, offset * 0.5),
            (Color(red: 0.25, green: 0.4, blue: 1), offset, 0),
        ]
        for k in 0..<6 {
            let base = (t * (0.35 + 0.6 * intensity) + Double(k) / 6).truncatingRemainder(dividingBy: 1)
            let r = 20 + base * size.width * 0.75
            let alpha = (1 - base) * (0.25 + 0.5 * intensity)
            for (color, dx, dy) in channels {
                let ring = Path(ellipseIn: CGRect(x: centre.x - r + dx, y: centre.y - r * 0.32 + dy, width: r * 2, height: r * 0.64))
                context.stroke(ring, with: .color(color.opacity(alpha)), lineWidth: 1.2)
            }
        }

        // Intergalactic: the Milky Way recedes into the fold as Andromeda fills the far side.
        if mode == .intergalactic {
            drawGalaxySilhouette(context: &context, size: size, t: t, progress: progress)
        }

        // Arrival flash on the last 8%.
        if progress > 0.92 {
            let f = (progress - 0.92) / 0.08
            context.blendMode = .normal
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(f * 0.85)))
        }
        context.blendMode = .normal
    }

    private func drawGalaxySilhouette(context: inout GraphicsContext, size: CGSize, t: Double, progress: Double) {
        // Milky Way: shrinks and sinks below the seam as we leave.
        let p = warpEaseOut(progress)
        let scale = 1.0 - 0.82 * p
        let centre = CGPoint(x: size.width / 2, y: size.height * (0.62 + 0.28 * p))
        let radius = size.width * 0.42 * scale
        drawSpiral(context: &context, centre: centre, radius: radius, rotation: t * 0.15, tilt: 0.38,
                   core: Color(red: 1, green: 0.9, blue: 0.7), arm: Color(red: 0.7, green: 0.8, blue: 1), alpha: 0.9 - 0.5 * p,
                   image: Self.milkyWay)

        // Andromeda: grows from a dot above the seam.
        let a = max(0, (progress - 0.35) / 0.65)
        if a > 0 {
            let ar = size.width * 0.05 + size.width * 0.34 * warpEaseOut(a)
            let ac = CGPoint(x: size.width / 2, y: size.height * (0.28 - 0.08 * a))
            drawSpiral(context: &context, centre: ac, radius: ar, rotation: -t * 0.12, tilt: 0.225,
                       core: Color(red: 1, green: 0.92, blue: 0.8), arm: Color(red: 0.75, green: 0.75, blue: 1), alpha: 0.4 + 0.6 * a,
                       image: Self.andromeda)
        }
    }

    private func drawSpiral(context: inout GraphicsContext, centre: CGPoint, radius: CGFloat, rotation: Double, tilt: CGFloat,
                            core: Color, arm: Color, alpha: Double, image: UIImage?) {
        guard radius > 2 else { return }
        if let image {
            var galaxy = context
            galaxy.blendMode = .normal
            galaxy.opacity = alpha
            galaxy.translateBy(x: centre.x, y: centre.y)
            galaxy.scaleBy(x: 1, y: tilt)
            galaxy.rotate(by: .radians(rotation))
            galaxy.draw(Image(uiImage: image),
                        in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            return
        }
        // Core glow
        let coreR = radius * 0.28
        context.fill(Path(ellipseIn: CGRect(x: centre.x - coreR, y: centre.y - coreR * tilt, width: coreR * 2, height: coreR * 2 * tilt)),
                     with: .radialGradient(Gradient(colors: [core.opacity(alpha), core.opacity(alpha * 0.3), .clear]),
                                           center: centre, startRadius: 0, endRadius: coreR))
        // Two arms as dotted logarithmic spirals
        let arms = 2
        let dots = 70
        for armIndex in 0..<arms {
            let armOffset = Double(armIndex) * .pi
            for d in 0..<dots {
                let f = Double(d) / Double(dots)
                let theta = f * 3.6 + armOffset + rotation
                let r = radius * CGFloat(0.12 + 0.88 * f)
                let jitter = (warpHash(d, armIndex + 20) - 0.5) * 0.18 * Double(radius)
                let x = centre.x + r * CGFloat(cos(theta)) + CGFloat(jitter)
                let y = centre.y + r * tilt * CGFloat(sin(theta)) + CGFloat(jitter) * tilt
                let dotR = (2.4 - 1.6 * f) * (radius / 160)
                context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                             with: .color(arm.opacity(alpha * (0.9 - 0.6 * f))))
            }
        }
    }
}

// MARK: - File-private helpers

private func warpHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 2_246_822_519 &+ UInt32(truncatingIfNeeded: b) &* 3_266_489_917
    h = (h ^ (h >> 15)) &* 668_265_263
    h ^= h >> 13
    return Double(h & 0xFFFF) / 65535
}

private func warpEaseOut(_ x: Double) -> Double { 1 - pow(1 - min(1, max(0, x)), 3) }

/// "12,345"
private func warpGrouped(_ n: Int) -> String {
    let s = String(abs(n))
    var out = ""
    for (i, ch) in s.reversed().enumerated() {
        if i > 0, i % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + String(out.reversed())
}

/// Light-year counter formatting for the warp readout.
private func warpFormatLY(_ ly: Double) -> String {
    if ly < 100 { return String(format: "%.2f ly", ly) }
    if ly < 10_000 { return String(format: "%.1f ly", ly) }
    return "\(warpGrouped(Int(ly.rounded()))) ly"
}
