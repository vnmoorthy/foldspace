import SwiftUI

/// Sagittarius A* slingshot. Replaces the cockpit while `store.phase == .blackHole`.
///
/// The hinge is gravity: the field strength is `G · (0.6 + 1.6 · fold)`, so a flat phone is a weak
/// field and a closed one is 2.2× stronger. The ship enters from the left, dropping down-right past the
/// hole; with the phone at cockpit angle (~110°, fold ≈ 0.4) it swings under Sgr A* at ~3 rs and is
/// flung out to the exit lane on the right. Hold the LEFT half of the screen for retro thrust, the RIGHT
/// half for prograde. Crossing the event horizon calls `store.blackHoleConsumed()`; leaving through the
/// exit lane calls `store.blackHoleEscaped()`; drifting off any other edge respawns and costs 10 hull.
///
/// Physics runs in a `.task` loop at ~60 Hz (dt clamped to 1/20 s) on `SlingshotModel`, a plain struct in
/// world units (u = min(width, height), origin at the black hole). `TimelineView(.animation)` + `Canvas`
/// only draw. Ship time vs Earth time uses the Schwarzschild factor 1/√(1 − rs/r).
struct BlackHoleView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    @State private var model = SlingshotModel()
    /// Finger x (view coordinates) while a press is held; nil when released.
    @State private var pressX: CGFloat?
    @State private var autopilot = false
    @State private var viewSize: CGSize = .zero
    @State private var lastRumble: TimeInterval = 0

    private static let demoMode = ProcessInfo.processInfo.environment["FOLDSPACE_DEMO"] == "blackhole"
    private static let starField = BHStar.field(count: 280)
    /// Below this hinge angle the ship is held at the start (the phone is closed or nearly so).
    private static let releaseAngle: Double = 30

    var body: some View {
        @Bindable var store = store
        let fold = hinge.fold
        let angle = hinge.angle
        let phoneClosed = angle < Self.releaseAngle
        let hull = store.hull
        let snapshot = model
        let auto = autopilot
        let pressing = pressX
        let autopilotAvailable = Self.demoMode || snapshot.elapsed >= 12

        GeometryReader { geo in
            let size = geo.size
            ZStack {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let stress: Double = snapshot.phase == .flying ? snapshot.tidalSeverity : 0
                    let shakeAmp: Double = stress * 4
                    Canvas { context, canvasSize in
                        drawScene(&context, size: canvasSize, t: t, model: snapshot, fold: fold)
                    }
                    .offset(x: CGFloat(sin(t * 41) * shakeAmp), y: CGFloat(cos(t * 33.7) * shakeAmp))
                }

                thrustZones(pressing: pressing, width: size.width, applied: snapshot.lastThrust, autopilot: auto)
                    .allowsHitTesting(false)

                // Full-screen press surface: left half = retro, right half = prograde.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if pressX == nil { Haptics.tap() }
                                pressX = value.location.x
                            }
                            .onEnded { _ in pressX = nil }
                    )

                readouts(model: snapshot, fold: fold, angle: angle, hull: hull, phoneClosed: phoneClosed, autopilot: auto)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        if autopilotAvailable {
                            Button {
                                Haptics.tap()
                                autopilot.toggle()
                                model.autopilotExiting = false
                            } label: {
                                Text(auto ? "AUTOPILOT ON" : "AUTOPILOT")
                            }
                            .buttonStyle(.cockpit(Theme.gain, filled: auto))
                        }
                        Button {
                            Haptics.warning()
                            store.phase = .orbit
                        } label: {
                            Text("ABORT (return to orbit)")
                        }
                        .buttonStyle(.cockpit(Theme.danger))
                    }
                    .padding(.bottom, 10)
                }
                .animation(.easeInOut(duration: 0.25), value: autopilotAvailable)
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: size, initial: true) { _, newSize in
                viewSize = newSize
                model.setViewSize(newSize)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await runLoop()
        }
        .onAppear {
            Haptics.heavy()
        }
    }

    // MARK: - Loop (hinge → gravity, press → thrust, model → store)

    private func runLoop() async {
        var last = Date.timeIntervalSinceReferenceDate
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 16_000_000)
            if Task.isCancelled { return }
            let now = Date.timeIntervalSinceReferenceDate
            let dt = min(0.05, max(0, now - last))
            last = now
            guard case .blackHole = store.phase else { continue }

            var input: Double = 0
            if let x = pressX, viewSize.width > 0 {
                input = x < viewSize.width / 2 ? -1 : 1
            }
            let events = model.step(dt: dt,
                                    fold: hinge.fold,
                                    thrustInput: input,
                                    autopilot: autopilot,
                                    held: hinge.angle < Self.releaseAngle)

            if model.phase == .flying {
                // Ship time runs slow near the horizon: Earth ages by dt · γ · 0.5 years per frame.
                let years = dt * model.timeDilation * 0.5
                store.addEarthYears(years)
                model.earthYears += years

                if model.underTidalStress, now - lastRumble > 0.25 {
                    lastRumble = now
                    Haptics.rumble(intensity: min(1, 0.3 + 0.7 * model.tidalSeverity))
                }
            }

            for event in events { handle(event) }
        }
    }

    private func handle(_ event: SlingshotEvent) {
        switch event {
        case .released:
            Haptics.tap()
        case .escaped:
            Haptics.success()
            store.blackHoleEscaped()
        case .consumed:
            Haptics.heavy()
            store.blackHoleConsumed()
        case .lost:
            Haptics.warning()
            store.hull = max(5, store.hull - 10)
        }
    }

    // MARK: - Thrust zones

    private func thrustZones(pressing: CGFloat?, width: CGFloat, applied: Double, autopilot: Bool) -> some View {
        let leftPressed = pressing.map { $0 < width / 2 } ?? false
        let rightPressed = pressing.map { $0 >= width / 2 } ?? false
        let leftActive = leftPressed || (autopilot && applied < -0.15)
        let rightActive = rightPressed || (autopilot && applied > 0.15)
        return HStack(spacing: 56) {
            thrustZone(label: "◀ RETRO", tint: Theme.warn, active: leftActive, leading: true)
            thrustZone(label: "THRUST ▶", tint: Theme.accent, active: rightActive, leading: false)
        }
        .padding(.horizontal, 8)
        .padding(.top, 124)
        .padding(.bottom, 160)
    }

    private func thrustZone(label: String, tint: Color, active: Bool, leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(tint.opacity(active ? 0.12 : 0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(active ? 0.7 : 0.16), lineWidth: 1)
            )
            .overlay(alignment: leading ? .bottomLeading : .bottomTrailing) {
                Text(label)
                    .font(.mono(12, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(tint.opacity(active ? 1 : 0.5))
                    .padding(14)
                    .hudGlow(tint, radius: active ? 8 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: active)
    }

    // MARK: - Readouts

    private func readouts(model: SlingshotModel, fold: Double, angle: Double, hull: Double, phoneClosed: Bool, autopilot: Bool) -> some View {
        let multiplier = 0.6 + 1.6 * fold
        let tidal = model.phase == .flying && model.underTidalStress
        let pulse = 0.6 + 0.4 * abs(sin(model.elapsed * 8))
        let hullColor = Theme.hullColor(hull)
        return VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("SLINGSHOT AROUND SGR A* · REACH THE EXIT")
                    .font(.mono(11, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.accent)
                    .hudGlow()
                Text("fold the phone to bend space · hold sides to thrust")
                    .font(.mono(9))
                    .foregroundStyle(Theme.dim)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // FOLD = GRAVITY
            HStack(spacing: 10) {
                CockpitCaption("FOLD = GRAVITY", color: Theme.warn)
                CockpitMeter(value: fold, tint: Theme.warn)
                    .frame(maxWidth: 150)
                Text(String(format: "×%.2f", multiplier))
                    .font(.mono(10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.warn)
                Text("\(Int(angle.rounded()))°")
                    .font(.mono(9))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            .cockpitPanel(tint: Theme.warn, padding: 8)
            .padding(.top, 8)

            // Status banner
            statusBanner(model: model, phoneClosed: phoneClosed, tidal: tidal, pulse: pulse, autopilot: autopilot)
                .padding(.top, 8)

            Spacer()

            // Clocks + hull
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        CockpitCaption("SHIP CLOCK")
                        Text(shipClockText(model.shipClock))
                            .font(.mono(20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .hudGlow()
                        Text(String(format: "r %.1f rs · v %.2f", model.radiusInRs, model.velocity.length))
                            .font(.mono(8))
                            .monospacedDigit()
                            .foregroundStyle(tidal ? Theme.danger : Theme.dim)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        CockpitCaption("EARTH CLOCK", color: Theme.warn)
                        Text(String(format: "%.1f yr", model.earthYears))
                            .font(.mono(20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.warn)
                            .hudGlow(Theme.warn)
                        Text(String(format: "DILATION ×%.2f", model.phase == .flying ? model.timeDilation : 1))
                            .font(.mono(8))
                            .monospacedDigit()
                            .foregroundStyle(Theme.dim)
                    }
                }
                HStack(spacing: 10) {
                    CockpitCaption("HULL")
                    CockpitMeter(value: hull / 100, tint: hullColor)
                    Text("\(Int(hull.rounded()))%")
                        .font(.mono(10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(hullColor)
                    if model.lostCount > 0 {
                        Text("RETRIES \(model.lostCount)")
                            .font(.mono(8))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .cockpitPanel()
            .padding(.horizontal, 12)
            .padding(.bottom, 54)
        }
    }

    @ViewBuilder
    private func statusBanner(model: SlingshotModel, phoneClosed: Bool, tidal: Bool, pulse: Double, autopilot: Bool) -> some View {
        VStack(spacing: 6) {
            if model.lostFlashRemaining > 0 {
                Text("LOST — RETRYING")
                    .font(.mono(13, weight: .black))
                    .kerning(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.danger.opacity(pulse), in: RoundedRectangle(cornerRadius: 4))
                    .hudGlow(Theme.danger, radius: 10)
            } else if model.phase == .holding, phoneClosed {
                Text("OPEN THE PHONE TO RELEASE THE SHIP")
                    .font(.mono(10, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(Theme.warn)
                    .hudGlow(Theme.warn)
            } else if model.phase == .holding {
                Text(String(format: "RELEASE IN %.1f · AIM WITH THE FOLD", max(0, model.holdRemaining)))
                    .font(.mono(10, weight: .bold))
                    .kerning(1.5)
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .hudGlow()
            } else if tidal {
                Text("TIDAL STRESS")
                    .font(.mono(13, weight: .black))
                    .kerning(3)
                    .foregroundStyle(Theme.danger.opacity(pulse))
                    .hudGlow(Theme.danger, radius: 10)
            }
            if autopilot {
                Text("AUTOPILOT · RCS ACTIVE")
                    .font(.mono(9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.gain)
            }
        }
    }

    private func shipClockText(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60
        let rest = s - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, rest)
    }

    // MARK: - Canvas

    private func drawScene(_ context: inout GraphicsContext, size: CGSize, t: Double, model: SlingshotModel, fold: Double) {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1 else { return }
        let u = min(w, h)
        let c = CGPoint(x: w / 2, y: h / 2)
        let rs = SlingshotModel.rs
        let rsPx = CGFloat(rs) * u
        // 1.0 at the fold ≈ 0.4 sweet spot; the grid visibly warps more as the phone closes.
        let gravityScale = (0.6 + 1.6 * min(1, max(0, fold))) / 1.24
        let lensK = 0.0028 * gravityScale

        func toScreen(_ v: BHVec) -> CGPoint {
            CGPoint(x: c.x + CGFloat(v.x) * u, y: c.y + CGFloat(v.y) * u)
        }

        /// Pulls a background point toward the hole by k / r² (world units). Nil when it falls inside the shadow.
        func lensed(_ p: CGPoint) -> CGPoint? {
            let dx = Double(p.x - c.x) / Double(u)
            let dy = Double(p.y - c.y) / Double(u)
            let r = max(0.001, (dx * dx + dy * dy).squareRoot())
            let shift = min(lensK / (r * r), r * 0.7)
            let r2 = r - shift
            if r2 < rs * 1.35 { return nil }
            let s = r2 / r
            return CGPoint(x: c.x + CGFloat(dx * s) * u, y: c.y + CGFloat(dy * s) * u)
        }

        func addLensedLine(_ path: inout Path, from a: CGPoint, to b: CGPoint) {
            let length = hypot(b.x - a.x, b.y - a.y)
            let steps = max(2, Int(length / 9))
            var penDown = false
            for i in 0...steps {
                let f = CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                if let q = lensed(p) {
                    if penDown { path.addLine(to: q) } else { path.move(to: q); penDown = true }
                } else {
                    penDown = false
                }
            }
        }

        func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }

        // --- Space
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "020309")))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color(hex: "FF7A1E").opacity(0.14), Color(hex: "3A1040").opacity(0.06), .clear]),
            center: c, startRadius: rsPx * 1.5, endRadius: rsPx * 11))

        // --- Lensed grid
        let spacing = 0.13 * u
        var grid = Path()
        var gx = c.x.truncatingRemainder(dividingBy: spacing)
        while gx <= w {
            addLensedLine(&grid, from: CGPoint(x: gx, y: 0), to: CGPoint(x: gx, y: h))
            gx += spacing
        }
        var gy = c.y.truncatingRemainder(dividingBy: spacing)
        while gy <= h {
            addLensedLine(&grid, from: CGPoint(x: 0, y: gy), to: CGPoint(x: w, y: gy))
            gy += spacing
        }
        context.stroke(grid, with: .color(Theme.accent.opacity(0.11)), lineWidth: 0.8)

        // --- Stars (three brightness buckets, one fill each)
        var starPaths = [Path(), Path(), Path()]
        for star in Self.starField {
            let base = CGPoint(x: CGFloat(star.x) * w, y: CGFloat(star.y) * h)
            guard let p = lensed(base) else { continue }
            let twinkle = 0.75 + 0.25 * sin(t * star.twinkleSpeed + star.phase)
            let r = CGFloat(star.size * twinkle)
            starPaths[star.bucket].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        context.fill(starPaths[0], with: .color(Color.white.opacity(0.32)))
        context.fill(starPaths[1], with: .color(Color(hex: "CFE6FF").opacity(0.6)))
        context.fill(starPaths[2], with: .color(Color.white.opacity(0.95)))

        // --- Exit lane (x > 92 % w, |y − centre| < 40 % h)
        let laneX = w * 0.92
        let laneTop = c.y - h * 0.4
        let laneBottom = c.y + h * 0.4
        var lane = Path()
        lane.move(to: CGPoint(x: laneX, y: laneTop))
        lane.addLine(to: CGPoint(x: laneX, y: laneBottom))
        lane.move(to: CGPoint(x: laneX - 6, y: laneTop))
        lane.addLine(to: CGPoint(x: laneX + 6, y: laneTop))
        lane.move(to: CGPoint(x: laneX - 6, y: laneBottom))
        lane.addLine(to: CGPoint(x: laneX + 6, y: laneBottom))
        let laneNear = model.position.x > 0.15 * model.halfW
        let laneAlpha = (laneNear ? 0.55 : 0.3) + 0.2 * sin(t * 3)
        context.stroke(lane, with: .color(Theme.gain.opacity(laneAlpha)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 6], dashPhase: CGFloat(-t * 24)))
        context.draw(Text("EXIT").font(.mono(8, weight: .bold)).foregroundStyle(Theme.gain),
                     at: CGPoint(x: laneX - 16, y: laneTop + 8), anchor: .center)

        // --- Accretion disc (back half), event horizon, disc front half, photon ring
        drawAccretionDisc(&context, centre: c, rsPx: rsPx, discAngle: model.discAngle, frontOnly: false)

        context.fill(circle(c, rsPx * 1.5), with: .radialGradient(
            Gradient(colors: [.black, .black, Color.black.opacity(0)]),
            center: c, startRadius: rsPx * 0.9, endRadius: rsPx * 1.45))
        context.fill(circle(c, rsPx), with: .color(.black))

        drawAccretionDisc(&context, centre: c, rsPx: rsPx, discAngle: model.discAngle, frontOnly: true)

        let ringPulse = 0.85 + 0.15 * sin(t * 2.6)
        context.stroke(circle(c, rsPx * 1.5), with: .color(Theme.warn.opacity(0.35 * ringPulse)), lineWidth: 6)
        context.stroke(circle(c, rsPx * 1.5), with: .color(Color(hex: "FFF1D6").opacity(0.95)), lineWidth: 1.3)

        // --- Predicted path for the current fold (bends live as the phone folds)
        let ghost = model.predictedPath(fold: fold)
        if ghost.count > 1 {
            var path = Path()
            path.move(to: toScreen(ghost[0]))
            for p in ghost.dropFirst() { path.addLine(to: toScreen(p)) }
            let alpha = model.phase == .holding ? 0.7 : 0.28
            context.stroke(path, with: .color(Theme.accent.opacity(alpha)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        }

        // --- Ship, stretched along the radial direction by the tidal factor
        let shipPos = toScreen(model.position)
        let heading = atan2(model.velocity.y, model.velocity.x)
        let radial = atan2(model.position.y, model.position.x)
        let stretch = CGFloat(min(3.5, model.tidalStretch))
        var ship = context
        ship.translateBy(x: shipPos.x, y: shipPos.y)
        ship.rotate(by: Angle(radians: radial))
        ship.scaleBy(x: stretch, y: 1 / stretch.squareRoot())
        ship.rotate(by: Angle(radians: -radial))
        ship.rotate(by: Angle(radians: heading))

        let glowColor = model.underTidalStress && model.phase == .flying ? Theme.danger : Theme.accent
        ship.fill(circle(.zero, 13), with: .radialGradient(
            Gradient(colors: [glowColor.opacity(0.45), .clear]), center: .zero, startRadius: 0, endRadius: 13))

        var hullPath = Path()
        hullPath.move(to: CGPoint(x: 9, y: 0))
        hullPath.addLine(to: CGPoint(x: -7, y: 5.5))
        hullPath.addLine(to: CGPoint(x: -4, y: 0))
        hullPath.addLine(to: CGPoint(x: -7, y: -5.5))
        hullPath.closeSubpath()
        ship.fill(hullPath, with: .color(Theme.accent))
        ship.stroke(hullPath, with: .color(Color.white.opacity(0.9)), lineWidth: 0.8)

        if model.phase == .flying, abs(model.lastThrust) > 0.1 {
            let flicker = 0.7 + 0.3 * sin(t * 40)
            let len = CGFloat((6 + 9 * abs(model.lastThrust)) * flicker)
            var flame = Path()
            if model.lastThrust > 0 {
                // prograde: exhaust behind the ship
                flame.move(to: CGPoint(x: -6, y: 3))
                flame.addLine(to: CGPoint(x: -6 - len, y: 0))
                flame.addLine(to: CGPoint(x: -6, y: -3))
            } else {
                // retro: braking jet out of the nose
                flame.move(to: CGPoint(x: 8, y: 2.5))
                flame.addLine(to: CGPoint(x: 8 + len, y: 0))
                flame.addLine(to: CGPoint(x: 8, y: -2.5))
            }
            flame.closeSubpath()
            ship.fill(flame, with: .color(Theme.warn.opacity(0.9)))
        }
    }

    /// Tilted, Doppler-beamed accretion disc. Drawn once behind the horizon and once more clipped to its
    /// front (lower) half so the near side passes in front of the shadow.
    private func drawAccretionDisc(_ context: inout GraphicsContext, centre: CGPoint, rsPx: CGFloat, discAngle: Double, frontOnly: Bool) {
        var disc = context
        disc.translateBy(x: centre.x, y: centre.y)
        disc.rotate(by: .degrees(-14))
        if frontOnly {
            disc.clip(to: Path(CGRect(x: -rsPx * 20, y: 0, width: rsPx * 40, height: rsPx * 20)))
        }
        disc.scaleBy(x: 1, y: 0.34)

        let inner = rsPx * 1.75
        let outer = rsPx * 4.4
        var ring = Path(ellipseIn: CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2))
        ring.addEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))

        // Radial temperature ramp: white-hot inner edge → orange → dark red rim.
        let ramp = Gradient(stops: [
            Gradient.Stop(color: Color.white, location: 0),
            Gradient.Stop(color: Color(hex: "FFE7B8"), location: 0.12),
            Gradient.Stop(color: Color(hex: "FF9A32"), location: 0.45),
            Gradient.Stop(color: Color(hex: "C8401A").opacity(0.85), location: 0.8),
            Gradient.Stop(color: Color(hex: "5A1200").opacity(0), location: 1),
        ])
        disc.fill(ring, with: .radialGradient(ramp, center: .zero, startRadius: inner, endRadius: outer),
                  style: FillStyle(eoFill: true))

        // Doppler beaming: the approaching (left) side is brighter and whiter, the receding side dimmer.
        var doppler = disc
        doppler.clip(to: ring, style: FillStyle(eoFill: true))
        let beaming = Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0.6), location: 0),
            Gradient.Stop(color: Color.white.opacity(0), location: 0.45),
            Gradient.Stop(color: Color.black.opacity(0), location: 0.55),
            Gradient.Stop(color: Color.black.opacity(0.5), location: 1),
        ])
        doppler.fill(Path(CGRect(x: -outer, y: -outer, width: outer * 2, height: outer * 2)),
                     with: .linearGradient(beaming, startPoint: CGPoint(x: -outer, y: 0), endPoint: CGPoint(x: outer, y: 0)))

        // Turbulent bands: dashed rings whose dash phase advances at Keplerian speed (faster inside).
        let bands: [Double] = [2.3, 3.1, 3.9]
        for band in bands {
            let radius = rsPx * CGFloat(band)
            let speed = 1 / pow(band, 1.5)
            let phase = CGFloat(-discAngle * speed * 6) * radius
            disc.stroke(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color.white.opacity(0.16)),
                        style: StrokeStyle(lineWidth: 0.9, dash: [rsPx * 0.5, rsPx * 1.1], dashPhase: phase))
        }

        // Hot spots orbiting clockwise so the left limb approaches the viewer (brightest there).
        disc.blendMode = .plusLighter
        for i in 0..<6 {
            let orbit = 2.0 + 2.2 * bhHash(i, 11)
            let radius = rsPx * CGFloat(orbit)
            let omega = 2.2 / pow(orbit, 1.5)
            let theta = -(discAngle * omega * 6) + bhHash(i, 12) * 2 * .pi
            let p = CGPoint(x: radius * CGFloat(cos(theta)), y: radius * CGFloat(sin(theta)))
            let boost = 0.3 + 0.7 * (0.5 - 0.5 * cos(theta))
            let blob = rsPx * CGFloat(0.35 + 0.35 * bhHash(i, 13))
            disc.fill(Path(ellipseIn: CGRect(x: p.x - blob, y: p.y - blob, width: blob * 2, height: blob * 2)),
                      with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.8 * boost), Theme.warn.opacity(0.3 * boost), .clear]),
                        center: p, startRadius: 0, endRadius: blob))
        }
    }
}

