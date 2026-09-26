import SwiftUI

/// The outer display — what the commander sees while the iPhone Duo is closed (docked / in transit).
///
/// The Duo's 5.4" outer display shares the 7.6" inner display's aspect ratio, so in the simulator we
/// render this view full-screen and frame it with a proportional bezel (same aspect as the container,
/// scaled by ≈ 5.4 / 7.6) to stand in for the real outer panel. On hardware the same content simply
/// fills the outer screen. All readouts are live: the phase card keys off `store.phase`.
struct OuterDisplayView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = 0.74
            let w = max(120, geo.size.width * scale)
            let h = max(120, geo.size.height * scale)
            let isWide = w > h
            ZStack {
                Color.black.ignoresSafeArea()

                // Bezel
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color(hex: "0A0C14"))
                    .frame(width: w + 26, height: h + 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: Theme.accent.opacity(0.10), radius: 34)

                // Outer panel content
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                    OuterStatusCard(now: tl.date, isWide: isWide)
                }
                .frame(width: w, height: h)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Theme.accent.opacity(0.22), lineWidth: 1)
                )

                // Front camera punch-hole on the bezel edge
                Circle()
                    .fill(Color.black)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .offset(y: isWide ? -(h / 2) - 5 : -(h / 2) - 6)
                    .offset(x: isWide ? -(w / 2) + 20 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
    }
}

// MARK: - Card router

private struct OuterStatusCard: View {
    @Environment(GameStore.self) private var store
    let now: Date
    let isWide: Bool

    var body: some View {
        Group {
            switch store.phase {
            case .warping(let to):
                OuterWarpCard(now: now, destinationID: to, intergalactic: false)
            case .intergalacticJump:
                OuterWarpCard(now: now, destinationID: SystemID.andromeda, intergalactic: true)
            case .foldCoreCharging:
                OuterFoldCoreCard(now: now)
            default:
                OuterDockedCard(now: now, isWide: isWide)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Faint scanline texture so the panel reads as a display, not a flat rect.
            OuterScanlines().opacity(0.35)
        )
    }
}

// MARK: - Docked / orbit / everything else

private struct OuterDockedCard: View {
    @Environment(GameStore.self) private var store
    let now: Date
    let isWide: Bool

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        let pulse = 0.5 + 0.5 * sin(t * 2.2)
        let status = OuterPhaseLabel.label(for: store.phase)

        VStack(alignment: .leading, spacing: 10) {
            OuterTopRow(status: status.text, color: status.color)

            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    locationBlock
                    Spacer(minLength: 4)
                    shipBlock
                }
            } else {
                locationBlock
                shipBlock
            }

            Spacer(minLength: 0)

