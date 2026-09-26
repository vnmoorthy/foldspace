import SwiftUI

/// The galaxy map — shown when the iPhone Duo is laid flat (hinge ≥ 170°) and the whole 7.6" inner
/// display is one canvas. ~70 % of the width is a `Canvas` star chart, ~30 % a target panel.
///
/// Interaction: tap a star to select it and (if it is reachable) make it the warp target. Then lift
/// the phone off the table and close it — FlightController turns the `.warpClose` gesture into a
/// fold-space jump to `store.targetSystemID`. In portrait the panel drops below the chart instead.
struct GalaxyMapView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    /// System whose card is shown in the side panel (falls back to target, then current).
    @State private var selectedID: String?
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    private let hitRadius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width >= geo.size.height * 1.15
            ZStack {
                Theme.bg.ignoresSafeArea()
                if isWide {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            header
                            chart
                        }
                        Rectangle().fill(Theme.accent.opacity(0.25)).frame(width: 1)
                        GalaxySidePanel(systemID: panelSystemID)
                            .frame(width: geo.size.width * 0.30)
                    }
                } else {
                    VStack(spacing: 0) {
                        header
                        chart
                        Rectangle().fill(Theme.accent.opacity(0.25)).frame(height: 1)
                        GalaxySidePanel(systemID: panelSystemID)
                            .frame(height: geo.size.height * 0.34)
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    private var panelSystemID: String? { selectedID ?? store.targetSystemID ?? store.save.systemID }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Text("GALAXY MAP · LAY FLAT")
                .font(.mono(13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.7), radius: 6)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill").font(.system(size: 10))
                Text("\(store.energy)").font(.mono(12, weight: .semibold))
            }
            .foregroundStyle(Theme.gain)
            Text(store.act.title)
                .font(.mono(11))
                .foregroundStyle(Theme.dim)
            Text("\(Int(hinge.angle))°")
                .font(.mono(11))
                .foregroundStyle(Theme.dim)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent.opacity(0.35)).frame(height: 1) }
    }

    // MARK: - Chart

    private var chart: some View {
        GeometryReader { g in
            let model = ChartModel(store: store, selectedID: selectedID)
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: false) { ctx, size in
                    Self.drawChart(&ctx, size: size, time: t, model: model)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                handleTap(value.location, size: g.size, model: model)
            })
            .overlay(alignment: .bottom) {
                if let toastText {
                    Text(toastText)
                        .font(.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.panel.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(Theme.warn.opacity(0.5), lineWidth: 1))
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 10) {
                    legend("◉", "CURRENT", Theme.accent)
                    legend("◎", "TARGET", Theme.warn)
                    legend("●", "CLAIMED", Theme.gain)
                    legend("◌", "LOCKED", Theme.dim)
                }
                .padding(8)
            }
        }
        .clipped()
    }

    private func legend(_ glyph: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(glyph).foregroundStyle(color)
            Text(text).foregroundStyle(Theme.dim)
        }
        .font(.mono(8))
    }

    // MARK: - Tap handling

    private func handleTap(_ p: CGPoint, size: CGSize, model: ChartModel) {
        let positions = ChartModel.positions(for: model.nodes, in: size)
        var bestID: String?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for node in model.nodes {
            guard let q = positions[node.id] else { continue }
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= hitRadius, d < bestDistance {
                bestDistance = d
                bestID = node.id
            }
        }
        guard let id = bestID, let system = store.universe.system(id) else { return }
        selectedID = id

        if id == store.save.systemID {
            Haptics.tap()
            let msg = "Already in \(system.name)."
            store.log(msg)
            showToast(msg)
            return
        }
        guard store.isUnlocked(system) else {
            Haptics.warning()
            let actTitle = Act(rawValue: system.act)?.title ?? "ACT \(system.act)"
            let msg = "\(system.name) is locked — reach \(actTitle)."
            store.log(msg, .danger)
            showToast(msg)
            return
        }
        store.targetSystemID = id
        Haptics.tap()
        showToast("TARGET: \(system.name.uppercased()) · \(system.formattedDistance)")
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toastText = text }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.3)) { toastText = nil }
        }
    }

    // MARK: - Drawing

    private static func drawChart(_ ctx: inout GraphicsContext, size: CGSize, time t: Double, model: ChartModel) {
        let positions = ChartModel.positions(for: model.nodes, in: size)
        let labelsAbove = ChartModel.labelsAbove(for: model.nodes, positions: positions)

        // 1. Distant star field (deterministic so it doesn't flicker; gentle twinkle).
        for s in starfield {
            let tw = 0.55 + 0.45 * sin(t * s.speed + s.phase)
            let r = s.r
            let rect = CGRect(x: s.x * size.width - r, y: s.y * size.height - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(s.alpha * tw)))
        }

        // 2. Milky Way band — a faint blurred diagonal, brighter towards the galactic core.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(14, size.height * 0.06)))
            var band = Path()
            band.move(to: CGPoint(x: -size.width * 0.1, y: size.height * 0.88))
            band.addQuadCurve(to: CGPoint(x: size.width * 1.1, y: size.height * 0.08),
                              control: CGPoint(x: size.width * 0.45, y: size.height * 0.55))
            layer.stroke(band, with: .color(Color.white.opacity(0.075)), lineWidth: size.height * 0.24)
            layer.stroke(band, with: .color(Theme.accent.opacity(0.05)), lineWidth: size.height * 0.10)
            if let core = model.nodes.first(where: { $0.kind == .blackHole }), let c = positions[core.id] {
                let r = max(40, size.height * 0.18)
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2)),
                           with: .color(Theme.warn.opacity(0.10)))
            }
        }

        // 3. Route: dashed line from the current system to the target.
        if let target = model.targetID, let a = positions[model.currentID], let b = positions[target] {
            var route = Path()
            route.move(to: a)
            route.addLine(to: b)
            ctx.stroke(route, with: .color(Theme.accent.opacity(0.25)), lineWidth: 4)
            ctx.stroke(route, with: .color(Theme.accent.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 6], dashPhase: CGFloat(-t * 40)))
            // A travelling spark along the route.
            let f = CGFloat((t * 0.45).truncatingRemainder(dividingBy: 1))
            let spark = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            ctx.fill(Path(ellipseIn: CGRect(x: spark.x - 2.5, y: spark.y - 2.5, width: 5, height: 5)), with: .color(Theme.accent))
        }

        // 4. Systems.
        for node in model.nodes {
            guard let p = positions[node.id] else { continue }
            let isCurrent = node.id == model.currentID
            let isTarget = node.id == model.targetID
            let isSelected = node.id == model.selectedID

            ctx.drawLayer { layer in
                if !node.unlocked && !isCurrent { layer.opacity = 0.42 }
                switch node.kind {
                case .galaxy:
                    drawAndromeda(&layer, at: p, time: t, unlocked: node.unlocked)
                case .blackHole:
                    drawBlackHole(&layer, at: p, radius: node.radius, time: t)
                default:
                    drawStar(&layer, at: p, radius: node.radius, color: node.color, claimed: node.claimed)
                }
            }

            // Claimed halo (cyan glow) — drawn at full opacity so it reads even on a dim node.
            if node.claimed {
                let r = node.radius + 6
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Theme.accent.opacity(0.7)), lineWidth: 2)
                }
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(Theme.accent.opacity(0.9)), lineWidth: 1)
            }

            // Home marker for Sol.
            if node.id == SystemID.sol {
                let r = node.radius + 11
                var diamond = Path()
                diamond.move(to: CGPoint(x: p.x, y: p.y - r))
                diamond.addLine(to: CGPoint(x: p.x + r, y: p.y))
                diamond.addLine(to: CGPoint(x: p.x, y: p.y + r))
                diamond.addLine(to: CGPoint(x: p.x - r, y: p.y))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(Theme.gain.opacity(0.8)), lineWidth: 1)
                let home = ctx.resolve(Text(Image(systemName: "house.fill")).font(.system(size: 8)).foregroundStyle(Theme.gain))
                ctx.draw(home, at: CGPoint(x: p.x - r - 7, y: p.y - r + 2), anchor: .center)
            }

            // Current system pulse.
            if isCurrent {
                let pulse = 0.5 + 0.5 * sin(t * 3)
                let r = node.radius + 8 + CGFloat(pulse) * 6
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(Theme.accent.opacity(0.9 - 0.6 * pulse)), lineWidth: 1.5)
                let r2 = node.radius + 5
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r2, y: p.y - r2, width: r2 * 2, height: r2 * 2)),
                           with: .color(Theme.accent), lineWidth: 1)
            }

            // Targeting ring (rotating dashes + 4 ticks).
            if isTarget {
                let r = node.radius + 14
                let ring = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.stroke(ring, with: .color(Theme.warn.opacity(0.25)), lineWidth: 5)
                ctx.stroke(ring, with: .color(Theme.warn),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 5], dashPhase: CGFloat(t * 25)))
                var ticks = Path()
                for i in 0..<4 {
                    let a: Double = Double(i) * .pi / 2 + .pi / 4
                    let ca: CGFloat = CGFloat(Foundation.cos(a))
                    let sa: CGFloat = CGFloat(Foundation.sin(a))
                    let inner = CGPoint(x: p.x + ca * (r + 3), y: p.y + sa * (r + 3))
                    let outer = CGPoint(x: p.x + ca * (r + 9), y: p.y + sa * (r + 9))
                    ticks.move(to: inner)
                    ticks.addLine(to: outer)
                }
                ctx.stroke(ticks, with: .color(Theme.warn), lineWidth: 1.5)
            } else if isSelected, !isCurrent {
                let r = node.radius + 12
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(Color.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // Lock glyph (to the right of the node so it never sits on a label).
            if !node.unlocked {
                let lock = ctx.resolve(Text(Image(systemName: "lock.fill")).font(.system(size: 9)).foregroundStyle(Theme.dim))
                ctx.draw(lock, at: CGPoint(x: p.x + node.radius + 10, y: p.y - 1), anchor: .center)
            }

            // Labels.
            if node.kind == .galaxy {
                let label = ctx.resolve(Text("ANDROMEDA · 2.5 M ly")
                    .font(.mono(9, weight: .bold))
                    .foregroundStyle(node.unlocked ? Theme.accent : Theme.dim))
                ctx.draw(label, at: CGPoint(x: p.x + 16, y: p.y + 26), anchor: .topTrailing)
            } else {
                let nameColor: Color = isCurrent ? Theme.accent : (isTarget ? Theme.warn : (node.unlocked ? Color.white : Theme.dim))
                let name = ctx.resolve(Text(node.name.uppercased()).font(.mono(10, weight: .bold)).foregroundStyle(nameColor))
                let dist = ctx.resolve(Text(node.distance).font(.mono(8)).foregroundStyle(Theme.dim))
                if labelsAbove.contains(node.id) {
                    ctx.draw(name, at: CGPoint(x: p.x, y: p.y - node.radius - 13), anchor: .bottom)
                    ctx.draw(dist, at: CGPoint(x: p.x, y: p.y - node.radius - 25), anchor: .bottom)
                } else {
                    ctx.draw(name, at: CGPoint(x: p.x, y: p.y + node.radius + 14), anchor: .top)
                    ctx.draw(dist, at: CGPoint(x: p.x, y: p.y + node.radius + 26), anchor: .top)
                }
            }
        }
    }

    private static func drawStar(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, claimed: Bool) {
        let glowR = radius * 3
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 1.6))
            layer.fill(Path(ellipseIn: CGRect(x: p.x - glowR, y: p.y - glowR, width: glowR * 2, height: glowR * 2)),
                       with: .color(color.opacity(0.35)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(color))
        let core = radius * 0.45
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                 with: .color(Color.white.opacity(0.85)))
    }

    private static func drawBlackHole(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, time t: Double) {
        // Accretion glow
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: radius))
            let r = radius * 2.2
            layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.55, width: r * 2, height: r * 1.1)),
                       with: .color(Theme.warn.opacity(0.45)))
        }
        // Orange ring (photon sphere)
        let ringR = radius + 3
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ringR, y: p.y - ringR, width: ringR * 2, height: ringR * 2)),
                   with: .color(Theme.warn), lineWidth: 2)
        // Rotating accretion disc
        let discR = radius + 8
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - discR, y: p.y - discR * 0.4, width: discR * 2, height: discR * 0.8)),
                   with: .color(Theme.warn.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 4], dashPhase: CGFloat(t * 18)))
        // Event horizon
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(.black))
    }

    private static func drawAndromeda(_ ctx: inout GraphicsContext, at p: CGPoint, time t: Double, unlocked: Bool) {
        let armLength: CGFloat = 20
        let tilt: Double = 0.55
        let cosTilt: CGFloat = CGFloat(Foundation.cos(tilt))
        let sinTilt: CGFloat = CGFloat(Foundation.sin(tilt))
        let rotation = t * 0.25
        var spiral = Path()
        for arm in 0..<2 {
            let offset = Double(arm) * .pi
            var first = true
            for i in 0...36 {
                let th = Double(i) / 36 * 2.3 * .pi
                let r = armLength * CGFloat(th / (2.3 * .pi))
                let ang = th + offset + rotation
                let raw = CGPoint(x: cos(ang) * r, y: sin(ang) * r * 0.55)
                let x = raw.x * cosTilt - raw.y * sinTilt
                let y = raw.x * sinTilt + raw.y * cosTilt
                let q = CGPoint(x: p.x + x, y: p.y + y)
                if first { spiral.move(to: q); first = false } else { spiral.addLine(to: q) }
            }
        }
        let tint = unlocked ? Theme.accent : Color.white
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            let r = armLength * 1.1
            layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4)),
                       with: .color(tint.opacity(0.22)))
        }
        ctx.stroke(spiral, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Color.white))
    }

    // MARK: - Star field

    private struct BackStar {
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
        let alpha: Double
        let speed: Double
        let phase: Double
    }

    private static let starfield: [BackStar] = {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        var stars: [BackStar] = []
        stars.reserveCapacity(220)
        for _ in 0..<220 {
            stars.append(BackStar(x: CGFloat(next()), y: CGFloat(next()), r: CGFloat(0.4 + next() * 1.1),
                                  alpha: 0.15 + next() * 0.55, speed: 0.6 + next() * 1.8, phase: next() * .pi * 2))
        }
        return stars
    }()
}