// MARK: - Physics model

private enum SlingshotEvent {
    case released, escaped, consumed, lost
}

/// Minimal 2-D vector for the slingshot maths (world units).
private struct BHVec: Equatable {
    var x: Double
    var y: Double

    static let zero = BHVec(x: 0, y: 0)

    var length: Double { (x * x + y * y).squareRoot() }

    func normalized() -> BHVec {
        let l = length
        return l > 1e-9 ? BHVec(x: x / l, y: y / l) : BHVec(x: 1, y: 0)
    }

    static func + (a: BHVec, b: BHVec) -> BHVec { BHVec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: BHVec, b: BHVec) -> BHVec { BHVec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: BHVec, s: Double) -> BHVec { BHVec(x: a.x * s, y: a.y * s) }
    static func += (a: inout BHVec, b: BHVec) { a = a + b }
}

/// Newtonian slingshot in world units: u = min(view width, view height), origin at the black hole,
/// +x right, +y down (screen orientation). Tuned so that fold ≈ 0.4 (phone at ~110°) gives a clean pass
/// at ~2.8 rs and exits in ~4 s; fold ≥ 0.5 over-bends the path, a closed phone captures the ship.
private struct SlingshotModel {
    // Tunables
    static let rs: Double = 0.06                    // Schwarzschild radius: 6 % of min(w, h)
    static let g0: Double = 0.007                   // base gravitational parameter (u³/s²)
    static let thrust: Double = 0.06                // player thrust (u/s²)
    static let startSpeed: Double = 0.20            // u/s
    static let startAngle: Double = 45 * .pi / 180  // below horizontal, heading right
    static let startY: Double = -0.04               // just above the fold line
    static let maxGravity: Double = 12              // accel cap near the horizon (u/s²)
    static let maxSpeed: Double = 1.8               // u/s
    static let holdDuration: Double = 1.2           // seconds held at the start before release

