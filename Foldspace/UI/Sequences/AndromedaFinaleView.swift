import SwiftUI

/// Act III finale, shown while `store.phase == .andromeda`.
/// The Milky Way (seen from outside) recedes at the bottom while Andromeda grows at the top —
/// rendered galaxy maps with a procedural fallback — over a slowly drifting starfield.
struct AndromedaFinaleView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge
    @Environment(ShipComputer.self) private var ship

    @State private var appearedAt = Date()

    private static let approach: TimeInterval = 9
    private static let milkyWay = VisualAssets.image(named: "galaxy-milkyway")
    private static let andromeda = VisualAssets.image(named: "galaxy-andromeda")

    var body: some View {
        let claimed = store.save.claimed.count
        let destroyed = store.save.destroyed.count
        let years = store.save.earthYearsElapsed
        let energy = store.energy
        let callsign = store.save.callsign
        let started = appearedAt

        ZStack {
            TimelineView(.animation) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let p = min(1, max(0, now.timeIntervalSince(started) / Self.approach))
                Canvas { context, size in
                    drawScene(context: &context, size: size, t: t, progress: finaleEaseOut(p))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("ANDROMEDA · M31")
                        .font(.mono(11, weight: .semibold))
                        .kerning(3)
                        .foregroundStyle(Theme.dim)
                    Text("2,537,000 LIGHT-YEARS")
                        .font(.mono(24, weight: .black))
                        .kerning(2)
                        .foregroundStyle(.white)
                        .shadow(color: Theme.accent.opacity(0.9), radius: 12)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("YOU ARE THE FIRST")
                        .font(.mono(14, weight: .bold))
                        .kerning(5)
                        .foregroundStyle(Theme.gain)
                        .shadow(color: Theme.gain.opacity(0.8), radius: 10)
                }
                .padding(.top, 64)
                .padding(.horizontal, 20)

                Spacer()

                // Stats card sits on the seam line between the two galaxies.
                VStack(spacing: 10) {
                    Text(callsign.uppercased() == "COMMANDER" ? "COMMANDER · FLIGHT LOG" : "COMMANDER \(callsign.uppercased()) · FLIGHT LOG")
                        .font(.mono(9, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 0) {
                        finaleStat("CLAIMED", "\(claimed)", Theme.gain)
                        finaleStat("DESTROYED", "\(destroyed)", destroyed > 0 ? Theme.danger : Theme.dim)
                        finaleStat("EARTH YEARS", years < 1 ? "<1" : finaleGrouped(Int(years.rounded())), Theme.warn)
                        finaleStat("ENERGY", "\(energy)", Theme.accent)
                    }
                    Text(destroyed == 0
                         ? "Every world you passed is still there. The galaxy behind you is intact."
                         : "\(destroyed) world\(destroyed == 1 ? "" : "s") no longer exist\(destroyed == 1 ? "s" : ""). Their light is still travelling home.")
                        .font(.mono(10))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let entry = ship.commandersLogText {
                        VStack(spacing: 4) {
                            Text(ship.lastSource == .openAI
                                 ? "COMMANDER'S LOG · SHIP COMPUTER · OPENAI"
                                 : "COMMANDER'S LOG · SHIP COMPUTER · OFFLINE VOICE")
                                .font(.mono(8, weight: .semibold))
                                .kerning(1.5)
                                .foregroundStyle(Theme.dim)
                            Text(entry)
                                .font(.mono(10))
                                .foregroundStyle(Theme.accent)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    } else if ship.isThinking {
                        Text("SHIP COMPUTER · COMPOSING THE COMMANDER'S LOG…")
                            .font(.mono(8, weight: .semibold))
                            .kerning(1.5)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.panel.opacity(0.78))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 22)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Haptics.success()
                        store.reset()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("NEW GAME +").kerning(3)
                        }
                        .font(.mono(16, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Theme.accent.opacity(0.6), radius: 12)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        // Keep the save (Andromeda, M31) and return to the cockpit.
                        store.phase = .orbit
                    } label: {
                        Text("BACK TO THE COCKPIT")
                            .kerning(2)
                            .font(.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text("HINGE \(Int(hinge.angle))° · \(hinge.posture.label)")
                        .font(.mono(9))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .background(Theme.bg)
        .onAppear {
            appearedAt = Date()
            Haptics.success()
            let snapshot = store.save
            Task { await ship.commandersLog(save: snapshot) }
        }
    }

    private func finaleStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.mono(20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 6)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.mono(8))
                .kerning(1)
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Canvas

    private func drawScene(context: inout GraphicsContext, size: CGSize, t: Double, progress: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))

        // Slow starfield drift (two parallax layers).
        for layer in 0..<2 {
            let speed = layer == 0 ? 4.0 : 9.0
            let count = layer == 0 ? 110 : 60
            for i in 0..<count {
                let sx = finaleHash(i, layer * 10 + 1) * Double(size.width)
                let sy = (finaleHash(i, layer * 10 + 2) * Double(size.height) + t * speed).truncatingRemainder(dividingBy: Double(size.height))
                let r = CGFloat(0.5 + finaleHash(i, layer * 10 + 3) * (layer == 0 ? 0.9 : 1.5))
                let twinkle = 0.5 + 0.5 * sin(t * (1 + finaleHash(i, 4) * 2) + Double(i))
                context.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: Double(r * 2), height: Double(r * 2))),
                             with: .color(Color.white.opacity((0.25 + 0.6 * twinkle) * (layer == 0 ? 0.6 : 1))))
            }
        }

        // Milky Way: seen from outside, receding at the bottom.
        let mwScale = 1.0 - 0.6 * progress
        let mwCentre = CGPoint(x: size.width / 2, y: size.height * (0.78 + 0.16 * progress))
        drawGalaxy(context: &context, centre: mwCentre, radius: size.width * 0.46 * mwScale, tilt: 0.34,
                   rotation: t * 0.05, arms: 4, coreColor: Color(red: 1, green: 0.88, blue: 0.62),
                   armColor: Color(red: 0.72, green: 0.82, blue: 1), dust: Color(red: 0.35, green: 0.2, blue: 0.15),
                   alpha: 0.95 - 0.35 * progress, seedSalt: 100, image: Self.milkyWay)

        // Andromeda: growing at the top.
        let anScale = 0.35 + 0.65 * progress
        let anCentre = CGPoint(x: size.width / 2, y: size.height * (0.24 - 0.02 * progress))
        drawGalaxy(context: &context, centre: anCentre, radius: size.width * 0.52 * anScale, tilt: 0.225,
                   rotation: -t * 0.04, arms: 2, coreColor: Color(red: 1, green: 0.93, blue: 0.78),
                   armColor: Color(red: 0.78, green: 0.78, blue: 1), dust: Color(red: 0.3, green: 0.18, blue: 0.2),
                   alpha: 0.55 + 0.45 * progress, seedSalt: 200, image: Self.andromeda)

        // Seam glow: the fold, where the last jump ended.
        let seamY = size.height / 2
        context.fill(Path(CGRect(x: 0, y: seamY - 20, width: size.width, height: 40)), with: .linearGradient(
            Gradient(colors: [.clear, Theme.accent.opacity(0.10 + 0.08 * sin(t * 1.3)), .clear]),
            startPoint: CGPoint(x: 0, y: seamY - 20), endPoint: CGPoint(x: 0, y: seamY + 20)))
    }

    private func drawGalaxy(context: inout GraphicsContext, centre: CGPoint, radius: CGFloat, tilt: CGFloat, rotation: Double,
                            arms: Int, coreColor: Color, armColor: Color, dust: Color, alpha: Double, seedSalt: Int, image: UIImage?) {
        guard radius > 4 else { return }
        if let image {
            var galaxy = context
            galaxy.blendMode = .normal
            galaxy.opacity = alpha
            galaxy.translateBy(x: centre.x, y: centre.y)
            // Main maps are face-on. Andromeda's cos(77°) projection is applied once here.
            galaxy.scaleBy(x: 1, y: tilt)
            galaxy.rotate(by: .radians(rotation))
            galaxy.draw(Image(uiImage: image),
                        in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            return
        }
        // Halo + bulge
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius * tilt, width: radius * 2, height: radius * 2 * tilt)),
                     with: .radialGradient(Gradient(colors: [coreColor.opacity(alpha * 0.55), armColor.opacity(alpha * 0.12), .clear]),
                                           center: centre, startRadius: 0, endRadius: radius))
        let bulge = radius * 0.22
        context.fill(Path(ellipseIn: CGRect(x: centre.x - bulge, y: centre.y - bulge * (tilt + 0.25), width: bulge * 2, height: bulge * 2 * (tilt + 0.25))),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(alpha), coreColor.opacity(alpha * 0.6), .clear]),
                                           center: centre, startRadius: 0, endRadius: bulge))

        // Arms: logarithmic spirals of stars with per-star jitter. Dust lanes trail slightly behind.
        context.blendMode = .plusLighter
        let dotsPerArm = 150
        let scaleFactor = Double(radius) / 180
        for arm in 0..<arms {
            let armOffset = Double(arm) * (2 * .pi / Double(arms))
            for d in 0..<dotsPerArm {
                let f = Double(d) / Double(dotsPerArm)
                let theta = 0.4 + f * 4.2 + armOffset + rotation
                let r = radius * CGFloat(0.06 + 0.94 * pow(f, 0.85))
                let spread = (finaleHash(d, arm + seedSalt) - 0.5) * (0.14 + 0.16 * f) * Double(radius)
                let along = (finaleHash(d, arm + seedSalt + 1) - 0.5) * 0.25
                let th = theta + along
                let ox = r * CGFloat(cos(th)) + CGFloat(spread * cos(th + .pi / 2))
                let oy = r * CGFloat(sin(th)) + CGFloat(spread * sin(th + .pi / 2))
                let x = centre.x + ox
                let y = centre.y + oy * tilt
                let dotR = CGFloat((0.6 + 1.9 * (1 - f) + finaleHash(d, arm + seedSalt + 2) * 0.8) * scaleFactor)
                let tint = finaleHash(d, arm + seedSalt + 3)
                let color = tint > 0.86 ? Color(red: 1, green: 0.7, blue: 0.75) : armColor // occasional H-II regions
                let a = alpha * (0.85 - 0.5 * f) * (0.6 + 0.4 * tint)
                context.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(color.opacity(a)))
            }
        }
        context.blendMode = .normal

        // Dust lane: a thin darker spiral trailing each arm.
        for arm in 0..<arms {
            let armOffset = Double(arm) * (2 * .pi / Double(arms))
            var path = Path()
            for d in 0...40 {
                let f = Double(d) / 40
                let theta = 0.55 + f * 4.0 + armOffset + rotation
                let r = radius * CGFloat(0.12 + 0.84 * pow(f, 0.85))
                let pt = CGPoint(x: centre.x + r * CGFloat(cos(theta)), y: centre.y + r * CGFloat(sin(theta)) * tilt)
                if d == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(dust.opacity(alpha * 0.45)), lineWidth: max(1, radius * 0.03))
        }
    }
}

// MARK: - File-private helpers

private func finaleHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 40_503 &+ UInt32(truncatingIfNeeded: b) &* 2_654_435_761
    h = (h ^ (h >> 15)) &* 3_266_489_917
    h ^= h >> 13
    return Double(h & 0xFFFF) / 65535
}

private func finaleEaseOut(_ x: Double) -> Double { 1 - pow(1 - min(1, max(0, x)), 3) }

private func finaleGrouped(_ n: Int) -> String {
    let s = String(abs(n))
    var out = ""
    for (i, ch) in s.reversed().enumerated() {
        if i > 0, i % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + String(out.reversed())
}