            Text(store.phase == .shipLost ? "OPEN THE PHONE TO DEPLOY A BACKUP SHIP" : "OPEN THE PHONE TO FLY")
                .font(.mono(11, weight: .bold))
                .foregroundStyle(store.phase == .shipLost ? Theme.danger : Theme.accent)
                .opacity(0.55 + 0.45 * pulse)
                .shadow(color: Theme.accent.opacity(0.6 * pulse), radius: 8)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            OuterClocks(now: now)
        }
    }

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("POSITION").font(.mono(8)).foregroundStyle(Theme.dim)
            Text(store.currentSystem.name.uppercased())
                .font(.mono(22, weight: .bold))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.7), radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                Image(systemName: "location.north.line.fill").font(.system(size: 9))
                Text(store.currentBody.name.uppercased())
                    .font(.mono(12, weight: .semibold))
                if store.isClaimed(store.currentBody.id) {
                    Text("✓").font(.mono(11, weight: .bold)).foregroundStyle(Theme.gain)
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(store.currentSystem.formattedDistance == "HOME" ? "HOME SYSTEM" : "\(store.currentSystem.formattedDistance) FROM SOL")
                .font(.mono(9))
                .foregroundStyle(Theme.dim)
            Text(store.act.title)
                .font(.mono(9, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .padding(.top, 2)
        }
    }

    private var shipBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // Hull ring
                ZStack {
                    OuterRing(progress: store.hull / 100, color: hullColor, lineWidth: 5, size: 58)
                    VStack(spacing: 0) {
                        Text("\(Int(store.hull.rounded()))")
                            .font(.mono(14, weight: .bold))
                            .foregroundStyle(hullColor)
                        Text("HULL").font(.mono(7)).foregroundStyle(Theme.dim)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 12))
                        Text("\(store.energy)")
                            .font(.mono(22, weight: .bold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(Theme.gain)
                    .shadow(color: Theme.gain.opacity(0.5), radius: 6)
                    Text("ENERGY").font(.mono(8)).foregroundStyle(Theme.dim)
                }
            }

            // Drive parts — three slots
            VStack(alignment: .leading, spacing: 4) {
                Text(store.hasWarpDrive ? "WARP DRIVE · ONLINE" : "WARP DRIVE · \(store.save.driveParts.count)/3 PARTS")
                    .font(.mono(8, weight: .semibold))
                    .foregroundStyle(store.hasWarpDrive ? Theme.gain : Theme.warn)
                HStack(spacing: 8) {
                    ForEach(DrivePart.allCases) { part in
                        OuterPartSlot(part: part, installed: store.save.driveParts.contains(part))
                    }
                }
            }

            HStack(spacing: 12) {
                OuterStat(label: "CLAIMED", value: "\(store.save.claimed.count)", color: Theme.gain)
                OuterStat(label: "DESTROYED", value: "\(store.save.destroyed.count)", color: store.save.destroyed.isEmpty ? Theme.dim : Theme.danger)
                if store.save.hasWeapon {
                    OuterStat(label: "NOVA LANCE", value: "ARMED", color: Theme.warn)
                }
                if store.save.solarCoreSample {
                    OuterStat(label: "CORE SAMPLE", value: "✓", color: Theme.gain)
                }
            }
        }
    }

    private var hullColor: Color {
        if store.hull > 60 { return Theme.gain }
        if store.hull > 30 { return Theme.warn }
        return Theme.danger
    }
}

// MARK: - Warping / intergalactic fold

private struct OuterWarpCard: View {
    @Environment(GameStore.self) private var store
    let now: Date
    let destinationID: String
    let intergalactic: Bool

    private static let andromedaDistanceLY: Double = 2_537_000

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        let pulse = 0.5 + 0.5 * sin(t * 4)
        let progress = max(0, min(1, store.transitProgress))
        let eased = 1 - pow(1 - progress, 3)
        let destination = store.universe.system(destinationID)
        let totalLY: Double = intergalactic
            ? Self.andromedaDistanceLY
            : (destination.map { store.universe.distance(from: store.currentSystem, to: $0) } ?? 0)
        let travelled = totalLY * eased
        let stability = max(0, min(1, store.lastWarpQuality))
        // Low-quality closes make the bubble flicker on the readout.
        let jitter = stability < 0.45 ? 0.08 * sin(t * 23) * sin(t * 7.3) : 0.015 * sin(t * 5)
        let shownStability = max(0, min(1, stability + jitter))
        let stabilityColor: Color = stability >= 0.45 ? Theme.gain : Theme.danger

