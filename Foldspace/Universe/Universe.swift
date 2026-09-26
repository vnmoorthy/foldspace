import Foundation

/// Kinds of things the ship can orbit.
enum BodyKind: String, Codable, Sendable {
    case star, planet, dwarfPlanet, blackHole, galaxy
}

/// Visual / gameplay class for planets (drives procedural materials in Scene/PlanetMaterials.swift).
enum PlanetClass: String, Codable, Sendable {
    case rocky, lava, desert, ice, ocean, superEarth, gasGiant, iceGiant, earthlike
}

/// Warp-drive parts hidden in the Solar System (Act 1).
enum DrivePart: String, Codable, Sendable, CaseIterable, Identifiable {
    case exoticMatter    // negative-energy density — the Alcubierre requirement
    case fieldCoil       // shapes the warp bubble
    case navigationCore  // plots the fold
    var id: String { rawValue }
    var label: String {
        switch self {
        case .exoticMatter: return "Exotic Matter"
        case .fieldCoil: return "Field Coil"
        case .navigationCore: return "Navigation Core"
        }
    }
    var symbol: String {
        switch self {
        case .exoticMatter: return "atom"
        case .fieldCoil: return "circle.hexagongrid"
        case .navigationCore: return "scope"
        }
    }
}

struct CelestialBody: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: BodyKind
    var planetClass: PlanetClass? = nil
    /// One-line scan result shown in the cockpit.
    let blurb: String
    /// 2–3 real facts (shown in the scan panel). Keep them true.
    let facts: [String]
    /// Radius relative to Earth (Sun ≈ 109, Jupiter ≈ 11.2). Used for rendering scale only.
    let radiusEarths: Double
    var massEarths: Double? = nil
    /// Equilibrium / surface temperature in kelvin, if known.
    var temperatureK: Double? = nil
    var orbitDays: Double? = nil
    /// Base colour as hex "RRGGBB".
    let colorHex: String
    /// Energy gained by claiming (scanning + planting a beacon).
    var claimYield: Int = 10
    /// Energy gained by destroying it with the Nova Lance (always bigger — that's the temptation).
    var destroyYield: Int = 40
    /// Solar-system planets hide warp-drive parts.
    var drivePart: DrivePart? = nil
    var habitable: Bool = false
    /// Stars can be dived into (Sun dive sequence).
    var divable: Bool = false

    var isPlanetLike: Bool { kind == .planet || kind == .dwarfPlanet }
    var canBeDestroyed: Bool { isPlanetLike }
}

/// Position on the galaxy map, unit square (0...1). Sol sits near the centre-left; Andromeda off the top-right edge.
struct MapPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

struct StarSystem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    /// Distance from Sol in light-years (0 for Sol). Andromeda ≈ 2.5 million.
    let distanceLY: Double
    let map: MapPoint
    /// The star, black hole or galaxy at the centre.
    let primary: CelestialBody
    /// Orbiting bodies in order from the primary.
    let bodies: [CelestialBody]
    /// Which act unlocks it: 1 = stranded (Sol), 2 = warp era, 3 = galactic core / intergalactic.
    let act: Int
    let lore: String
    /// Energy needed to fold space here.
    var warpCost: Int = 0

    var allBodies: [CelestialBody] { [primary] + bodies }

    func body(_ id: String) -> CelestialBody? { allBodies.first { $0.id == id } }

    var formattedDistance: String {
        switch distanceLY {
        case 0: return "HOME"
        case ..<1000: return String(format: "%.1f ly", distanceLY)
        case ..<1_000_000: return String(format: "%.0f ly", distanceLY)
        default: return String(format: "%.1f M ly", distanceLY / 1_000_000)
        }
    }
}

/// Everything in the game universe. Populated in Universe/UniverseData.swift.
struct Universe: Sendable {
    let systems: [StarSystem]

    func system(_ id: String) -> StarSystem? { systems.first { $0.id == id } }

    func body(_ id: String) -> (StarSystem, CelestialBody)? {
        for s in systems { if let b = s.body(id) { return (s, b) } }
        return nil
    }

    /// Distance between two systems for warp timing.
    func distance(from a: StarSystem, to b: StarSystem) -> Double {
        if a.id == b.id { return 0 }
        if a.id == SystemID.sol { return b.distanceLY }
        if b.id == SystemID.sol { return a.distanceLY }
        let dx = a.map.x - b.map.x, dy = a.map.y - b.map.y
        let mapDist = (dx * dx + dy * dy).squareRoot()
        let scale = max(a.distanceLY, b.distanceLY)
        return max(0.5, mapDist * scale * 1.2)
    }
}

// MARK: - Well-known ids (used across UI + game logic)
enum SystemID {
    static let sol = "sol"
    static let alphaCentauri = "alpha-centauri"
    static let barnards = "barnards-star"
    static let wolf359 = "wolf-359"
    static let sirius = "sirius"
    static let epsilonEridani = "epsilon-eridani"
    static let tauCeti = "tau-ceti"
    static let trappist1 = "trappist-1"
    static let sagittariusA = "sagittarius-a"
    static let andromeda = "andromeda"
}

enum BodyID {
    static let sun = "sun"
    static let earth = "earth"
    static let sagittariusAStar = "sgr-a-star"
    static let andromedaGalaxy = "m31"
}
