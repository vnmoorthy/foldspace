import SwiftUI

/// The console below the fold. Every game verb the hinge can trigger is also reachable here, so the
/// game is fully playable in the simulator and on a non-folding iPhone. Layout: body strip pinned at
/// the top, scrolling panels in the middle, the beacon probe + gear menu pinned at the bottom.
struct ConsoleView: View {
    @Environment(GameStore.self) private var store
    @Environment(HingeEngine.self) private var hinge

    // Probe drag
    @State private var probeOffset: CGSize = .zero
    @State private var probeArmed = false
    @State private var probeDragging = false

    // Gear menu
    @State private var showCallsignEditor = false
    @State private var callsignDraft = ""
    @State private var confirmReset = false

    var body: some View {
        GeometryReader { geo in
            let consoleHeight = geo.size.height
            VStack(spacing: 0) {
                bodyStrip
                    .frame(height: 46)
                hairline
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        scanPanel
                        drivePanel
                        systemsPanel
                        hullPanel
                        logPanel
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                hairline
                probeBar(consoleHeight: consoleHeight)
                    .frame(height: 74)
            }
        }
        .background(Theme.panel)
        .alert("CALLSIGN", isPresented: $showCallsignEditor) {
            TextField("Callsign", text: $callsignDraft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Save") { saveCallsign() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How the Galactic Registry will remember you.")
        }
        .confirmationDialog("Reset commander?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset all progress", role: .destructive) {
                store.reset()
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Beacons, energy and drive parts are wiped. The registry keeps its history.")
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.18))
            .frame(height: 1)
    }

    private var inOrbit: Bool {
        if case .orbit = store.phase { return true }
        return false
    }

    // MARK: - (1) Body strip

    private var bodyStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    bodyChip(store.currentSystem.primary, isPrimary: true)
                    ForEach(store.livingBodies) { body in
                        bodyChip(body, isPrimary: false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: store.save.bodyID) { _, id in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(store.save.bodyID, anchor: .center)
            }
        }
    }

    private func bodyChip(_ body: CelestialBody, isPrimary: Bool) -> some View {
        let isCurrent = body.id == store.save.bodyID
        let claimed = store.isClaimed(body.id)
        let hidesPart: Bool = {
            guard let part = body.drivePart else { return false }
            return !store.save.driveParts.contains(part)
        }()
        let tint: Color = isCurrent ? Theme.accent : (claimed ? Theme.gain : Theme.dim)
        return Button {
            guard !isCurrent else { return }
            Haptics.tap()
            store.hop(to: body.id)
        } label: {
            HStack(spacing: 5) {
                if isPrimary {
                    Image(systemName: primarySymbol(body.kind))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: body.colorHex))
                } else {
                    Circle()
                        .fill(Color(hex: body.colorHex))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
                Text(body.name.uppercased())
                    .font(.mono(10, weight: isCurrent ? .bold : .medium))
                if claimed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.gain)
                }
                if hidesPart {
                    Image(systemName: "questionmark.diamond")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warn)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(isCurrent ? 0.16 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(isCurrent ? 0.9 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(inOrbit || isCurrent ? 1 : 0.5)
        .id(body.id)
    }

    private func primarySymbol(_ kind: BodyKind) -> String {
        switch kind {
        case .blackHole: return "circle.circle"
        case .galaxy: return "sparkles"
        default: return "sun.max.fill"
        }
    }

    // MARK: - (2) Scan panel

    private var scanPanel: some View {
        let body = store.currentBody
        let claimed = store.isClaimed(body.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader("SCAN", symbol: "waveform.path.ecg")
                Spacer()
                Text(classLabel(body))
                    .font(.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text(body.blurb)
                .font(.mono(11))
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            statsRow(body)
            ForEach(Array(body.facts.prefix(3).enumerated()), id: \.offset) { _, fact in
                HStack(alignment: .top, spacing: 6) {
                    Text("▸")
                        .font(.mono(9))
                        .foregroundStyle(Theme.accent)
                    Text(fact)
                        .font(.mono(9.5))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    yieldBadge(
                        claimed ? "BEACON ACTIVE" : "CLAIM +\(body.claimYield)",
                        symbol: claimed ? "checkmark.seal.fill" : "bolt.fill",
                        color: Theme.gain
                    )
                    if body.canBeDestroyed {
                        yieldBadge("DESTROY +\(body.destroyYield)", symbol: "burst.fill", color: Theme.danger)
                    }
                    if let part = body.drivePart {
                        let recovered = store.save.driveParts.contains(part)
                        yieldBadge(
                            recovered ? "\(part.label.uppercased()) RECOVERED" : "DRIVE PART · \(part.label.uppercased())",
                            symbol: part.symbol,
                            color: recovered ? Theme.dim : Theme.warn
                        )
                    }
                    if body.habitable {
                        yieldBadge("HABITABLE", symbol: "leaf.fill", color: Theme.gain)
                    }
                }
            }
        }
        .cockpitPanel()
    }

    private func statsRow(_ body: CelestialBody) -> some View {
        HStack(spacing: 12) {
            if body.kind == .star {
                stat("RADIUS", String(format: "%.2f R☉", body.radiusEarths / 109.2))
            } else if body.kind == .planet || body.kind == .dwarfPlanet {
                stat("RADIUS", String(format: "%.2f R⊕", body.radiusEarths))
            }
            if let t = body.temperatureK {
                stat("TEMP", "\(Int(t)) K")
            }
            if let d = body.orbitDays {
                stat("ORBIT", d >= 365 ? String(format: "%.1f yr", d / 365.25) : String(format: "%.0f d", d))
            }
            if let m = body.massEarths {
                stat("MASS", String(format: "%.2g M⊕", m))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            CockpitCaption(label, color: Theme.dim.opacity(0.8))
            Text(value)
                .font(.mono(9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        }
    }

    private func yieldBadge(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.mono(8.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.45), lineWidth: 1))
    }

    private func classLabel(_ body: CelestialBody) -> String {
        var parts: [String] = []
        switch body.kind {
        case .star: parts.append("STAR")
        case .planet: parts.append("PLANET")
        case .dwarfPlanet: parts.append("DWARF PLANET")
        case .blackHole: parts.append("BLACK HOLE")
        case .galaxy: parts.append("GALAXY")
        }
        if let cls = body.planetClass {
            switch cls {
            case .rocky: parts.append("ROCKY")
            case .lava: parts.append("LAVA")
            case .desert: parts.append("DESERT")
            case .ice: parts.append("ICE")
            case .ocean: parts.append("OCEAN")
            case .superEarth: parts.append("SUPER-EARTH")
            case .gasGiant: parts.append("GAS GIANT")
            case .iceGiant: parts.append("ICE GIANT")
            case .earthlike: parts.append("EARTHLIKE")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - (4)+(5) Drive status + target picker

    private var drivePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("FOLD DRIVE", symbol: "point.3.connected.trianglepath.dotted")
            HStack(spacing: 6) {
                ForEach(DrivePart.allCases) { part in
                    driveSlot(part, installed: store.save.driveParts.contains(part))
                }
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(store.hasWarpDrive ? Theme.gain : Theme.warn)
                    .frame(width: 6, height: 6)
                    .shadow(color: (store.hasWarpDrive ? Theme.gain : Theme.warn).opacity(0.9), radius: 3)
                Text(store.hasWarpDrive
                     ? "WARP DRIVE ONLINE"
                     : "WARP DRIVE OFFLINE · \(store.save.driveParts.count)/\(DrivePart.allCases.count) PARTS")
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(store.hasWarpDrive ? Theme.gain : Theme.warn)
            }
            targetPicker
        }
        .cockpitPanel(tint: store.hasWarpDrive ? Theme.accent : Theme.dim)
    }

    private func driveSlot(_ part: DrivePart, installed: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: part.symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(part.label.uppercased())
                .font(.mono(7, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(installed ? Theme.gain : Theme.dim.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(installed ? Theme.gain.opacity(0.1) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    installed ? Theme.gain.opacity(0.6) : Theme.dim.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: installed ? [] : [3, 3])
                )
        )
        .shadow(color: installed ? Theme.gain.opacity(0.4) : .clear, radius: 4)
    }

    @ViewBuilder private var targetPicker: some View {
        let options = store.reachableSystems.filter { $0.id != store.currentSystem.id }
        Menu {
            ForEach(options) { system in
                Button {
                    Haptics.tap()
                    store.targetSystemID = system.id
                } label: {
                    Label(
                        "\(system.name) · \(system.formattedDistance) · \(system.warpCost) energy",
                        systemImage: system.id == store.targetSystemID ? "scope" : "star"
                    )
                }
            }
            if options.isEmpty {
                Text("No other systems in range")
            }
            if store.targetSystemID != nil {
                Divider()
                Button("Clear target", role: .destructive) {
                    store.targetSystemID = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                Text(store.targetSystem.map { "TARGET · \($0.name.uppercased())" } ?? "SELECT TARGET STAR")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.cockpit(store.targetSystem == nil ? Theme.accent : Theme.warn))
        .disabled(options.isEmpty)

        if let target = store.targetSystem {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.compact")
                    Text("CLOSE THE PHONE TO FOLD SPACE → \(target.name.uppercased())")
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Theme.accent)
                .hudGlow(radius: 5)
                CockpitCaption(
                    "\(target.formattedDistance) · COST \(target.warpCost) · HAVE \(store.energy)",
                    color: store.energy >= target.warpCost ? Theme.dim : Theme.danger
                )
                if !store.hasWarpDrive {
                    CockpitCaption("DRIVE OFFLINE — recover all three parts first", color: Theme.warn)
                }
                if target.id == SystemID.andromeda, store.foldCoreCharge < 0.999 {
                    CockpitCaption("FOLD CORE \(Int(store.foldCoreCharge * 100))% — charge it before closing", color: Theme.warn)
                }
            }
        }
    }

    // MARK: - (6)(7)(8) Star dive · Nova Lance · Fold Core

    private var systemsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("SYSTEMS", symbol: "cpu")

            if store.currentSystem.primary.divable {
                Button {
                    Haptics.heavy()
                    store.beginSunDive()
                } label: {
                    Label("DIVE INTO \(store.currentSystem.primary.name.uppercased())", systemImage: "sun.max.trianglebadge.exclamationmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.cockpit(Theme.warn, filled: !store.save.solarCoreSample))
                .disabled(!inOrbit)
                CockpitCaption(
                    store.save.solarCoreSample
                        ? "CORE SAMPLE SECURED · the hull still burns in there"
                        : "Depth = how far you close the phone. Reach the core for the sample.",
                    color: Theme.dim
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: store.save.hasWeapon ? "bolt.horizontal.circle.fill" : "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(store.save.hasWeapon ? Theme.danger : Theme.dim)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOVA LANCE · " + (store.save.hasWeapon ? "ARMED" : "LOCKED"))
                        .font(.mono(10, weight: .bold))
                        .foregroundStyle(store.save.hasWeapon ? Theme.danger : Theme.dim)
                    Text(weaponHint)
                        .font(.mono(9))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.act == .core {
                foldCoreControls
            }
        }
        .cockpitPanel()
    }

    private var weaponHint: String {
        guard store.save.hasWeapon else {
            return "LOCKED — recover the stellar core sample. Dive into the Sun and reach its core."
        }
        let body = store.currentBody
        if body.canBeDestroyed, !store.isDestroyed(body.id) {
            return "ARMED — squeeze the phone (12–45°) to charge, snap open to fire. +\(body.destroyYield) energy. Whatever lives on \(body.name) is lost."
        }
        return "ARMED — no destroyable target in this orbit. Hop to a planet."
    }

    @ViewBuilder private var foldCoreControls: some View {
        if case .foldCoreCharging = store.phase {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("FOLD CORE \(Int(store.foldCoreCharge * 100))%")
                        .font(.mono(10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("PUMP \(hinge.pumpCount)/\(hinge.pumpTarget)")
                        .font(.mono(9))
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                    Button("CANCEL") {
                        Haptics.tap()
                        store.cancelFoldCoreCharge()
                    }
                    .buttonStyle(.cockpit(Theme.dim, size: 9))
                }
                CockpitMeter(value: store.foldCoreCharge, tint: Theme.accent)
                CockpitCaption(
                    store.foldCoreCharge >= 0.999
                        ? "CHARGED — close the phone to fold to Andromeda"
                        : "Open and shut the hinge in ≥ 40° swings",
                    color: store.foldCoreCharge >= 0.999 ? Theme.gain : Theme.dim
                )
            }
        } else {
            Button {
                Haptics.heavy()
                store.beginFoldCoreCharge()
            } label: {
                Label("CHARGE FOLD CORE → ANDROMEDA", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.cockpit(Theme.accent, filled: true))
            .disabled(!inOrbit)
        }
    }

    // MARK: - (9) Hull + repair

    private var hullPanel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    sectionHeader("HULL", symbol: "shield.lefthalf.filled")
                    Spacer()
                    Text(String(format: "%3.0f%%", store.hull))
                        .font(.mono(11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.hullColor(store.hull))
                }
                CockpitMeter(value: store.hull / 100, tint: Theme.hullColor(store.hull))
            }
            Button {
                let before = store.hull
                store.repair()
                if store.hull > before { Haptics.success() } else { Haptics.warning() }
            } label: {
                Text("REPAIR −20")
            }
            .buttonStyle(.cockpit(Theme.gain, size: 9))
            .disabled(store.hull >= 100 || store.energy < 20)
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("\(store.energy)")
                    .font(.mono(11, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.gain)
        }
        .cockpitPanel(tint: Theme.hullColor(store.hull))
    }

    // MARK: - (10) Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("LOG", symbol: "text.alignleft")
            if store.save.log.isEmpty {
                CockpitCaption("No entries")
            }
            ForEach(Array(store.save.log.suffix(4).reversed())) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Rectangle()
                        .fill(logColor(entry.kind))
                        .frame(width: 2)
                        .padding(.vertical, 1)
                    Text(entry.text)
                        .font(.mono(9))
                        .foregroundStyle(logColor(entry.kind).opacity(entry.kind == .info ? 0.85 : 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cockpitPanel(tint: Theme.dim)
        .padding(.bottom, 4)
    }

    private func logColor(_ kind: LogEntry.Kind) -> Color {
        switch kind {
        case .info: return Theme.dim
        case .gain: return Theme.gain
        case .danger: return Theme.danger
        case .story: return Theme.accent
        }
    }

    // MARK: - (3) Probe bar + (11) gear menu

    private func probeBar(consoleHeight: CGFloat) -> some View {
        let body = store.currentBody
        let claimed = store.isClaimed(body.id)
        let claimable = !claimed && !store.isDestroyed(body.id) && inOrbit
        let threshold = consoleHeight * 0.55
        return HStack(spacing: 12) {
            probe(claimable: claimable, threshold: threshold)
            VStack(alignment: .leading, spacing: 3) {
                Text(claimable ? "BEACON PROBE" : (claimed ? "BEACON ACTIVE" : "PROBE OFFLINE"))
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(claimable ? Theme.accent : Theme.dim)
                Text(claimable
                     ? "Drag up across the fold into the hologram to claim \(body.name)."
                     : (claimed ? "\(body.name) is already on the beacon network." : "Establish orbit first."))
                    .font(.mono(8.5))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button {
                plantBeacon()
            } label: {
                Text("PLANT\nBEACON")
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.cockpit(Theme.gain, size: 9))
            .disabled(!claimable)
            gearMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func probe(claimable: Bool, threshold: CGFloat) -> some View {
        let tint: Color = probeArmed ? Theme.gain : (claimable ? Theme.accent : Theme.dim)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.55), Theme.panel], center: .center, startRadius: 2, endRadius: 26))
            Circle()
                .strokeBorder(tint, lineWidth: 1.5)
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                .padding(5)
            Image(systemName: probeArmed ? "antenna.radiowaves.left.and.right" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 54, height: 54)
        .shadow(color: tint.opacity(probeDragging ? 0.9 : 0.4), radius: probeDragging ? 14 : 6)
        .scaleEffect(probeDragging ? 1.15 : 1)
        .offset(probeOffset)
        .zIndex(50)
        .opacity(claimable ? 1 : 0.45)
        .animation(.easeOut(duration: 0.15), value: probeArmed)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard claimable else { return }
                    probeDragging = true
                    probeOffset = CGSize(width: value.translation.width * 0.6, height: value.translation.height)
                    let armed = value.translation.height < -threshold
                    if armed != probeArmed {
                        probeArmed = armed
                        if armed { Haptics.heavy() } else { Haptics.tap() }
                    }
                }
                .onEnded { value in
                    let crossed = claimable && value.translation.height < -threshold
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                        probeOffset = .zero
                        probeDragging = false
                        probeArmed = false
                    }
                    if crossed {
                        plantBeacon()
                    }
                }
        )
        .accessibilityLabel("Beacon probe")
        .accessibilityHint("Drag up across the fold to claim the current body")
    }

    private func plantBeacon() {
        if store.claim(store.currentBody.id) {
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    private var gearMenu: some View {
        Menu {
            Section("Commander \(store.save.callsign)") {
                Button {
                    callsignDraft = store.save.callsign
                    showCallsignEditor = true
                } label: {
                    Label("Edit callsign", systemImage: "person.text.rectangle")
                }
            }
            Section("Stage demo") {
                Button {
                    Haptics.success()
                    store.demoSkip(to: .warp)
                } label: {
                    Label("Demo → Act II · Warp", systemImage: "2.circle")
                }
                Button {
                    Haptics.success()
                    store.demoSkip(to: .core)
                } label: {
                    Label("Demo → Act III · The Core", systemImage: "3.circle")
                }
            }
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset commander", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.dim.opacity(0.4), lineWidth: 1))
        }
        .accessibilityLabel("Settings")
    }

    private func saveCallsign() {
        let cleaned = callsignDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return }
        store.save.callsign = String(cleaned.prefix(12))
        store.registry?.callsign = store.save.callsign
        store.log("Callsign registered: \(store.save.callsign).")
        Haptics.success()
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.mono(9, weight: .bold))
                .tracking(1.5)
        }
        .foregroundStyle(Theme.accent.opacity(0.85))
    }
}