        VStack(alignment: .leading, spacing: 10) {
            OuterTopRow(status: intergalactic ? "INTERGALACTIC FOLD" : "FOLDING SPACE", color: Theme.accent)

            // Fold tunnel
            OuterFoldTunnel(time: t, progress: progress)
                .frame(maxWidth: .infinity)
                .frame(height: 70)

            VStack(alignment: .leading, spacing: 3) {
                Text(intergalactic ? "MILKY WAY → ANDROMEDA" : "DESTINATION")
                    .font(.mono(8))
                    .foregroundStyle(Theme.dim)
                Text((destination?.name ?? destinationID).uppercased())
                    .font(.mono(22, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.5 + 0.4 * pulse), radius: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(OuterFormat.lightYears(travelled))
                    .font(.mono(26, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("OF \(OuterFormat.lightYears(totalLY).uppercased()) · \(Int((progress * 100).rounded()))%")
                    .font(.mono(9))
                    .foregroundStyle(Theme.dim)
            }

            OuterBar(progress: progress, color: Theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("BUBBLE STABILITY").font(.mono(8)).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(Int((shownStability * 100).rounded()))%")
                        .font(.mono(9, weight: .semibold))
                        .foregroundStyle(stabilityColor)
                }
                OuterBar(progress: shownStability, color: stabilityColor)
                if stability < 0.45 {
                    Text("WARNING · BUBBLE UNSTABLE — CLOSED TOO \(stability < 0.3 ? "FAST" : "SLOWLY")")
                        .font(.mono(8, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .opacity(0.5 + 0.5 * pulse)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Text(intergalactic ? "KEEP THE PHONE CLOSED · 2.5 MILLION LIGHT-YEARS" : "KEEP THE PHONE CLOSED UNTIL ARRIVAL")
                .font(.mono(9, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .opacity(0.6 + 0.4 * pulse)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            OuterClocks(now: now)
        }
    }
}

// MARK: - Fold Core charging

private struct OuterFoldCoreCard: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge
    let now: Date

    var body: some View {
        let t = now.timeIntervalSinceReferenceDate
        let pulse = 0.5 + 0.5 * sin(t * 3)
        let charge = max(0, min(1, store.foldCoreCharge))
        let charged = charge >= 0.999

        VStack(alignment: .leading, spacing: 10) {
            OuterTopRow(status: "FOLD CORE", color: charged ? Theme.gain : Theme.accent)

            HStack {
                Spacer(minLength: 0)
                ZStack {
                    OuterRing(progress: charge, color: charged ? Theme.gain : Theme.accent, lineWidth: 9, size: 128)
                    Circle()
                        .stroke(Theme.accent.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 5], dashPhase: CGFloat(t * 20)))
                        .frame(width: 152, height: 152)
                    VStack(spacing: 2) {
                        Text("\(Int((charge * 100).rounded()))%")
                            .font(.mono(28, weight: .bold))
                            .foregroundStyle(charged ? Theme.gain : .white)
                            .monospacedDigit()
                        Text("PUMPS \(hinge.pumpCount)/\(hinge.pumpTarget)")
                            .font(.mono(9))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .shadow(color: (charged ? Theme.gain : Theme.accent).opacity(0.3 + 0.3 * pulse), radius: 18)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("TARGET").font(.mono(8)).foregroundStyle(Theme.dim)
                Text((store.targetSystem?.name ?? "ANDROMEDA").uppercased())
                    .font(.mono(18, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("2,537,000 ly · HINGE \(Int(hinge.angle))°")
                    .font(.mono(9))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)

            Text(charged ? "CORE CHARGED · CLOSE THE PHONE TO FOLD" : "OPEN AND PUMP")
                .font(.mono(charged ? 11 : 16, weight: .bold))
                .foregroundStyle(charged ? Theme.gain : Theme.warn)
                .opacity(0.55 + 0.45 * pulse)
                .shadow(color: (charged ? Theme.gain : Theme.warn).opacity(0.7), radius: 8)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            OuterClocks(now: now)
        }
    }
}

// MARK: - Shared pieces

private struct OuterTopRow: View {
    @Environment(GameStore.self) private var store
    let status: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.9), radius: 4)
                Text(status)
                    .font(.mono(11, weight: .bold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 4)
            Text(store.save.callsign.uppercased())
                .font(.mono(9))
                .foregroundStyle(Theme.dim)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct OuterClocks: View {
    @Environment(GameStore.self) private var store
    let now: Date

    var body: some View {
        let years = store.save.earthYearsElapsed
        let earthDate = now.addingTimeInterval(years * 365.25 * 86_400)
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SHIP CLOCK").font(.mono(7)).foregroundStyle(Theme.dim)
                Text(now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("EARTH CLOCK").font(.mono(7)).foregroundStyle(Theme.dim)
                Text(earthDate.formatted(.dateTime.year().month(.abbreviated).day()))
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(years > 0 ? Theme.warn : Theme.accent)
                    .monospacedDigit()
                Text(years > 0 ? "+\(OuterFormat.years(years)) DILATION" : "NO DILATION")
                    .font(.mono(7))
                    .foregroundStyle(Theme.dim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.top, 4)
        .overlay(alignment: .top) { Rectangle().fill(Theme.accent.opacity(0.2)).frame(height: 1) }
    }
}

private struct OuterRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 5
    var size: CGFloat = 56

    var body: some View {
        let p = CGFloat(max(0, min(1, progress)))
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.8), radius: 6)
                .animation(.easeOut(duration: 0.25), value: p)
        }
        .frame(width: size, height: size)
    }
}

private struct OuterBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            let p = CGFloat(max(0, min(1, progress)))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, g.size.width * p))
                    .shadow(color: color.opacity(0.8), radius: 5)
            }
        }
        .frame(height: 6)
    }
}