    enum Phase: Equatable { case holding, flying, escaped, consumed }

    // View geometry in world units (half extents)
    var halfW: Double = 0.5
    var halfH: Double = 0.9

    var position = BHVec(x: -0.42, y: SlingshotModel.startY)
    var velocity = BHVec(x: cos(SlingshotModel.startAngle) * SlingshotModel.startSpeed,
                         y: sin(SlingshotModel.startAngle) * SlingshotModel.startSpeed)
    var phase: Phase = .holding
    var holdRemaining: Double = SlingshotModel.holdDuration
    /// Seconds spent flying (the ship's clock).
    var shipClock: Double = 0
    /// Seconds since the level appeared, in any phase.
    var elapsed: Double = 0
    /// Earth years accrued in this level (mirrors what was pushed to the store).
    var earthYears: Double = 0
    var lostFlashRemaining: Double = 0
    var lostCount: Int = 0
    var discAngle: Double = 0
    var autopilotExiting = false
    /// −1…1: thrust actually applied this frame (player or autopilot), for the zone lights and flame.
    var lastThrust: Double = 0

    // MARK: Derived

    var radius: Double { max(1e-4, position.length) }
    var radiusInRs: Double { radius / Self.rs }
    /// Schwarzschild time dilation γ = 1/√(1 − rs/r), clamped so it stays finite at the horizon.
    var timeDilation: Double { 1 / max(0.02, 1 - Self.rs / radius).squareRoot() }
    /// Radial stretch factor 1 + 2 (rs/r)².
    var tidalStretch: Double { 1 + 2 * pow(Self.rs / radius, 2) }
    var underTidalStress: Bool { radius < 3 * Self.rs }
    /// 0 outside 3 rs, 1 at the horizon.
    var tidalSeverity: Double { min(1, max(0, (3 * Self.rs - radius) / (2 * Self.rs))) }

