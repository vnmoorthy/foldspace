import SwiftUI

/// Routes hinge posture + flight phase to a full-screen scene.
///
/// The posture switch stands in for the iPhone Duo's display hand-off: on hardware iOS moves the app
/// to the outer display when the phone closes; in the simulator we render `OuterDisplayView` on the
/// inner display instead. The hinge simulator control is pinned to the bottom edge whenever the
/// engine is not fed by a real Duo hinge.
struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge
    @State private var toastTask: Task<Void, Never>?

    private enum Screen: Equatable {
        case shipLost, andromeda, blackHole, outerDisplay, sunDive, galaxyMap, cockpit
    }

    private var screen: Screen {
        switch store.phase {
        case .shipLost: return .shipLost
        case .andromeda: return .andromeda
        case .blackHole: return .blackHole
        case .sunDive: return .sunDive // the dive owns the whole hinge range: closed = deep, not "docked"
        default: break
        }
        if hinge.posture == .closed { return .outerDisplay }
        if hinge.posture == .flat { return .galaxyMap }
        return .cockpit
    }

    private var isHopping: Bool {
        if case .hopping = store.phase { return true }
        return false
    }

    private var showWarpSequence: Bool { store.phase.isTransit && !isHopping }

    private var showWeapon: Bool {
        switch store.phase {
        case .weaponCharging, .weaponFiring: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
                .animation(.easeInOut(duration: 0.35), value: screen)
        }
        .overlay(alignment: .top) {
            toastView
                .animation(.spring(duration: 0.35), value: store.toast)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hinge.source != .duo {
                HingeSimulatorControl()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hinge.source)
        .onChange(of: store.toast) { _, newValue in scheduleToastClear(newValue) }
        .onAppear { scheduleToastClear(store.toast) }
    }

    // MARK: - Scenes

    @ViewBuilder private var content: some View {
        switch screen {
        case .shipLost:
            ShipLostView().transition(.opacity)
        case .andromeda:
            AndromedaFinaleView().transition(.opacity)
        case .blackHole:
            BlackHoleView().transition(.opacity)
        case .outerDisplay:
            OuterDisplayView().transition(.opacity)
        case .sunDive:
            SunDiveView().transition(.opacity)
        case .galaxyMap:
            GalaxyMapView().transition(.opacity)
        case .cockpit:
            CockpitView()
                .overlay {
                    if showWarpSequence {
                        WarpSequenceView().transition(.opacity)
                    }
                }
                .overlay {
                    if showWeapon {
                        WeaponView().transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showWarpSequence)
                .animation(.easeInOut(duration: 0.3), value: showWeapon)
                .transition(.opacity)
        }
    }

    // MARK: - Toast

    @ViewBuilder private var toastView: some View {
        if let toast = store.toast {
            Text(toast)
                .font(.mono(11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Theme.panel.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
                )
                .hudGlow(radius: 10)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .id(toast) // a new message slides in fresh
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func scheduleToastClear(_ toast: String?) {
        toastTask?.cancel()
        guard toast != nil else { return }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                store.toast = nil
            }
        }
    }
}