// MARK: - Chart model (snapshot of store state taken in `body`, so the Canvas closure stays pure)

private struct ChartModel {
    struct Node {
        let id: String
        let name: String
        let distance: String
        let kind: BodyKind
        let color: Color
        let radius: CGFloat
        let unlocked: Bool
        let claimed: Bool
        let map: MapPoint
    }

    let nodes: [Node]
    let currentID: String
    let targetID: String?
    let selectedID: String?

    @MainActor
    init(store: GameStore, selectedID: String?) {
        nodes = store.universe.systems.map { s in
            let radius: CGFloat
            switch s.primary.kind {
            case .blackHole: radius = 9
            case .galaxy: radius = 10
            default: radius = min(8, max(4, 4 + CGFloat(log10(max(1, s.primary.radiusEarths))) * 1.6))
            }
            return Node(id: s.id,
                        name: s.name,
                        distance: s.formattedDistance,
                        kind: s.primary.kind,
                        color: Color(hex: s.primary.colorHex),
                        radius: radius,
                        unlocked: store.isUnlocked(s),
                        claimed: s.allBodies.contains { store.isClaimed($0.id) },
                        map: s.map)
        }
        currentID = store.save.systemID
        targetID = store.targetSystemID
        self.selectedID = selectedID
    }

    /// Screen positions for every system. Andromeda is pinned to the top-right corner regardless of its
    /// map coordinate (it lies far off the Milky Way's unit square).
    ///
    /// The Milky Way systems are spread over the whole chart by normalising their bounding box: the solar
    /// neighbourhood (everything in Act II is within ~12 ly) occupies only a slice of the unit square, and
    /// mapping it 1:1 would pile the stars — and their labels — into one corner.
    static func positions(for nodes: [Node], in size: CGSize) -> [String: CGPoint] {
        let insetX: CGFloat = min(60, size.width * 0.12)
        let insetTop: CGFloat = min(48, size.height * 0.13)
        let insetBottom: CGFloat = min(64, size.height * 0.18)
        let rect = CGRect(x: insetX, y: insetTop,
                          width: max(1, size.width - insetX * 2),
                          height: max(1, size.height - insetTop - insetBottom))

        let galactic = nodes.filter { $0.kind != .galaxy }
        var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0
        for n in galactic {
            minX = min(minX, n.map.x); maxX = max(maxX, n.map.x)
            minY = min(minY, n.map.y); maxY = max(maxY, n.map.y)
        }
        let spanX = maxX - minX, spanY = maxY - minY
        let useBox = galactic.count > 1 && spanX > 0.05 && spanY > 0.05

        var out: [String: CGPoint] = [:]
        for n in nodes {
            if n.kind == .galaxy {
                out[n.id] = CGPoint(x: rect.maxX + 6, y: rect.minY - 6)
            } else {
                var ux = min(1, max(0, n.map.x))
                var uy = min(1, max(0, n.map.y))
                if useBox {
                    ux = (n.map.x - minX) / spanX
                    uy = (n.map.y - minY) / spanY
                }
                out[n.id] = CGPoint(x: rect.minX + CGFloat(ux) * rect.width,
                                    y: rect.minY + CGFloat(uy) * rect.height)
            }
        }
        return out
    }