    var startPosition: BHVec { BHVec(x: -halfW + 0.08, y: Self.startY) }
    var startVelocity: BHVec { BHVec(x: cos(Self.startAngle), y: sin(Self.startAngle)) * Self.startSpeed }
    /// World x of the exit line (screen x = 92 % of width).
    var exitX: Double { halfW * 0.84 }
    /// Half-height of the exit lane (40 % of height either side of the fold line).
    var exitHalfHeight: Double { halfH * 0.8 }

    static func gravityParameter(fold: Double) -> Double {
        g0 * (0.6 + 1.6 * min(1, max(0, fold)))
    }

    // MARK: Geometry

    mutating func setViewSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let u = Double(min(size.width, size.height))
        halfW = Double(size.width) / (2 * u)
        halfH = Double(size.height) / (2 * u)
        if phase == .holding {
            position = startPosition
            velocity = startVelocity
        }
    }

    mutating func resetToStart() {
        position = startPosition
        velocity = startVelocity
        phase = .holding
        holdRemaining = Self.holdDuration
        autopilotExiting = false
        lastThrust = 0
    }

    // MARK: Step

    /// Advances the simulation by `dt`. `thrustInput` is −1 (retro), 0 or +1 (prograde); `held` freezes the
    /// ship at the start (phone closed). Returns the events the view should react to.
    mutating func step(dt: Double, fold: Double, thrustInput: Double, autopilot: Bool, held: Bool) -> [SlingshotEvent] {
        var events: [SlingshotEvent] = []
        elapsed += dt
        discAngle += dt * 0.35
        if lostFlashRemaining > 0 { lostFlashRemaining = max(0, lostFlashRemaining - dt) }

        switch phase {
        case .escaped, .consumed:
            return events
        case .holding:
            position = startPosition
            velocity = startVelocity
            lastThrust = 0
            if held {
                holdRemaining = Self.holdDuration
                return events
            }
            holdRemaining -= dt
            if holdRemaining <= 0 {
                phase = .flying
                events.append(.released)
            }
            return events
        case .flying:
            break
        }

        shipClock += dt
        let mu = Self.gravityParameter(fold: fold)
        var acceleration = gravity(mu: mu)
        var applied: Double = 0
        if autopilot {
            let rcs = autopilotAcceleration(mu: mu)
            acceleration += rcs
            let along = rcs.x * velocity.normalized().x + rcs.y * velocity.normalized().y
            applied = min(1, max(-1, along / 0.45))
        } else if thrustInput != 0 {
            let direction = velocity.normalized()
            acceleration += direction * (Self.thrust * thrustInput)
            applied = thrustInput > 0 ? 1 : -1
        }
        lastThrust = applied

        velocity += acceleration * dt
        let speed = velocity.length
        if speed > Self.maxSpeed { velocity = velocity * (Self.maxSpeed / speed) }
        position += velocity * dt

        let r = radius
        if r < Self.rs {
            phase = .consumed
            events.append(.consumed)
            return events
        }
        if position.x > exitX, abs(position.y) < exitHalfHeight {
            phase = .escaped
            events.append(.escaped)
            return events
        }
        let margin = 0.06
        if position.x < -halfW - margin || abs(position.y) > halfH + margin || position.x > halfW + margin {
            lostCount += 1
            lostFlashRemaining = 2.2
            resetToStart()
            events.append(.lost)
        }
        return events
    }

    private func gravity(mu: Double) -> BHVec {
        let r = radius
        let magnitude = min(mu / (r * r), Self.maxGravity)
        return position * (-magnitude / r)
    }

    /// Reaction-control autopilot: holds a ~3.3 rs orbit in the current sense of rotation, then, once the
    /// tangent points right of the hole, latches into an exit run toward the lane.
    private mutating func autopilotAcceleration(mu: Double) -> BHVec {
        let r = radius
        let rhat = position * (1 / r)
        let cross = position.x * velocity.y - position.y * velocity.x
        let tangent: BHVec
        if abs(cross) < 1e-4 {
            tangent = -rhat.y > 0 ? BHVec(x: -rhat.y, y: rhat.x) : BHVec(x: rhat.y, y: -rhat.x)
        } else {
            let s: Double = cross > 0 ? 1 : -1
            tangent = BHVec(x: -rhat.y * s, y: rhat.x * s)
        }
        let rStar = 3.3 * Self.rs
        if !autopilotExiting {
            if (position.x > 0.5 * Self.rs && tangent.x > 0.6 && r > 2.6 * Self.rs)
                || (position.x > 4.5 * Self.rs && velocity.x > 0) {
                autopilotExiting = true
            }
        } else if r < 2 * Self.rs {
            autopilotExiting = false
        }

        let desired: BHVec
        if autopilotExiting {
            desired = BHVec(x: 1, y: position.y > 0 ? -0.12 : 0.12).normalized() * 0.36
        } else {
            let circular = (mu / rStar).squareRoot()
            desired = tangent * circular - rhat * (1.2 * (r - rStar))
        }
        var a = (desired - velocity) * 3.0
        let magnitude = a.length
        if magnitude > 0.9 { a = a * (0.9 / magnitude) }
        return a
    }

    /// Coasting trajectory from the current state for the given fold (no thrust), ~4.5 s ahead.
    func predictedPath(fold: Double, seconds: Double = 4.5) -> [BHVec] {
        var p = phase == .holding ? startPosition : position
        var v = phase == .holding ? startVelocity : velocity
        let mu = Self.gravityParameter(fold: fold)
        let step = 1.0 / 30
        var points: [BHVec] = [p]
        var t = 0.0
        while t < seconds {
            let r = max(1e-4, p.length)
            if r < Self.rs { break }
            let magnitude = min(mu / (r * r), Self.maxGravity)
            v += p * (-magnitude / r * step)
            let speed = v.length
            if speed > Self.maxSpeed { v = v * (Self.maxSpeed / speed) }
            p += v * step
            points.append(p)
            if abs(p.x) > halfW + 0.1 || abs(p.y) > halfH + 0.1 { break }
            t += step
        }
        return points
    }
}

// MARK: - File-private helpers

private struct BHStar {
    let x: Double
    let y: Double
    let size: Double
    let twinkleSpeed: Double
    let phase: Double
    let bucket: Int

    static func field(count: Int) -> [BHStar] {
        (0..<count).map { i -> BHStar in
            let brightness = bhHash(i, 5)
            let bucket = brightness > 0.85 ? 2 : (brightness > 0.5 ? 1 : 0)
            return BHStar(x: bhHash(i, 1),
                          y: bhHash(i, 2),
                          size: 0.5 + 1.1 * bhHash(i, 3) * (bucket == 2 ? 1.4 : 1),
                          twinkleSpeed: 0.8 + 2.5 * bhHash(i, 4),
                          phase: bhHash(i, 6) * 2 * .pi,
                          bucket: bucket)
        }
    }
}

private func bhHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 3_266_489_917 &+ UInt32(truncatingIfNeeded: b) &* 374_761_393
    h = (h ^ (h >> 15)) &* 2_654_435_761
    h ^= h >> 13
    return Double(h & 0xFFFF) / 65535
}
