import SwiftUI

/// Nova Lance overlay. Sits on top of the cockpit.
/// - `.weaponCharging`: the fold seam (horizontal band at screen centre) glows with `store.weaponCharge`
///   and particles from both halves converge into it.
/// - `.weaponFiring`: a beam bursts from the seam upward into the top half (where the planet hologram sits),
///   white flash + expanding shock rings, fading over 2.4 s (matches GameStore's 2.4 s resolve delay).
/// Renders nothing (and passes touches through) in every other phase.
struct WeaponView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    @State private var firedAt: Date?

    private static let fireDuration: TimeInterval = 2.4

    private var isCharging: Bool {
        if case .weaponCharging = store.phase { return true }
        return false
    }

    private var isFiring: Bool {
        if case .weaponFiring = store.phase { return true }
        return false
    }

    private var targetName: String {
        if case .weaponFiring(let id) = store.phase, let body = store.currentSystem.body(id) { return body.name }
        return store.currentBody.name
    }

    var body: some View {
        let charging = isCharging
        let firing = isFiring
        let charge = store.weaponCharge
        let angle = hinge.angle
        let name = targetName
        let fired = firedAt

        ZStack {
            if charging || firing {
                // Dim the console so the lance owns the moment (the readout card sits on it).
                VStack(spacing: 0) {
                    Color.clear
                    LinearGradient(colors: [Theme.bg.opacity(0.35), Theme.bg.opacity(0.82), Theme.bg.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .allowsHitTesting(false)

                TimelineView(.animation) { timeline in
                    let now = timeline.date
                    let t = now.timeIntervalSinceReferenceDate
                    let fireT: Double = fired.map { min(1, max(0, now.timeIntervalSince($0) / Self.fireDuration)) } ?? 0
                    Canvas { context, size in
                        if charging {
                            drawCharging(context: &context, size: size, charge: charge, t: t)
                        } else if firing {
                            drawFiring(context: &context, size: size, progress: fireT, t: t)
                        }
                    }
                }
                .allowsHitTesting(false)

                if charging {
                    chargingReadout(charge: charge, angle: angle, name: name)
                } else {
                    firingReadout(name: name, fired: fired)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if firing, firedAt == nil { firedAt = Date() }
        }
        .onChange(of: store.phase) { _, newPhase in
            if case .weaponFiring = newPhase {
                firedAt = Date()
                Haptics.heavy()
            } else if case .weaponCharging = newPhase {
                firedAt = nil
                Haptics.tap()
            } else {
                firedAt = nil
            }
        }
    }

    // MARK: - Readouts

    private func chargingReadout(charge: Double, angle: Double, name: String) -> some View {
        let pct = Int((charge * 100).rounded())
        let ready = charge >= 0.6
        return VStack(spacing: 0) {
            Color.clear
            VStack(spacing: 6) {
                Text("NOVA LANCE  CHARGE \(pct)%")
                    .font(.mono(15, weight: .bold))
                    .foregroundStyle(ready ? Theme.gain : Theme.warn)
                    .shadow(color: (ready ? Theme.gain : Theme.warn).opacity(0.8), radius: 8)
                    .kerning(2)
                Text(ready ? "SNAP THE PHONE OPEN TO FIRE" : "HOLD THE SQUEEZE")
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(ready ? .white : Theme.dim)
                    .kerning(1.5)
                Text("TARGET \(name.uppercased()) · HINGE \(Int(angle))°")
                    .font(.mono(9))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.panel.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke((ready ? Theme.gain : Theme.warn).opacity(0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.6), radius: 18)
            .frame(maxHeight: .infinity)
        }
    }

    private func firingReadout(name: String, fired: Date?) -> some View {
        VStack(spacing: 0) {
            Color.clear
            VStack(spacing: 6) {
                Text("NOVA LANCE  DISCHARGE")
                    .font(.mono(15, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.9), radius: 10)
                    .kerning(2)
                Text("\(name.uppercased()) · STRUCTURAL FAILURE")
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .kerning(1.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.panel.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.danger.opacity(0.7), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.6), radius: 18)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Canvas: charging

    private func drawCharging(context: inout GraphicsContext, size: CGSize, charge: Double, t: Double) {
        let seamY = size.height / 2
        let glow = max(0.05, charge)
        let hot = charge >= 0.6

        // Seam band: an intensifying horizontal glow at the physical fold.
        let bandH = 6 + 48 * glow
        let band = CGRect(x: 0, y: seamY - bandH / 2, width: size.width, height: bandH)
        let core = hot ? Color(red: 0.75, green: 1, blue: 0.85) : Color(red: 1, green: 0.75, blue: 0.35)
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [.clear, core.opacity(0.35 + 0.45 * glow), Color.white.opacity(0.55 + 0.4 * glow), core.opacity(0.35 + 0.45 * glow), .clear]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))

        // Thin hard line on the seam itself, flickering faster as the charge builds.
        let flicker = 0.7 + 0.3 * sin(t * (8 + 30 * charge))
        context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: seamY)); p.addLine(to: CGPoint(x: size.width, y: seamY)) },
                       with: .color(Color.white.opacity(0.5 + 0.5 * glow * flicker)), lineWidth: 1 + 2 * glow)

        // Converging particles: each has a fixed lane (x) and half, and streams toward the seam.
        context.blendMode = .plusLighter
        let count = 18 + Int(46 * charge)
        let reach = min(size.height * 0.5, 150 + 60 * charge)   // streams start this far from the seam
        for i in 0..<count {
            let seed = Double(i)
            let lane = weaponHash(i, 1)
            let x = CGFloat(lane) * size.width
            let speed = 0.6 + weaponHash(i, 2) * 1.4 + charge * 1.2
            let phase = (t * speed + weaponHash(i, 3) * 10).truncatingRemainder(dividingBy: 1)
            let fromTop = (i % 2 == 0)
            // 0 → far from the seam, 1 → at the seam
            let travel = pow(phase, 0.65)
            let dist = (1 - travel) * reach
            let y = fromTop ? seamY - dist : seamY + dist
            let len = 4 + 18 * travel * (0.3 + charge)
            let alpha = pow(travel, 1.6) * (0.35 + 0.65 * glow)
            let hue = weaponHash(i, 4)
            let color = hot
                ? Color(red: 0.6 + 0.4 * hue, green: 1, blue: 0.8)
                : Color(red: 1, green: 0.55 + 0.4 * hue, blue: 0.25)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x, y: fromTop ? y - len : y + len))
            context.stroke(streak, with: .color(color.opacity(alpha)), lineWidth: 0.8 + CGFloat(seed.truncatingRemainder(dividingBy: 2)) * 0.4)
        }

        // Focus rings on the seam centre that tighten as the charge rises.
        let centre = CGPoint(x: size.width / 2, y: seamY)
        for k in 0..<3 {
            let base = 90.0 - 60.0 * charge
            let r = base + Double(k) * 26 * (1 - charge * 0.5) + 6 * sin(t * 3 + Double(k))
            let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r * 0.28, width: r * 2, height: r * 0.56))
            context.stroke(ring, with: .color(core.opacity(0.12 + 0.28 * glow)), lineWidth: 1)
        }
        context.blendMode = .normal
    }

    // MARK: - Canvas: firing

    private func drawFiring(context: inout GraphicsContext, size: CGSize, progress: Double, t: Double) {
        let seamY = size.height / 2
        let fade = 1 - weaponEaseIn(progress)          // overall envelope
        let burst = weaponEaseOut(min(1, progress / 0.18)) // beam grows fast in the first 18%
        let centreX = size.width / 2

        // Full-screen white flash on the first 12%.
        if progress < 0.12 {
            let f = 1 - progress / 0.12
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(f * 0.85)))
        }

        // Beam from the seam into the top half where the hologram sits.
        let beamTop = seamY - (seamY - 20) * burst
        let widthCore = (14 + 26 * (1 - progress)) * (0.6 + 0.4 * sin(t * 40) * (1 - progress))
        let widthHalo = widthCore * 4.5
        context.blendMode = .plusLighter
        let halo = CGRect(x: centreX - widthHalo / 2, y: beamTop, width: widthHalo, height: seamY - beamTop)
        context.fill(Path(halo), with: .linearGradient(
            Gradient(colors: [.clear, Theme.accent.opacity(0.5 * fade), .clear]),
            startPoint: CGPoint(x: halo.minX, y: 0), endPoint: CGPoint(x: halo.maxX, y: 0)))
        let coreRect = CGRect(x: centreX - widthCore / 2, y: beamTop, width: widthCore, height: seamY - beamTop)
        context.fill(Path(coreRect), with: .linearGradient(
            Gradient(colors: [Theme.accent.opacity(0.7 * fade), Color.white.opacity(fade), Theme.accent.opacity(0.7 * fade)]),
            startPoint: CGPoint(x: coreRect.minX, y: 0), endPoint: CGPoint(x: coreRect.maxX, y: 0)))

        // Seam blowout: the whole fold lights up then dims.
        let bandH = 60 * fade + 4
        let band = CGRect(x: 0, y: seamY - bandH / 2, width: size.width, height: bandH)
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [.clear, Color.white.opacity(0.9 * fade), .clear]),
            startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))

        // Expanding shock rings, emitted from the seam centre and the impact point at the top.
        let origins = [CGPoint(x: centreX, y: seamY), CGPoint(x: centreX, y: max(30, seamY * 0.42))]
        for (oi, origin) in origins.enumerated() {
            for k in 0..<5 {
                let delay = Double(k) * 0.09 + Double(oi) * 0.12
                let local = progress - delay
                guard local > 0 else { continue }
                let e = weaponEaseOut(min(1, local / 0.8))
                let r = e * size.width * (oi == 0 ? 0.9 : 0.55)
                let alpha = (1 - e) * 0.7 * fade
                let squash: CGFloat = oi == 0 ? 0.35 : 0.7
                let ring = Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r * squash, width: r * 2, height: r * 2 * squash))
                context.stroke(ring, with: .color((k % 2 == 0 ? Color.white : Theme.accent).opacity(alpha)), lineWidth: 2.5 - CGFloat(e) * 2)
            }
        }

        // Debris sparks flung from the impact point.
        let impact = origins[1]
        for i in 0..<60 {
            let a = weaponHash(i, 11) * .pi * 2
            let sp = 60 + weaponHash(i, 12) * 260
            let life = progress - weaponHash(i, 13) * 0.15
            guard life > 0 else { continue }
            let d = sp * life
            let p = CGPoint(x: impact.x + CGFloat(cos(a) * d), y: impact.y + CGFloat(sin(a) * d) + CGFloat(life * life * 120))
            let alpha = max(0, 1 - life * 1.1) * fade
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                         with: .color((i % 3 == 0 ? Theme.warn : Color.white).opacity(alpha)))
        }
        context.blendMode = .normal
    }
}

// MARK: - File-private helpers

private func weaponHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 2_654_435_761 &+ UInt32(truncatingIfNeeded: b) &* 40_503
    h = (h ^ (h >> 15)) &* 2_246_822_519
    h ^= h >> 13
    return Double(h & 0xFFFF) / 65535
}

private func weaponEaseOut(_ x: Double) -> Double { 1 - pow(1 - min(1, max(0, x)), 3) }
private func weaponEaseIn(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c }