    /// Systems whose labels should sit above the node because another system lies just below them.
    static func labelsAbove(for nodes: [Node], positions: [String: CGPoint]) -> Set<String> {
        var above = Set<String>()
        for n in nodes where n.kind != .galaxy {
            guard let p = positions[n.id] else { continue }
            for m in nodes where m.id != n.id && m.kind != .galaxy {
                guard let q = positions[m.id] else { continue }
                if abs(q.x - p.x) < 70, q.y > p.y, q.y - p.y < 42 {
                    above.insert(n.id)
                    break
                }
            }
        }
        return above
    }
}

// MARK: - Side panel

private struct GalaxySidePanel: View {
    @Environment(GameStore.self) private var store
    let systemID: String?

    var body: some View {
        let system = systemID.flatMap { store.universe.system($0) } ?? store.currentSystem
        let unlocked = store.isUnlocked(system)
        let isCurrent = system.id == store.save.systemID
        let isTarget = store.targetSystemID == system.id
        let missingParts = DrivePart.allCases.count - store.save.driveParts.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(system.name.uppercased())
                    .font(.mono(17, weight: .bold))
                    .foregroundStyle(unlocked ? Theme.accent : Theme.dim)
                    .shadow(color: unlocked ? Theme.accent.opacity(0.6) : .clear, radius: 5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                statusBadge(isCurrent: isCurrent, isTarget: isTarget, unlocked: unlocked)
            }

            HStack(spacing: 8) {
                GalaxyTag(label: "DIST", value: system.formattedDistance, color: .white)
                GalaxyTag(label: "COST", value: "\(system.warpCost)⚡",
                          color: store.energy >= system.warpCost ? Theme.gain : Theme.danger)
                GalaxyTag(label: "ACT", value: roman(system.act), color: .white)
            }

            Text(system.lore)
                .font(.mono(9))
                .foregroundStyle(Theme.dim)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.accent.opacity(0.2)).frame(height: 1)

