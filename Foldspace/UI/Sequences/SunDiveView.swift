import SwiftUI

/// Full-screen plunge into the star. Replaces the cockpit while `store.phase == .sunDive`.
///
/// Depth is the hinge: angle 120° → depth 0 (corona), angle 12° → depth 1 (core). The view owns the
/// 60 Hz loop that feeds `store.updateSunDive(depth:dt:)` (GameStore's contract says the dive view calls it)
/// and calls `store.endSunDive()` when the phone is opened past 130° after the dive has begun.
struct SunDiveView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    /// Smoothed temperature for the animated readout.
    @State private var displayedTemp: Double = 1_000_000
    /// Set when the player has actually started descending (angle ≤ 118°); enables climb-out.
    @State private var armed = false
    @State private var startedAt = Date()
    @State private var coreFlashAt: Date?
    @State private var lastRumble: TimeInterval = 0

    private static let topAngle: Double = 120   // depth 0
    private static let coreAngle: Double = 12   // depth 1
    private static let climbOutAngle: Double = 130
    private static let photosphere = VisualAssets.image(named: "sun-photosphere")

    static func depth(forAngle angle: Double) -> Double {
        max(0, min(1, (topAngle - angle) / (topAngle - coreAngle)))
    }

    var body: some View {
        let depth = store.diveDepth
        let hull = store.hull
        let angle = hinge.angle
        let layer = SunLayer.at(depth: depth)
        let hasSample = store.save.solarCoreSample
        let shown = displayedTemp
        let flash = coreFlashAt
        let armedNow = armed

        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let shakeAmp = pow(depth, 2) * 7
            let shake = CGSize(width: sin(t * 37) * shakeAmp, height: cos(t * 29.3) * shakeAmp)
            ZStack {
                Canvas { context, size in
                    drawStar(context: &context, size: size, depth: depth, t: t)
                }
                .ignoresSafeArea()

                // Vignette darkening at the edges, stronger with depth.
                RadialGradient(colors: [.clear, Color.black.opacity(0.25 + 0.55 * depth)],
                               center: .center, startRadius: 60, endRadius: 520)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                readouts(depth: depth, hull: hull, angle: angle, layer: layer, temp: shown, hasSample: hasSample, armed: armedNow, now: timeline.date, flash: flash)
            }
            .offset(shake)
        }
        .background(Color.black)
        .task {
            await runLoop()
        }
        .onAppear {
            startedAt = Date()
            armed = hinge.angle <= 118
            displayedTemp = SunLayer.at(depth: store.diveDepth).temperatureK
            Haptics.warning()
        }
        .onChange(of: store.save.solarCoreSample) { old, new in
            if !old, new {
                coreFlashAt = Date()
                Haptics.success()
            }
        }
    }

    // MARK: - Loop (hinge → depth → store)

    private func runLoop() async {
        var last = Date.timeIntervalSinceReferenceDate
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 16_000_000)
            if Task.isCancelled { return }
            guard case .sunDive = store.phase else { continue }
            let now = Date.timeIntervalSinceReferenceDate
            let dt = min(0.05, max(0, now - last))
            last = now

            let angle = hinge.angle
            if angle <= 118 { armed = true }
            if armed, angle > Self.climbOutAngle {
                store.endSunDive()
                continue
            }
            store.updateSunDive(depth: Self.depth(forAngle: angle), dt: dt)

            // Animated temperature: exponential approach to the layer's real value.
            let target = SunLayer.at(depth: store.diveDepth).temperatureK
            let k = 1 - exp(-dt * 4.5)
            displayedTemp += (target - displayedTemp) * k
            if abs(target - displayedTemp) < 50 { displayedTemp = target }

            // Rumble grows with depth, throttled to ~4 Hz.
            let depth = store.diveDepth
            if depth > 0.25, now - lastRumble > 0.25 {
                lastRumble = now
                Haptics.rumble(intensity: min(1, 0.2 + depth))
            }
        }
    }

    // MARK: - Text layer

    private func readouts(depth: Double, hull: Double, angle: Double, layer: SunLayer, temp: Double, hasSample: Bool, armed: Bool, now: Date, flash: Date?) -> some View {
        let hullCritical = hull < 40
        let flashAge = flash.map { now.timeIntervalSince($0) } ?? 99
        return VStack(spacing: 0) {
            // Instruction
            Text("CLOSE THE PHONE TO DIVE · OPEN TO CLIMB OUT")
                .font(.mono(10, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.75))
                .clipShape(Capsule())
                .padding(.top, 58)

            Text("HINGE \(Int(angle))° · \(armed ? "DESCENDING" : "AT THE CORONA — CLOSE TO BEGIN")")
                .font(.mono(9))
                .foregroundStyle(Color.black.opacity(0.7))
                .padding(.top, 6)

            Spacer()

            // Temperature block
            VStack(spacing: 4) {
                Text(layer.name)
                    .font(.mono(13, weight: .bold))
                    .kerning(4)
                    .foregroundStyle(Color.black.opacity(0.85))
                Text("\(sunGrouped(Int(temp.rounded()))) K")
                    .font(.mono(46, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(depth > 0.6 ? Color(red: 0.25, green: 0.05, blue: 0.35) : Color.black.opacity(0.9))
                    .shadow(color: Color.white.opacity(0.9), radius: 12)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(layer.note)
                    .font(.mono(10))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Core sample flash
            if flashAge < 3.5 {
                let pulse = 0.75 + 0.25 * sin(flashAge * 14)
                Text("STELLAR CORE SAMPLE SECURED")
                    .font(.mono(15, weight: .black))
                    .kerning(2)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.gain.opacity(pulse))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: Theme.gain, radius: 16)
                    .opacity(flashAge > 2.8 ? (3.5 - flashAge) / 0.7 : 1)
                    .padding(.bottom, 14)
            } else if hasSample {
                Text("CORE SAMPLE ✓ · NOVA LANCE ONLINE")
                    .font(.mono(9, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .padding(.bottom, 10)
            }

            // Bars
            VStack(spacing: 10) {
                sunBar(label: "DEPTH", value: depth, text: String(format: "%.0f%%", depth * 100), color: Color.black.opacity(0.8), track: Color.white.opacity(0.35))
                sunBar(label: "HULL", value: hull / 100, text: "\(Int(hull.rounded()))%",
                       color: hullCritical ? Theme.danger : Theme.gain, track: Color.black.opacity(0.35))
                if hullCritical {
                    Text("PULL UP — OPEN THE PHONE")
                        .font(.mono(13, weight: .black))
                        .kerning(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.danger.opacity(0.65 + 0.35 * abs(sin(now.timeIntervalSinceReferenceDate * 9))))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(14)
            .background(Color.black.opacity(0.28))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            Button {
                Haptics.tap()
                store.endSunDive()
            } label: {
                Text("ABORT DIVE")
                    .font(.mono(10, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(Color.black.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Color.black.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
    }

    private func sunBar(label: String, value: Double, text: String, color: Color, track: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.mono(10, weight: .semibold)).kerning(1.5)
                Spacer()
                Text(text).font(.mono(10, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(Color.black.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(track)
                    Rectangle().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                        .shadow(color: color.opacity(0.7), radius: 5)
                }
            }
            .frame(height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
        }
    }

    // MARK: - Canvas

    private func drawStar(context: inout GraphicsContext, size: CGSize, depth: Double, t: Double) {
        // Background ramp: gold → orange → white-hot → violet-white.
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (1.00, 0.82, 0.30)),
            (0.30, (1.00, 0.52, 0.12)),
            (0.65, (1.00, 0.97, 0.90)),
            (1.00, (0.88, 0.80, 1.00)),
        ]
        let bg = sunRamp(stops, depth)
        let bgColor = Color(red: bg.0, green: bg.1, blue: bg.2)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bgColor))

        // A close surface patch fades in around the photosphere, then gives way to the interior.
        let surfaceAlpha = Self.photosphere == nil ? 0 : (1 - abs(depth - 0.25) / 0.32).clamped01()
        if let image = Self.photosphere, surfaceAlpha > 0 {
            var surface = context
            surface.blendMode = .normal
            surface.opacity = surfaceAlpha
            let imageHeight = max(size.height * (1.25 + depth * 0.35), size.width * 0.55)
            let imageWidth = imageHeight * 2
            let drift = CGFloat(sin(t * 0.05)) * imageWidth * 0.025
            surface.draw(Image(uiImage: image),
                         in: CGRect(x: (size.width - imageWidth) / 2 + drift,
                                    y: (size.height - imageHeight) / 2,
                                    width: imageWidth, height: imageHeight))
        }

        // Inner brightness: a hot centre that whitens with depth.
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.25 + 0.55 * depth), .clear]),
            center: centre, startRadius: 0, endRadius: size.width * (0.6 + 0.3 * depth)))

        // Granulation noise: coarse cells whose brightness churns over time.
        let cell: CGFloat = 26
        let cols = Int(size.width / cell) + 1
        let rows = Int(size.height / cell) + 1
        let frame = Int(t * 6)
        let granAlpha = (0.05 + 0.10 * (1 - abs(depth - 0.3) * 2).clamped01()) * (1 - surfaceAlpha)
        for r in 0..<rows {
            for c in 0..<cols {
                let n = sunHash(c + r * 97, frame + (c ^ r) % 3)
                guard n > 0.55 else { continue }
                let a = (n - 0.55) * granAlpha * 2
                let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell - 2, height: cell - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color((n > 0.85 ? Color.white : Color.black).opacity(a)))
            }
        }

        // Rising plasma cells (convective zone): bubbles rising from the bottom, stronger mid-depth.
        context.blendMode = .plusLighter
        let plasmaAlpha = 0.15 + 0.5 * depth
        let count = 18 + Int(30 * depth)
        for i in 0..<count {
            let speed = 0.06 + sunHash(i, 1) * 0.12 + depth * 0.15
            let phase = (t * speed + sunHash(i, 2) * 10).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(sunHash(i, 3)) * size.width + CGFloat(sin(t * 0.7 + Double(i)) * 14)
            let y = size.height * (1.1 - CGFloat(phase) * 1.2)
            let radius = 18 + CGFloat(sunHash(i, 4)) * 46 * CGFloat(0.6 + depth)
            let a = plasmaAlpha * (1 - phase) * 0.8
            let hot = depth > 0.6
            let color = hot ? Color(red: 0.9, green: 0.75, blue: 1) : Color(red: 1, green: 0.9, blue: 0.55)
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius * 0.8, width: radius * 2, height: radius * 1.6)),
                         with: .radialGradient(Gradient(colors: [color.opacity(a), .clear]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
        context.blendMode = .normal

        // Heat shimmer: wobbling horizontal lines.
        let lines = 14
        let shimmer = 0.10 + 0.25 * depth
        for i in 0..<lines {
            let baseY = size.height * CGFloat(Double(i) / Double(lines))
            var path = Path()
            var x: CGFloat = 0
            let freq = 0.02 + sunHash(i, 7) * 0.02
            let amp = 4 + 10 * depth
            path.move(to: CGPoint(x: 0, y: baseY + CGFloat(sin(t * 3 + Double(i)) * amp)))
            while x <= size.width {
                let y = baseY + CGFloat(sin(Double(x) * freq + t * (2.5 + Double(i) * 0.2)) * amp) + CGFloat(sin(t * 0.9 + Double(i) * 1.7) * 6)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            context.stroke(path, with: .color(Color.white.opacity(shimmer * (0.4 + 0.6 * sunHash(i, 8)))), lineWidth: 1)
        }

        // Corona filaments near the top when shallow.
        if depth < 0.25 {
            let a = (0.25 - depth) / 0.25
            for i in 0..<10 {
                var path = Path()
                let x0 = CGFloat(sunHash(i, 21)) * size.width
                path.move(to: CGPoint(x: x0, y: 0))
                path.addCurve(to: CGPoint(x: x0 + CGFloat(sin(t + Double(i)) * 80), y: size.height * 0.45),
                              control1: CGPoint(x: x0 - 60, y: size.height * 0.15),
                              control2: CGPoint(x: x0 + 90, y: size.height * 0.3))
                context.stroke(path, with: .color(Color.white.opacity(0.25 * a)), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - File-private helpers

private extension Double {
    func clamped01() -> Double { Swift.min(1, Swift.max(0, self)) }
}

private func sunHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 3_266_489_917 &+ UInt32(truncatingIfNeeded: b) &* 374_761_393
    h = (h ^ (h >> 15)) &* 2_654_435_761
    h ^= h >> 13
    return Double(h & 0xFFFF) / 65535
}

private func sunRamp(_ stops: [(Double, (Double, Double, Double))], _ x: Double) -> (Double, Double, Double) {
    let v = min(1, max(0, x))
    for i in 1..<stops.count {
        let (x0, c0) = stops[i - 1]
        let (x1, c1) = stops[i]
        if v <= x1 {
            let f = (v - x0) / max(0.0001, x1 - x0)
            return (c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f)
        }
    }
    return stops[stops.count - 1].1
}

private func sunGrouped(_ n: Int) -> String {
    let s = String(abs(n))
    var out = ""
    for (i, ch) in s.reversed().enumerated() {
        if i > 0, i % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + String(out.reversed())
}
