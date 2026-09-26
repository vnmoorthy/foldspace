import Foundation
import Observation

/// What the ship is doing right now. Every sequence view keys off this.
enum FlightPhase: Equatable, Sendable {
    case docked                         // phone closed at home: outer display shows ship status
    case orbit                          // in orbit around `bodyID`; cockpit visible
    case hopping(to: String)            // short in-system hop (hinge dip)
    case warping(to: String)            // folding space to another system (phone closed)
    case sunDive                        // diving into the current star (hinge angle = depth)
    case weaponCharging                 // squeezed: Nova Lance charging
    case weaponFiring(target: String)   // snap open: beam + shatter
    case blackHole                      // Sagittarius A* slingshot level
    case foldCoreCharging               // pumping the hinge to charge the intergalactic jump
    case intergalacticJump              // the 2.5 M ly fold
    case andromeda                      // finale
    case shipLost                       // hull hit zero (sun / black hole)

    var isTransit: Bool {
        switch self {
        case .warping, .intergalacticJump, .hopping: return true
        default: return false
        }
    }
}

enum Act: Int, Codable, Sendable {
    case stranded = 1   // Solar System only. Find the three drive parts.
    case warp = 2       // Warp drive online. Nearby stars.
    case core = 3       // Fold Core. Sagittarius A* and Andromeda.

    var title: String {
        switch self {
        case .stranded: return "ACT I · STRANDED"
        case .warp: return "ACT II · WARP"
        case .core: return "ACT III · THE CORE"
        }
    }
}

struct LogEntry: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var kind: Kind = .info
    enum Kind: String, Codable, Sendable { case info, gain, danger, story }
}

/// Persisted progress.
struct SaveData: Codable, Sendable {
    var systemID = SystemID.sol
    var bodyID = BodyID.earth
    var energy = 0
    var driveParts: Set<DrivePart> = []
    var claimed: Set<String> = []
    var destroyed: Set<String> = []
    var hasWeapon = false
    var solarCoreSample = false
    var passedSagittariusA = false
    var reachedAndromeda = false
    var earthYearsElapsed: Double = 0
    var callsign = "COMMANDER"
    var log: [LogEntry] = []
}

/// The game's single state store. Sequences and the console mutate it through its methods;
/// views observe it. Hinge gestures reach it via `FlightController`.
@MainActor
@Observable
final class GameStore {
    let universe: Universe
    var save = SaveData()
    var phase: FlightPhase = .orbit
    /// System chosen on the galaxy map (warp destination).
    var targetSystemID: String?
    /// Hull integrity 0...100 (drops during a sun dive / black hole pass).
    var hull: Double = 100
    /// 0...1 Nova Lance charge while squeezed.
    var weaponCharge: Double = 0
    /// 0...1 Fold Core charge (pumps).
    var foldCoreCharge: Double = 0
    /// 0...1 depth into the star during a sun dive (hinge-driven).
    var diveDepth: Double = 0
    /// 0...1 progress of the current warp / hop animation.
    var transitProgress: Double = 0
    /// Quality of the last warp close (0...1). < 0.45 drops you out early.
    var lastWarpQuality: Double = 1
    /// Bumped whenever the scene should play a one-shot effect.
    var shatterEvent: (target: String, at: Date)?
    var toast: String?
    /// Galactic registry (backend). Optional so the game runs fully offline.
    var registry: GalacticRegistry?

    private var transitTask: Task<Void, Never>?

    init(universe: Universe = UniverseData.universe) {
        self.universe = universe
        load()
    }

    // MARK: - Derived

    var currentSystem: StarSystem { universe.system(save.systemID) ?? universe.systems[0] }
    var currentBody: CelestialBody { currentSystem.body(save.bodyID) ?? currentSystem.primary }
    var targetSystem: StarSystem? { targetSystemID.flatMap(universe.system) }
    var hasWarpDrive: Bool { save.driveParts.count == DrivePart.allCases.count }
    var act: Act {
        if save.passedSagittariusA || save.solarCoreSample && save.claimed.count >= 6 { return .core }
        return hasWarpDrive ? .warp : .stranded
    }
    var energy: Int { save.energy }
    func isClaimed(_ id: String) -> Bool { save.claimed.contains(id) }
    func isDestroyed(_ id: String) -> Bool { save.destroyed.contains(id) }
    func isUnlocked(_ system: StarSystem) -> Bool { system.act <= act.rawValue }
    /// Bodies that still exist in the current system (destroyed ones are gone for good).
    var livingBodies: [CelestialBody] { currentSystem.bodies.filter { !isDestroyed($0.id) } }