            Text("BODIES · \(system.allBodies.count)")
                .font(.mono(9, weight: .semibold))
                .foregroundStyle(Theme.dim)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(system.allBodies) { body in
                        bodyRow(body, inCurrentSystem: isCurrent)
                    }
                }
            }

            Spacer(minLength: 0)

            actionArea(system: system, unlocked: unlocked, isCurrent: isCurrent, isTarget: isTarget)

            if !store.hasWarpDrive {
                Text("WARP DRIVE OFFLINE · \(missingParts) PART\(missingParts == 1 ? "" : "S") MISSING")
                    .font(.mono(8, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
    }

    @ViewBuilder
    private func statusBadge(isCurrent: Bool, isTarget: Bool, unlocked: Bool) -> some View {
        let text: String = isCurrent ? "HERE" : (isTarget ? "TARGET" : (unlocked ? "IN RANGE" : "LOCKED"))
        let color: Color = isCurrent ? Theme.accent : (isTarget ? Theme.warn : (unlocked ? Theme.gain : Theme.dim))
        Text(text)
            .font(.mono(8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private func bodyRow(_ body: CelestialBody, inCurrentSystem: Bool) -> some View {
        let claimed = store.isClaimed(body.id)
        let destroyed = store.isDestroyed(body.id)
        let isHere = inCurrentSystem && body.id == store.save.bodyID
        HStack(spacing: 6) {
            Image(systemName: glyph(for: body))
                .font(.system(size: 8))
                .foregroundStyle(destroyed ? Theme.dim : Color(hex: body.colorHex))
                .frame(width: 10)
            Text(body.name)
                .font(.mono(10, weight: isHere ? .bold : .regular))
                .foregroundStyle(destroyed ? Theme.dim : (isHere ? Theme.accent : .white))
                .strikethrough(destroyed, color: Theme.danger)
                .lineLimit(1)
            if let part = body.drivePart, claimed {
                Image(systemName: part.symbol)
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.gain)
            }
            if body.habitable, !destroyed {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.gain.opacity(0.8))
            }
            Spacer(minLength: 2)
            if destroyed {
                Text("✗").font(.mono(11, weight: .bold)).foregroundStyle(Theme.danger)
            } else if claimed {
                Text("✓").font(.mono(11, weight: .bold)).foregroundStyle(Theme.gain)
            } else {
                Text("·").font(.mono(11)).foregroundStyle(Theme.dim)
            }
        }
    }

    @ViewBuilder
    private func actionArea(system: StarSystem, unlocked: Bool, isCurrent: Bool, isTarget: Bool) -> some View {
        if isTarget, !isCurrent {
            Text("LIFT THE PHONE, THEN CLOSE IT TO FOLD SPACE")
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Theme.warn)
                .shadow(color: Theme.warn.opacity(0.8), radius: 6)
                .fixedSize(horizontal: false, vertical: true)
            if system.id == SystemID.andromeda, store.foldCoreCharge < 0.999 {
                Text("FOLD CORE NOT CHARGED · PUMP THE HINGE FIRST")
                    .font(.mono(8))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                store.targetSystemID = nil
                Haptics.tap()
            } label: {
                Text("CLEAR TARGET")
                    .font(.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.dim.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else if isCurrent {
            Text("CURRENT POSITION · TAP ANOTHER STAR TO TARGET IT")
                .font(.mono(9))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        } else if unlocked {
            Button {
                store.targetSystemID = system.id
                Haptics.tap()
            } label: {
                Text("SET TARGET")
                    .font(.mono(11, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 8)
            }
            .buttonStyle(.plain)
        } else {
            Text("LOCKED · UNLOCKS IN \(Act(rawValue: system.act)?.title ?? "ACT \(roman(system.act))")")
                .font(.mono(9, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glyph(for body: CelestialBody) -> String {
        switch body.kind {
        case .star: return "sun.max.fill"
        case .planet: return "circle.fill"
        case .dwarfPlanet: return "circle"
        case .blackHole: return "circle.circle"
        case .galaxy: return "hurricane"
        }
    }

    private func roman(_ n: Int) -> String {
        switch n {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        default: return "\(n)"
        }
    }
}

private struct GalaxyTag: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.mono(7)).foregroundStyle(Theme.dim)
            Text(value).font(.mono(10, weight: .semibold)).foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
