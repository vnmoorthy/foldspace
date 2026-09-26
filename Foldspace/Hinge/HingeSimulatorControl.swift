import SwiftUI

/// On-screen stand-in for the iPhone Duo hinge (Xcode simulator / non-folding iPhones).
///
/// Everything here goes through `HingeEngine.ingest(angle:)` / `nudge(by:)` / `animate(to:duration:)`,
/// so gestures are recognised exactly as they would be from the real hinge. RootView hides this
/// control as soon as the engine's source becomes `.duo`.
struct HingeSimulatorControl: View {
    @Environment(HingeEngine.self) private var hinge
    @State private var expanded = false
    @State private var lastDragY: CGFloat = 0
    @State private var sequence: Task<Void, Never>?
    @State private var busyAction: String?
    @State private var runID = 0

    // MARK: - Quick actions

    private struct Step {
        let target: Double
        let duration: Double
    }

    private struct QuickAction: Identifiable {
        let id: String
        let tint: Color
        let steps: [Step]
    }

    private static let actions: [QuickAction] = [
        QuickAction(id: "CLOSE", tint: Theme.accent, steps: [Step(target: 0, duration: 1.0)]),      // ideal warp close
        QuickAction(id: "SLAM", tint: Theme.danger, steps: [Step(target: 0, duration: 0.15)]),      // too fast → bubble collapse
        QuickAction(id: "OPEN", tint: Theme.accent, steps: [Step(target: 110, duration: 0.6)]),
        QuickAction(id: "FLAT", tint: Theme.accent, steps: [Step(target: 180, duration: 0.6)]),
        QuickAction(id: "HOP", tint: Theme.gain, steps: [Step(target: 55, duration: 0.35), Step(target: 110, duration: 0.35)]),
        QuickAction(id: "SQUEEZE", tint: Theme.warn, steps: [Step(target: 25, duration: 0.5)]),
        QuickAction(id: "SNAP", tint: Theme.warn, steps: [Step(target: 130, duration: 0.12)]),
        QuickAction(id: "PUMP ×4", tint: Theme.gain, steps: (0..<4).flatMap { _ in
            [Step(target: 30, duration: 0.35), Step(target: 150, duration: 0.35)]
        }),
    ]

    // MARK: - Body

    var body: some View {
        @Bindable var hinge = hinge
        VStack(spacing: 8) {
            header
            slider
            if expanded {
                HStack(alignment: .top, spacing: 10) {
                    dragPad
                        .frame(width: 88, height: 118)
                    VStack(spacing: 8) {
                        quickActions
                        sourcePicker(selection: $hinge.source)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background { panelBackground }
        .animation(.spring(duration: 0.3), value: expanded)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                expanded.toggle()
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse hinge simulator" : "Expand hinge simulator")

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(String(format: "%3.0f", hinge.angle))
                    .font(.mono(20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text("°")
                    .font(.mono(12))
                    .foregroundStyle(Theme.dim)
            }
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                CockpitCaption("HINGE · \(hinge.posture.label)", color: Theme.accent)
                CockpitCaption(hinge.lastGesture.map { "LAST · \($0.displayName)" } ?? "LAST · —", color: Theme.dim)
            }

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                Image(systemName: hinge.velocity > 5 ? "arrow.up" : (hinge.velocity < -5 ? "arrow.down" : "minus"))
                    .font(.system(size: 8, weight: .bold))
                Text(String(format: "%+.0f°/s", hinge.velocity))
                    .font(.mono(9))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Slider (absolute angle)

    private var slider: some View {
        HStack(spacing: 8) {
            Text("0°")
                .font(.mono(8))
                .foregroundStyle(Theme.dim)
            Slider(
                value: Binding(
                    get: { hinge.angle },
                    set: { hinge.ingest(angle: $0) }
                ),
                in: 0...180
            )
            .tint(Theme.accent)
            Text("180°")
                .font(.mono(8))
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Drag pad (relative nudges — "drag the lid")

    private var dragPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.06))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            VStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                lidGlyph
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                CockpitCaption("DRAG THE LID", color: Theme.accent)
            }
            .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Finger up opens the lid, finger down closes it. 1 pt ≈ 0.8°.
                    let delta = lastDragY - value.translation.height
                    lastDragY = value.translation.height
                    hinge.nudge(by: Double(delta) * 0.8)
                }
                .onEnded { _ in
                    lastDragY = 0
                }
        )
    }

    /// Side view of the phone: fixed base, lid rotated to the live angle.
    private var lidGlyph: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule()
                .fill(Theme.dim)
                .frame(width: 26, height: 4)
            Capsule()
                .fill(Theme.accent)
                .frame(width: 26, height: 4)
                .shadow(color: Theme.accent.opacity(0.8), radius: 3)
                .rotationEffect(.degrees(-hinge.angle), anchor: .leading)
        }
        .padding(.leading, 26)
        .frame(height: 30, alignment: .bottom)
    }

    // MARK: - Quick actions (async sequences of engine animations)

    private var quickActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Self.actions) { action in
                Button {
                    run(action)
                } label: {
                    Text(action.id)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.cockpit(action.tint, filled: busyAction == action.id, size: 10))
                .disabled(busyAction != nil && busyAction != action.id)
            }
        }
    }

    private func run(_ action: QuickAction) {
        sequence?.cancel()
        runID += 1
        let myRun = runID
        busyAction = action.id
        Haptics.tap()
        let engine = hinge
        sequence = Task { @MainActor in
            for step in action.steps {
                if Task.isCancelled { break }
                engine.animate(to: step.target, duration: step.duration)
                // Wait for that animation to finish (plus a frame) before starting the next leg.
                try? await Task.sleep(nanoseconds: UInt64((step.duration + 0.06) * 1_000_000_000))
            }
            if runID == myRun {
                busyAction = nil
            }
        }
    }

    // MARK: - Source picker

    private func sourcePicker(selection: Binding<HingeSource>) -> some View {
        HStack(spacing: 8) {
            CockpitCaption("SOURCE")
            Picker("Hinge source", selection: selection) {
                ForEach(HingeSource.allCases.filter { $0 != .duo }) { source in
                    Text(shortLabel(source)).tag(source)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func shortLabel(_ source: HingeSource) -> String {
        switch source {
        case .simulated: return "SIMULATED"
        case .motion: return "TILT PHONE"
        case .duo: return "DUO"
        }
    }

    // MARK: - Chrome

    private var panelBackground: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.panel.opacity(0.88))
            Rectangle()
                .fill(Theme.accent.opacity(0.5))
                .frame(height: 1)
                .shadow(color: Theme.accent.opacity(0.6), radius: 3)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
