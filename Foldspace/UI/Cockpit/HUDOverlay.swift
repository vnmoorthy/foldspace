import SwiftUI

/// Heads-up display drawn over the windshield: corner readouts, a targeting reticle on the planet,
/// a faint scan-line/grid texture, and a hazard strip when the hull is failing or the Nova Lance is
/// charging. Purely presentational — it never intercepts touches meant for the scene.
struct HUDOverlay: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge
    @State private var reticleSpin = false
    @State private var stripPulse = false

    private struct Warning: Equatable {
        let text: String
        let symbol: String
        let color: Color
        let meter: Double?
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                scanTexture(size: geo.size)
                reticle(size: geo.size)
                readouts
                warningStrip
            }
        }
        .allowsHitTesting(false)
        .onAppear { reticleSpin = true }
    }

    // MARK: - Texture

    private func scanTexture(size: CGSize) -> some View {
        Canvas { context, size in
            // Grid every 40 pt
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += 40
            }
            var y: CGFloat = 0
            while y <= size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += 40
            }
            context.stroke(grid, with: .color(Theme.accent.opacity(0.05)), lineWidth: 0.5)

            // Scan-lines every 3 pt
            var lines = Path()
            var sy: CGFloat = 0
            while sy <= size.height {
                lines.move(to: CGPoint(x: 0, y: sy))
                lines.addLine(to: CGPoint(x: size.width, y: sy))
                sy += 3
            }
            context.stroke(lines, with: .color(Color.black.opacity(0.10)), lineWidth: 1)
        }
    }

    // MARK: - Reticle

    private var reticleTint: Color {
        switch store.phase {
        case .weaponCharging, .weaponFiring: return Theme.danger
        default: return store.hull < 40 ? Theme.warn : Theme.accent
        }
    }

    private func reticle(size: CGSize) -> some View {
        let d = min(size.width, size.height) * 0.42
        let tint = reticleTint
        return ZStack {
            // Rotating dashed outer ring
            Circle()
                .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [d * 0.30, d * 0.22]))
                .frame(width: d, height: d)
                .rotationEffect(.degrees(reticleSpin ? 360 : 0))
                .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: reticleSpin)

            Circle()
                .stroke(tint.opacity(0.25), lineWidth: 1)
                .frame(width: d * 0.72, height: d * 0.72)

            // Static brackets + crosshair ticks
            Canvas { context, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let half = d * 0.62
                let arm = d * 0.14
                var brackets = Path()
                for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
                    let corner = CGPoint(x: c.x + half * sx, y: c.y + half * sy)
                    brackets.move(to: CGPoint(x: corner.x - arm * sx, y: corner.y))
                    brackets.addLine(to: corner)
                    brackets.addLine(to: CGPoint(x: corner.x, y: corner.y - arm * sy))
                }
                context.stroke(brackets, with: .color(tint.opacity(0.8)), lineWidth: 1.2)

                var ticks = Path()
                let r = d / 2
                for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    ticks.move(to: CGPoint(x: c.x + dx * (r + 4), y: c.y + dy * (r + 4)))
                    ticks.addLine(to: CGPoint(x: c.x + dx * (r + 14), y: c.y + dy * (r + 14)))
                }
                context.stroke(ticks, with: .color(tint.opacity(0.7)), lineWidth: 1)

                var dot = Path()
                dot.addEllipse(in: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3))
                context.fill(dot, with: .color(tint.opacity(0.9)))
            }
            .frame(width: d * 1.5, height: d * 1.5)

            VStack {
                Spacer()
                // The warning strip takes over this spot while the lance is live.
                if warning == nil {
                    CockpitCaption(lockLabel, color: tint)
                        .padding(.top, 4)
                }
            }
            .frame(width: d * 1.5, height: d * 1.5)
        }
        .hudGlow(tint, radius: 4)
        .position(x: size.width / 2, y: size.height * 0.52)
    }

    private var lockLabel: String {
        switch store.phase {
        case .weaponCharging: return "LANCE LOCK · \(store.currentBody.name)"
        case .weaponFiring: return "FIRING"
        case .hopping(let to): return "REALIGN → \(bodyName(to))"
        default: return "LOCK · \(store.currentBody.name)"
        }
    }

    // MARK: - Corner readouts

    private var readouts: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.currentBody.name.uppercased())
                        .font(.mono(22, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .hudGlow()
                    CockpitCaption(systemLine, color: Theme.dim)
                    CockpitCaption(kindLabel, color: Theme.dim)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    CockpitCaption(store.act.title, color: Theme.warn)
                    readout("HULL", String(format: "%3.0f%%", store.hull), color: Theme.hullColor(store.hull))
                    readout("ENERGY", "\(store.energy)", color: Theme.gain)
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    CockpitCaption("HINGE", color: Theme.dim)
                    Text("\(hinge.posture.label) · \(Int(hinge.angle.rounded()))°")
                        .font(.mono(10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    CockpitCaption("STATUS", color: Theme.dim)
                    Text(phaseLabel)
                        .font(.mono(10, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(10)
    }

    private func readout(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            CockpitCaption(label, color: Theme.dim)
            Text(value)
                .font(.mono(11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var systemLine: String {
        let system = store.currentSystem
        if system.distanceLY == 0 { return "\(system.name) · HOME SYSTEM" }
        return "\(system.name) · \(system.formattedDistance) FROM SOL"
    }

    private var kindLabel: String {
        let body = store.currentBody
        var parts: [String] = [kindName(body.kind)]
        if let cls = body.planetClass { parts.append(className(cls)) }
        if body.habitable { parts.append("HABITABLE") }
        if store.isClaimed(body.id) { parts.append("BEACON") }
        return parts.joined(separator: " · ")
    }

    private func kindName(_ kind: BodyKind) -> String {
        switch kind {
        case .star: return "STAR"
        case .planet: return "PLANET"
        case .dwarfPlanet: return "DWARF PLANET"
        case .blackHole: return "BLACK HOLE"
        case .galaxy: return "GALAXY"
        }
    }

    private func className(_ cls: PlanetClass) -> String {
        switch cls {
        case .rocky: return "ROCKY"
        case .lava: return "LAVA"
        case .desert: return "DESERT"
        case .ice: return "ICE"
        case .ocean: return "OCEAN"
        case .superEarth: return "SUPER-EARTH"
        case .gasGiant: return "GAS GIANT"
        case .iceGiant: return "ICE GIANT"
        case .earthlike: return "EARTHLIKE"
        }
    }

    private func bodyName(_ id: String) -> String {
        store.universe.body(id)?.1.name ?? id
    }

    private func systemName(_ id: String) -> String {
        store.universe.system(id)?.name ?? id
    }

    private var phaseLabel: String {
        switch store.phase {
        case .docked: return "DOCKED"
        case .orbit:
            if let target = store.targetSystem { return "TARGET → \(target.name.uppercased())" }
            return "ORBIT STABLE"
        case .hopping(let to): return "HOP → \(bodyName(to).uppercased())"
        case .warping(let to): return "FOLDING → \(systemName(to).uppercased())"
        case .sunDive: return "SUN DIVE \(Int(store.diveDepth * 100))%"
        case .weaponCharging: return "LANCE \(Int(store.weaponCharge * 100))%"
        case .weaponFiring: return "FIRING"
        case .blackHole: return "EVENT HORIZON"
        case .foldCoreCharging: return "FOLD CORE \(Int(store.foldCoreCharge * 100))% · PUMP \(hinge.pumpCount)/\(hinge.pumpTarget)"
        case .intergalacticJump: return "INTERGALACTIC FOLD"
        case .andromeda: return "ANDROMEDA"
        case .shipLost: return "SIGNAL LOST"
        }
    }

    private var phaseColor: Color {
        switch store.phase {
        case .weaponCharging, .weaponFiring, .shipLost: return Theme.danger
        case .sunDive, .foldCoreCharging: return Theme.warn
        case .hopping, .warping, .intergalacticJump: return Theme.gain
        default: return store.targetSystem == nil ? Theme.accent : Theme.warn
        }
    }

    // MARK: - Warning strip

    private var warning: Warning? {
        switch store.phase {
        case .weaponCharging:
            let ready = store.weaponCharge >= 0.6
            return Warning(
                text: ready ? "NOVA LANCE READY — SNAP OPEN TO FIRE" : "NOVA LANCE CHARGING — HOLD THE SQUEEZE",
                symbol: "bolt.horizontal.fill",
                color: ready ? Theme.danger : Theme.warn,
                meter: store.weaponCharge
            )
        case .weaponFiring:
            return Warning(text: "FIRING", symbol: "burst.fill", color: Theme.danger, meter: nil)
        default:
            break
        }
        if store.hull < 40 {
            return Warning(
                text: "HULL CRITICAL \(Int(store.hull))%",
                symbol: "exclamationmark.triangle.fill",
                color: Theme.danger,
                meter: store.hull / 100
            )
        }
        if case .foldCoreCharging = store.phase {
            return Warning(
                text: "PUMP THE HINGE · \(hinge.pumpCount)/\(hinge.pumpTarget)",
                symbol: "arrow.up.and.down",
                color: Theme.accent,
                meter: store.foldCoreCharge
            )
        }
        return nil
    }

    @ViewBuilder private var warningStrip: some View {
        ZStack {
            if let warning {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: warning.symbol)
                        Text(warning.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let meter = warning.meter {
                            CockpitMeter(value: meter, tint: warning.color)
                                .frame(width: 70)
                        }
                    }
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(warning.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(hazardStripes(warning.color))
                    .overlay(Rectangle().strokeBorder(warning.color.opacity(0.7), lineWidth: 1))
                    .opacity(stripPulse ? 1 : 0.65)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: stripPulse)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 38)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear { stripPulse = true }
                .onDisappear { stripPulse = false }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: warning)
    }

    private func hazardStripes(_ color: Color) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg.opacity(0.88)))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                stripe.addLine(to: CGPoint(x: x + size.height + 6, y: 0))
                stripe.addLine(to: CGPoint(x: x + 6, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(color.opacity(0.16)))
                x += 16
            }
        }
    }
}