    /// Planets near home the drive can reach in Act II.
    var reachableSystems: [StarSystem] { universe.systems.filter { isUnlocked($0) } }

    // MARK: - Logging

    func log(_ text: String, _ kind: LogEntry.Kind = .info) {
        save.log.append(LogEntry(text: text, kind: kind))
        if save.log.count > 60 { save.log.removeFirst(save.log.count - 60) }
        toast = text
        persist()
    }

    // MARK: - Claiming (probe dragged across the fold into the hologram)

    @discardableResult
    func claim(_ bodyID: String) -> Bool {
        guard let body = currentSystem.body(bodyID), !isClaimed(bodyID), !isDestroyed(bodyID) else { return false }
        save.claimed.insert(bodyID)
        save.energy += body.claimYield
        var msg = "Beacon planted on \(body.name). +\(body.claimYield) energy."
        if let part = body.drivePart, !save.driveParts.contains(part) {
            save.driveParts.insert(part)
            msg += " Recovered \(part.label)!"
            if hasWarpDrive {
                log(msg, .gain)
                log("WARP DRIVE ASSEMBLED. Close the phone to fold space.", .story)
                registry?.record(.driveAssembled, body: bodyID, energy: save.energy)
                return true
            }
        }
        log(msg, .gain)
        registry?.record(.claimed, body: bodyID, energy: save.energy)
        return true
    }

    // MARK: - Hop (hinge dip)

    func hopToNextBody() {
        guard case .orbit = phase else { return }
        let alive = livingBodies
        guard alive.count > 1 else { return }
        let idx = alive.firstIndex { $0.id == save.bodyID } ?? -1
        let next = alive[(idx + 1) % alive.count]
        hop(to: next.id)
    }