private struct OuterPartSlot: View {
    let part: DrivePart
    let installed: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(installed ? Theme.accent.opacity(0.14) : Color.clear)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(installed ? Theme.accent : Theme.dim.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: installed ? [] : [3, 3]))
                Image(systemName: part.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(installed ? Theme.accent : Theme.dim.opacity(0.5))
                    .shadow(color: installed ? Theme.accent.opacity(0.8) : .clear, radius: 5)
            }
            .frame(width: 34, height: 34)
            Text(shortLabel)
                .font(.mono(6))
                .foregroundStyle(installed ? Theme.accent : Theme.dim)
                .lineLimit(1)
        }
    }

    private var shortLabel: String {
        switch part {
        case .exoticMatter: return "EXOTIC"
        case .fieldCoil: return "COIL"
        case .navigationCore: return "NAV"
        }
    }
}

private struct OuterStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.mono(7)).foregroundStyle(Theme.dim)
            Text(value).font(.mono(12, weight: .bold)).foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Concentric ellipses rushing outward — the inside of the warp bubble as seen from the outer display.
private struct OuterFoldTunnel: View {
    let time: Double
    let progress: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = max(size.width, size.height) * 0.55
            let speed = 0.25 + progress * 0.6
            for i in 0..<10 {
                let f = (time * speed + Double(i) / 10).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(f * f) * maxR
                let alpha = (1 - f) * 0.7
                let rect = CGRect(x: c.x - r, y: c.y - r * 0.42, width: r * 2, height: r * 0.84)
                ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(alpha)), lineWidth: 1)
            }
            // Streaks
            for i in 0..<14 {
                let a = Double(i) / 14 * .pi * 2 + time * 0.1
                let f = (time * (speed * 1.6) + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let r0 = CGFloat(f) * maxR
                let r1 = r0 + 6 + CGFloat(f) * 18
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0 * 0.42))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1 * 0.42))
                ctx.stroke(p, with: .color(Color.white.opacity((1 - f) * 0.5)), lineWidth: 1)
            }
            let core = 3 + CGFloat(0.5 + 0.5 * sin(time * 6)) * 2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)),
                     with: .color(Color.white))
        }
    }
}

private struct OuterScanlines: View {
    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            var y: CGFloat = 0
            var path = Path()
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 3
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Helpers

private enum OuterPhaseLabel {
    static func label(for phase: FlightPhase) -> (text: String, color: Color) {
        switch phase {
        case .docked: return ("DOCKED", Theme.accent)
        case .orbit: return ("IN ORBIT", Theme.accent)
        case .hopping: return ("HOPPING", Theme.accent)
        case .warping: return ("FOLDING SPACE", Theme.accent)
        case .sunDive: return ("SUN DIVE", Theme.warn)
        case .weaponCharging, .weaponFiring: return ("NOVA LANCE", Theme.warn)
        case .blackHole: return ("EVENT HORIZON", Theme.warn)
        case .foldCoreCharging: return ("FOLD CORE", Theme.accent)
        case .intergalacticJump: return ("INTERGALACTIC FOLD", Theme.accent)
        case .andromeda: return ("ANDROMEDA", Theme.gain)
        case .shipLost: return ("SHIP LOST", Theme.danger)
        }
    }
}

private enum OuterFormat {
    /// "4.24 ly" under 100 ly, otherwise grouped integers ("2,537,000 ly").
    static func lightYears(_ v: Double) -> String {
        if v < 100 { return String(format: "%.2f ly", v) }
        return "\(Int(v.rounded()).formatted()) ly"
    }

    static func years(_ v: Double) -> String {
        if v < 10 { return String(format: "%.1f y", v) }
        return "\(Int(v.rounded()).formatted()) y"
    }
}
