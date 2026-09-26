import SwiftUI

/// Shown when `store.phase == .shipLost` (hull vaporised in the Sun or spaghettified at Sagittarius A*).
/// Red-black static, the last danger entry from the log, and two real exits: REDEPLOY or RESET.
struct ShipLostView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    private var lastDanger: LogEntry? {
        store.save.log.last { $0.kind == .danger }
    }

    var body: some View {
        let entry = lastDanger
        let years = store.save.earthYearsElapsed
        ZStack {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    // Black base with a slow red breathing gradient from the bottom.
                    let breathe = 0.55 + 0.25 * sin(t * 1.6)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.0, blue: 0.01)))
                    let glow = Path(CGRect(origin: .zero, size: size))
                    context.fill(glow, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.55, green: 0.02, blue: 0.08).opacity(breathe * 0.5), .clear]),
                        startPoint: CGPoint(x: size.width / 2, y: size.height),
                        endPoint: CGPoint(x: size.width / 2, y: size.height * 0.35)))

                    // Static scanlines: every 3 pt, brightness from a cheap hash that shifts each frame.
                    let frame = Int(t * 24)
                    var y: CGFloat = 0
                    var line = 0
                    while y < size.height {
                        let n = shipLostHash(line, frame)
                        if n > 0.72 {
                            let alpha = (n - 0.72) * 0.9
                            let w = size.width * CGFloat(0.3 + shipLostHash(line, frame + 7) * 0.7)
                            let x = CGFloat(shipLostHash(line, frame + 13)) * (size.width - w)
                            context.fill(Path(CGRect(x: x, y: y, width: w, height: 1.5)),
                                         with: .color(Color(red: 1, green: 0.23, blue: 0.36).opacity(alpha)))
                        }
                        y += 3
                        line += 1
                    }

                    // Torn horizontal tear bands (signal loss).
                    for i in 0..<3 {
                        let phase = (t * (0.35 + Double(i) * 0.17) + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                        let ty = CGFloat(phase) * size.height
                        let rect = CGRect(x: 0, y: ty, width: size.width, height: 2 + CGFloat(i) * 3)
                        context.fill(Path(rect), with: .color(Color.white.opacity(0.05 + 0.05 * Double(i))))
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 20)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Theme.danger)
                    .shadow(color: Theme.danger.opacity(0.9), radius: 18)

                Text("SHIP LOST")
                    .font(.mono(44, weight: .black))
                    .foregroundStyle(Theme.danger)
                    .shadow(color: Theme.danger.opacity(0.8), radius: 14)
                    .kerning(6)

                Text("TELEMETRY TERMINATED · \(hinge.posture.label) · \(Int(hinge.angle))°")
                    .font(.mono(11))
                    .foregroundStyle(Theme.dim)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LAST TRANSMISSION")
                        .font(.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.danger.opacity(0.85))
                    Text(entry?.text ?? "Contact with the hull lost. No final words were recorded.")
                        .font(.mono(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.danger.opacity(0.6), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 24)

                HStack(spacing: 22) {
                    shipLostStat("CLAIMED", "\(store.save.claimed.count)")
                    shipLostStat("DESTROYED", "\(store.save.destroyed.count)")
                    shipLostStat("ENERGY", "\(store.energy)")
                    shipLostStat("EARTH YRS", years < 1 ? "<1" : "\(Int(years))")
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Haptics.success()
                        store.respawn()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("REDEPLOY")
                                .kerning(3)
                        }
                        .font(.mono(16, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Theme.accent.opacity(0.55), radius: 10)
                    }
                    .buttonStyle(.plain)

                    Text("A backup hull launches from the beacon network at \(store.currentSystem.name).")
                        .font(.mono(10))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)

                    Button {
                        Haptics.warning()
                        store.reset()
                    } label: {
                        Text("RESET · NEW COMMANDER")
                            .kerning(2)
                            .font(.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.danger.opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .background(Color.black)
        .onAppear { Haptics.warning() }
    }

    private func shipLostStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.mono(18, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.mono(9))
                .foregroundStyle(Theme.dim)
        }
    }
}

/// Deterministic 0...1 noise used for the static effect (no RNG so frames are reproducible).
private func shipLostHash(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a) &* 374_761_393 &+ UInt32(truncatingIfNeeded: b) &* 668_265_263
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65535
}