    func hop(to bodyID: String) {
        guard currentSystem.body(bodyID) != nil, !isDestroyed(bodyID) else { return }
        guard case .orbit = phase else { return }
        phase = .hopping(to: bodyID)
        transitProgress = 0
        transitTask?.cancel()
        transitTask = Task { @MainActor in
            for i in 1...30 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if Task.isCancelled { return }
                transitProgress = Double(i) / 30
            }
            save.bodyID = bodyID
            phase = .orbit
            log("Orbit established: \(currentBody.name).")
        }
    }

    // MARK: - Warp (close the phone)

    /// Called by FlightController when the hinge closes with the drive online and a target set.
    func beginWarp(quality: Double) {
        guard hasWarpDrive, let target = targetSystem, target.id != save.systemID, isUnlocked(target) else { return }
        guard save.energy >= target.warpCost else {
            log("Insufficient energy to fold to \(target.name). Need \(target.warpCost).", .danger)
            return
        }
        if target.id == SystemID.andromeda {
            guard foldCoreCharge >= 0.999 else {
                log("Andromeda needs a charged Fold Core. Pump the hinge.", .danger)
                return
            }
        }
        lastWarpQuality = quality
        save.energy -= target.warpCost
        phase = target.id == SystemID.andromeda ? .intergalacticJump : .warping(to: target.id)
        transitProgress = 0
        let distance = universe.distance(from: currentSystem, to: target)
        // 2.2 s for a neighbour, ~5 s for the galactic core, 7 s for Andromeda.
        let duration: Double = target.id == SystemID.andromeda ? 7 : min(5, 2.2 + log10(max(1, distance)) * 0.9)
        log("Folding space → \(target.name) (\(target.formattedDistance)).", .story)
        registry?.record(.warped, body: target.id, energy: save.energy)
        transitTask?.cancel()
        transitTask = Task { @MainActor in
            let steps = Int(duration * 30)
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 33_000_000)
                if Task.isCancelled { return }
                transitProgress = Double(i) / Double(steps)
            }
            completeWarp()
        }
    }

    func completeWarp() {
        switch phase {
        case .warping(let to):
            if lastWarpQuality < 0.45, to != SystemID.sagittariusA {
                // Bubble collapsed: drop out at the nearest unlocked system that isn't the target.
                log("Warp bubble collapsed — closed too \(lastWarpQuality < 0.3 ? "fast" : "slowly"). Dropped out short.", .danger)
                hull = max(20, hull - 15)
            } else {
                save.systemID = to
                save.bodyID = currentSystem.bodies.first?.id ?? currentSystem.primary.id
                log("Arrived: \(currentSystem.name). \(currentSystem.lore)", .story)
            }
            targetSystemID = nil
            transitProgress = 0
            phase = to == SystemID.sagittariusA && lastWarpQuality >= 0.45 ? .blackHole : .orbit
        case .intergalacticJump:
            save.systemID = SystemID.andromeda
            save.bodyID = BodyID.andromedaGalaxy
            save.reachedAndromeda = true
            foldCoreCharge = 0
            phase = .andromeda
            log("2.5 million light-years. You are the first.", .story)
            registry?.record(.reachedAndromeda, body: BodyID.andromedaGalaxy, energy: save.energy)
        default: break
        }
        persist()
    }

    // MARK: - Nova Lance (squeeze + snap)

    func beginWeaponCharge() {
        guard save.hasWeapon, case .orbit = phase, currentBody.canBeDestroyed, !isDestroyed(currentBody.id) else { return }
        phase = .weaponCharging
        weaponCharge = 0
    }

    /// Called every frame while charging with the current hinge angle (peek zone 12...45).
    func updateWeaponCharge(hingeAngle: Double, dt: Double) {
        guard case .weaponCharging = phase else { return }
        let squeeze = max(0, min(1, (45 - hingeAngle) / 33)) // tighter squeeze charges faster
        weaponCharge = min(1, weaponCharge + dt * (0.35 + squeeze * 0.9))
    }

    func cancelWeaponCharge() {
        guard case .weaponCharging = phase else { return }
        phase = .orbit
        weaponCharge = 0
        log("Nova Lance discharged safely.")
    }

    func fireWeapon() {
        guard case .weaponCharging = phase else { return }
        let target = currentBody
        guard weaponCharge >= 0.6 else {
            cancelWeaponCharge()
            log("Charge too low — hold the squeeze longer.", .danger)
            return
        }
        phase = .weaponFiring(target: target.id)
        if target.kind == .blackHole {
            log("The beam bends into Sagittarius A* and vanishes. Nothing escapes.", .story)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                weaponCharge = 0
                phase = .blackHole
            }
            return
        }
        shatterEvent = (target.id, Date())
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            save.destroyed.insert(target.id)
            save.energy += target.destroyYield
            weaponCharge = 0
            let remaining = livingBodies
            save.bodyID = remaining.first?.id ?? currentSystem.primary.id
            phase = .orbit
            log("\(target.name) is gone. +\(target.destroyYield) energy. Whatever lived there is lost.", .danger)
            registry?.record(.destroyed, body: target.id, energy: save.energy)
        }
    }

    // MARK: - Sun dive (hinge angle = depth)

    func beginSunDive() {
        guard case .orbit = phase, currentSystem.primary.divable else { return }
        phase = .sunDive
        diveDepth = 0
        log("Solar shield up. Close the phone to dive. Open it to climb out.", .story)
    }

    /// depth 0 = corona, 1 = core. Called every frame from the dive view with the hinge fold amount.
    func updateSunDive(depth: Double, dt: Double) {
        guard case .sunDive = phase else { return }
        diveDepth = max(0, min(1, depth))
        // Hull burns faster the deeper you go; it never regenerates inside the star.
        let burn = pow(diveDepth, 2.2) * 26 + (diveDepth > 0.15 ? 1.5 : 0)
        hull = max(0, hull - burn * dt)
        if diveDepth > 0.97, !save.solarCoreSample {
            save.solarCoreSample = true
            save.energy += 120
            save.hasWeapon = true
            log("STELLAR CORE SAMPLE secured. +120 energy. Fusion pressure unlocks the NOVA LANCE.", .gain)
            registry?.record(.coreSample, body: currentSystem.primary.id, energy: save.energy)
        }
        if hull <= 0 {
            phase = .shipLost
            log("Hull vaporised at \(Int(SunLayer.at(depth: diveDepth).temperatureK)) K.", .danger)
        }
    }

    func endSunDive() {
        guard case .sunDive = phase else { return }
        phase = .orbit
        diveDepth = 0
        log(hull < 40 ? "Climbed out with \(Int(hull))% hull. That was close." : "Climbed out of the star.")
    }

    // MARK: - Sagittarius A*

    func blackHoleEscaped() {
        guard case .blackHole = phase else { return }
        save.passedSagittariusA = true
        save.bodyID = BodyID.sagittariusAStar
        phase = .orbit
        log("Slingshot complete. Time dilation cost you \(Int(save.earthYearsElapsed)) Earth years. Fold Core unlocked.", .story)
        registry?.record(.passedBlackHole, body: BodyID.sagittariusAStar, energy: save.energy)
    }

    func blackHoleConsumed() {
        guard case .blackHole = phase else { return }
        phase = .shipLost
        log("Spaghettified. Even light doesn't leave here.", .danger)
    }

    func addEarthYears(_ years: Double) { save.earthYearsElapsed += years }

    // MARK: - Fold Core (pump the hinge)

    func beginFoldCoreCharge() {
        guard save.passedSagittariusA || act == .core else { return }
        guard case .orbit = phase else { return }
        phase = .foldCoreCharging
        foldCoreCharge = 0
        targetSystemID = SystemID.andromeda
        log("Pump the hinge to charge the Fold Core. Then slam it shut.", .story)
    }

    func recordPump(count: Int, target: Int) {
        guard case .foldCoreCharging = phase else { return }
        foldCoreCharge = min(1, Double(count) / Double(target))
    }

    func foldCoreCharged() {
        guard case .foldCoreCharging = phase else { return }
        foldCoreCharge = 1
        log("FOLD CORE AT 100%. Close the phone.", .gain)
    }

    func cancelFoldCoreCharge() {
        guard case .foldCoreCharging = phase else { return }
        phase = .orbit
        foldCoreCharge = 0
    }

    // MARK: - Docking / recovery

    func respawn() {
        hull = 100
        diveDepth = 0
        phase = .orbit
        save.bodyID = currentSystem.bodies.first { !isDestroyed($0.id) }?.id ?? currentSystem.primary.id
        log("Backup ship deployed from the beacon network.")
    }

    func repair() {
        guard save.energy >= 20, hull < 100 else { return }
        save.energy -= 20
        hull = 100
        log("Hull repaired. −20 energy.")
    }

    func reset() {
        transitTask?.cancel()
        save = SaveData()
        hull = 100
        phase = .orbit
        targetSystemID = nil
        weaponCharge = 0
        foldCoreCharge = 0
        diveDepth = 0
        transitProgress = 0
        persist()
        log("New commander. You are stranded in the Solar System. Find the three drive parts.", .story)
    }

    /// Jump straight to a late-game state for stage demos.
    func demoSkip(to act: Act) {
        transitTask?.cancel()
        switch act {
        case .stranded:
            reset()
        case .warp:
            save.driveParts = Set(DrivePart.allCases)
            save.claimed.formUnion(["earth", "mars", "jupiter", "neptune"])
            save.energy = max(save.energy, 200)
            save.systemID = SystemID.sol
            save.bodyID = BodyID.earth
            phase = .orbit
            log("DEMO: Warp drive online.", .story)
        case .core:
            save.driveParts = Set(DrivePart.allCases)
            save.hasWeapon = true
            save.solarCoreSample = true
            save.passedSagittariusA = true
            save.claimed.formUnion(["earth", "mars", "jupiter", "neptune", "proxima-b", "trappist-1e", "barnard-b"])
            save.energy = max(save.energy, 600)
            save.systemID = SystemID.sagittariusA
            save.bodyID = BodyID.sagittariusAStar
            hull = 100
            phase = .orbit
            log("DEMO: Fold Core unlocked. Pump the hinge for Andromeda.", .story)
        }
        persist()
    }

    // MARK: - Persistence

    private static let key = "foldspace.save.v1"

    func persist() {
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(SaveData.self, from: data) {
            save = s
        } else {
            save.log = [LogEntry(text: "You are stranded in the Solar System. Find the three drive parts.", kind: .story)]
        }
    }
}

/// Layers of the Sun, outermost first. Depth 0...1 maps across them (real temperatures).
struct SunLayer: Sendable {
    let name: String
    let temperatureK: Double
    let depthStart: Double
    let note: String

    static let layers: [SunLayer] = [
        SunLayer(name: "CORONA", temperatureK: 1_000_000, depthStart: 0.0, note: "Hotter than the surface below it — a mystery physicists still argue about."),
        SunLayer(name: "CHROMOSPHERE", temperatureK: 20_000, depthStart: 0.12, note: "Pink-red hydrogen glow, only visible during eclipses."),
        SunLayer(name: "PHOTOSPHERE", temperatureK: 5_800, depthStart: 0.22, note: "The 'surface' — the light you see left here 8 minutes ago."),
        SunLayer(name: "CONVECTIVE ZONE", temperatureK: 2_000_000, depthStart: 0.35, note: "Plasma boils in cells the size of Texas."),
        SunLayer(name: "RADIATIVE ZONE", temperatureK: 7_000_000, depthStart: 0.62, note: "A photon takes ~100,000 years to random-walk through here."),
        SunLayer(name: "CORE", temperatureK: 15_000_000, depthStart: 0.88, note: "600 million tonnes of hydrogen fuse every second."),
    ]

    static func at(depth: Double) -> SunLayer {
        layers.last { depth >= $0.depthStart } ?? layers[0]
    }
}
