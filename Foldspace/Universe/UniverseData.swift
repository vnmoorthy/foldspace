import Foundation

/// The hand-authored FOLDSPACE universe: ten systems across three acts.
///
/// Every number here is real, or the best current estimate. Radii are in Earth radii,
/// masses in Earth masses, temperatures in kelvin (equilibrium / mean surface), orbits in Earth days.
/// `colorHex` is the base render colour; `planetClass` drives the procedural material.
///
/// Radii of non-transiting worlds (Proxima b/d, Barnard b–e, Wolf 359 b, Tau Ceti e/f, ε Eri b)
/// are not measured — they are mass–radius estimates used for render scale only.
///
/// `Universe.systems[0]` must be Sol: `GameStore.currentSystem` falls back to it.
enum UniverseData {

    /// One solar mass in Earth masses.
    private static let solarMassEarths: Double = 333_000

    static let universe = Universe(systems: [
        sol,
        alphaCentauri,
        barnardsStar,
        wolf359,
        sirius,
        epsilonEridani,
        tauCeti,
        trappist1,
        sagittariusA,
        andromeda,
    ])

    // MARK: - Act I · Sol

    private static let sol: StarSystem = StarSystem(
        id: SystemID.sol,
        name: "Sol",
        distanceLY: 0,
        map: MapPoint(x: 0.30, y: 0.55),
        primary: CelestialBody(
            id: BodyID.sun,
            name: "The Sun",
            kind: .star,
            blurb: "A middle-aged G-type star, 4.6 billion years in and about halfway through its hydrogen.",
            facts: [
                "Core temperature ~15 million K; it fuses ~600 million tonnes of hydrogen into helium every second.",
                "Holds 99.8% of the Solar System's mass — everything else is rounding error.",
                "Sunlight takes 8 min 20 s to reach Earth, but that energy spent tens of thousands of years escaping the core."
            ],
            radiusEarths: 109,
            massEarths: solarMassEarths,
            temperatureK: 5772,
            colorHex: "FFC94D",
            claimYield: 20,
            divable: true
        ),
        bodies: [
            CelestialBody(
                id: "mercury", name: "Mercury", kind: .planet, planetClass: .rocky,
                blurb: "A scorched iron cannonball skimming the Sun — no air, no moons, no mercy.",
                facts: [
                    "One Mercury solar day (sunrise to sunrise) lasts 176 Earth days — two of its 88-day years.",
                    "Surface swings from about −180 °C at night to 430 °C in daylight.",
                    "Its iron core fills roughly 85% of the planet's radius — likely the scar of an ancient giant impact."
                ],
                radiusEarths: 0.383, massEarths: 0.055, temperatureK: 440, orbitDays: 88.0,
                colorHex: "8C8078", claimYield: 10, destroyYield: 40
            ),
            CelestialBody(
                id: "venus", name: "Venus", kind: .planet, planetClass: .desert,
                blurb: "Earth's twin gone wrong: a crushing CO₂ oven hidden under sulphuric-acid clouds.",
                facts: [
                    "Hottest planet in the Solar System: ~465 °C (737 K) at the surface, from a runaway greenhouse.",
                    "Surface pressure is ~92 bar — like standing 900 m under the ocean.",
                    "Spins backwards, and so slowly that its day (243 Earth days) is longer than its year (225)."
                ],
                radiusEarths: 0.949, massEarths: 0.815, temperatureK: 737, orbitDays: 224.7,
                colorHex: "E0B570", claimYield: 12, destroyYield: 50
            ),
            CelestialBody(
                id: BodyID.earth, name: "Earth", kind: .planet, planetClass: .earthlike,
                blurb: "Home. The only place in the known universe where anything has ever looked up and wondered.",
                facts: [
                    "The only known world with liquid surface water and life; ~71% of it is ocean.",
                    "The atmosphere's 21% oxygen is produced almost entirely by living things.",
                    "The Moon is drifting away at ~3.8 cm per year, slowly lengthening Earth's day."
                ],
                radiusEarths: 1.0, massEarths: 1.0, temperatureK: 288, orbitDays: 365.25,
                colorHex: "3B82D6", claimYield: 25, destroyYield: 80, habitable: true
            ),
            CelestialBody(
                id: "mars", name: "Mars", kind: .planet, planetClass: .desert,
                blurb: "A cold rust-red desert with the tallest mountain and deepest canyon in the Solar System.",
                facts: [
                    "Olympus Mons rises ~22 km — about 2.5× the height of Everest.",
                    "Valles Marineris runs ~4,000 km, roughly the width of the continental United States.",
                    "A Martian day is 24 h 37 min; a year is 687 Earth days. Its two tiny moons may be captured asteroids."
                ],
                radiusEarths: 0.532, massEarths: 0.107, temperatureK: 210, orbitDays: 687,
                colorHex: "C4613A", claimYield: 15, destroyYield: 50, drivePart: .fieldCoil
            ),
            CelestialBody(
                id: "jupiter", name: "Jupiter", kind: .planet, planetClass: .gasGiant,
                blurb: "The king: a banded hydrogen giant with a storm wider than Earth and a moon bigger than Mercury.",
                facts: [
                    "About 2.5× the mass of all the other planets combined.",
                    "The Great Red Spot is a storm wider than Earth, observed continuously since at least 1831.",
                    "Has at least 95 known moons; Ganymede is larger than Mercury and hides a subsurface ocean."
                ],
                radiusEarths: 11.21, massEarths: 317.8, temperatureK: 165, orbitDays: 4333,
                colorHex: "D2A374", claimYield: 15, destroyYield: 70, drivePart: .exoticMatter
            ),
            CelestialBody(
                id: "saturn", name: "Saturn", kind: .planet, planetClass: .gasGiant,
                blurb: "A pale gold giant wearing the most spectacular ring system in the Solar System.",
                facts: [
                    "The rings span ~280,000 km yet are mostly under 1 km thick — almost pure water ice.",
                    "Average density is 0.69 g/cm³, less than water; it would float in a big enough bath.",
                    "Titan, its largest moon, has a thick nitrogen atmosphere and lakes of liquid methane."
                ],
                radiusEarths: 9.45, massEarths: 95.2, temperatureK: 134, orbitDays: 10_759,
                colorHex: "E4C98A", claimYield: 15, destroyYield: 65
            ),
            CelestialBody(
                id: "uranus", name: "Uranus", kind: .planet, planetClass: .iceGiant,
                blurb: "A nearly featureless cyan ice giant rolling around the Sun on its side.",
                facts: [
                    "Its axis is tilted ~98°, so each pole gets 42 years of daylight followed by 42 of night.",
                    "Coldest planetary atmosphere ever measured: down to ~49 K (−224 °C).",
                    "Visited only once, by Voyager 2 in January 1986."
                ],
                radiusEarths: 4.01, massEarths: 14.5, temperatureK: 76, orbitDays: 30_687,
                colorHex: "7CD4DE", claimYield: 12, destroyYield: 60
            ),
            CelestialBody(
                id: "neptune", name: "Neptune", kind: .planet, planetClass: .iceGiant,
                blurb: "The deep-blue outermost planet, whipped by the fastest winds ever measured.",
                facts: [
                    "Winds reach ~2,100 km/h — the fastest known in the Solar System.",
                    "The first planet found by mathematics: Le Verrier predicted its position, Galle saw it in 1846.",
                    "Triton orbits backwards and is probably a captured Kuiper Belt object."
                ],
                radiusEarths: 3.88, massEarths: 17.1, temperatureK: 72, orbitDays: 60_190,
                colorHex: "3E6BD1", claimYield: 15, destroyYield: 60, drivePart: .navigationCore
            ),
        ],
        act: 1,
        lore: "Home. Eight worlds around one ordinary star — and the only one you know of that ever grew anything alive.",
        warpCost: 0
    )

    // MARK: - Act II · Warp era

    private static let alphaCentauri: StarSystem = StarSystem(
        id: SystemID.alphaCentauri,
        name: "Alpha Centauri",
        distanceLY: 4.24,
        map: MapPoint(x: 0.37, y: 0.63),
        primary: CelestialBody(
            id: "alpha-cen-a",
            name: "Alpha Centauri A",
            kind: .star,
            blurb: "A Sun-like G2 star in a tight triple with Alpha Centauri B and the red dwarf Proxima.",
            facts: [
                "Alpha Centauri A and B orbit each other every ~79.9 years; Proxima circles both, 4.24 ly from Earth.",
                "Together A and B are the third-brightest star in Earth's night sky.",
                "A is ~10% more massive and ~50% more luminous than the Sun."
            ],
            radiusEarths: 133,
            massEarths: 1.08 * solarMassEarths,
            temperatureK: 5790,
            colorHex: "FFE3A8",
            claimYield: 20
        ),
        bodies: [
            CelestialBody(
                id: "proxima-d", name: "Proxima d", kind: .planet, planetClass: .rocky,
                blurb: "A sub-Earth skimming Proxima Centauri every five days — too hot and too small to hold much of anything.",
                facts: [
                    "Minimum mass ~0.26 Earths — one of the lightest planets ever found by radial velocity.",
                    "Orbits at ~0.029 AU, about 1/13th of Mercury's distance from the Sun.",
                    "Confirmed in 2022 with the ESPRESSO spectrograph on ESO's Very Large Telescope."
                ],
                radiusEarths: 0.81, massEarths: 0.26, temperatureK: 360, orbitDays: 5.12,
                colorHex: "8A7B6E", claimYield: 12, destroyYield: 45
            ),
            CelestialBody(
                id: "proxima-b", name: "Proxima b", kind: .planet, planetClass: .rocky,
                blurb: "The closest known exoplanet, hugging a flare-prone red dwarf inside its habitable zone.",
                facts: [
                    "Minimum mass ~1.07 Earths; orbits Proxima Centauri every 11.2 days at 0.049 AU.",
                    "Receives ~65% of the starlight Earth does — but Proxima's flares may have stripped its air.",
                    "Discovered in 2016 (Anglada-Escudé et al.); probably tidally locked with one permanent dayside."
                ],
                radiusEarths: 1.1, massEarths: 1.07, temperatureK: 234, orbitDays: 11.19,
                colorHex: "9C8A78", claimYield: 25, destroyYield: 75, habitable: true
            ),
        ],
        act: 2,
        lore: "The nearest streetlight to home — three suns sharing one sky, and a red-dwarf world that might still be listening.",
        warpCost: 30
    )

    private static let barnardsStar: StarSystem = StarSystem(
        id: SystemID.barnards,
        name: "Barnard's Star",
        distanceLY: 5.96,
        map: MapPoint(x: 0.24, y: 0.45),
        primary: CelestialBody(
            id: "barnard",
            name: "Barnard's Star",
            kind: .star,
            blurb: "A dim, ancient red dwarf with the fastest proper motion of any star — it crosses a Moon-width of sky every ~180 years.",
            facts: [
                "Second-closest star system to the Sun after Alpha Centauri; too faint (magnitude 9.5) to see unaided.",
                "Around 10 billion years old — roughly twice the Sun's age — and only ~16% of its mass.",
                "Proper motion of 10.4 arcseconds per year, the largest of any known star."
            ],
            radiusEarths: 20,
            massEarths: 0.16 * solarMassEarths,
            temperatureK: 3195,
            colorHex: "FF7A45",
            claimYield: 20
        ),
        // Ordered outward from the star: d (2.34 d), b (3.15 d), c (4.12 d), e (6.74 d).
        bodies: [
            CelestialBody(
                id: "barnard-d", name: "Barnard d", kind: .planet, planetClass: .lava,
                blurb: "The innermost pebble: a quarter-Earth whipping round its star every 2.3 days.",
                facts: [
                    "Minimum mass ~0.26 Earths on a 2.34-day orbit — confirmed in 2025 by MAROON-X (Gemini North) and ESPRESSO.",
                    "Lies at ~0.019 AU, about 20× closer to its star than Mercury is to the Sun.",
                    "Its pull moves the star at well under half a metre per second — slower than a walking pace."
                ],
                radiusEarths: 0.68, massEarths: 0.26, temperatureK: 440, orbitDays: 2.34,
                colorHex: "D9502F", claimYield: 12, destroyYield: 45
            ),
            CelestialBody(
                id: "barnard-b", name: "Barnard b", kind: .planet, planetClass: .rocky,
                blurb: "The first world confirmed around Barnard's Star, after a century of false alarms.",
                facts: [
                    "Minimum mass ~0.37 Earths — about half of Venus — on a 3.15-day orbit.",
                    "Confirmed in 2024 with ESPRESSO on the VLT; a 1960s 'Jupiter' claim and a 2018 'super-Earth' had both evaporated.",
                    "Equilibrium temperature ~400 K: far too hot for liquid water."
                ],
                radiusEarths: 0.75, massEarths: 0.37, temperatureK: 400, orbitDays: 3.15,
                colorHex: "A07C63", claimYield: 12, destroyYield: 45
            ),
            CelestialBody(
                id: "barnard-c", name: "Barnard c", kind: .planet, planetClass: .rocky,
                blurb: "A third-of-an-Earth on a four-day year, baked for ten billion years.",
                facts: [
                    "Minimum mass ~0.34 Earths, 4.12-day orbit; confirmed 2025 alongside d and e.",
                    "Barnard b, c, d and e are all lighter than Earth — the first compact sub-Earth system found by radial velocity.",
                    "Its star is ~10 billion years old, so this world has been roasting for twice Earth's lifetime."
                ],
                radiusEarths: 0.72, massEarths: 0.34, temperatureK: 370, orbitDays: 4.12,
                colorHex: "8E7A69", claimYield: 12, destroyYield: 45
            ),
            CelestialBody(
                id: "barnard-e", name: "Barnard e", kind: .planet, planetClass: .rocky,
                blurb: "The outermost and lightest of the four — not quite twice the mass of Mars.",
                facts: [
                    "Minimum mass ~0.19 Earths on a 6.74-day orbit at ~0.038 AU.",
                    "Still too warm for liquid water (~310 K) — just inside the inner edge of the habitable zone.",
                    "The 2018 '233-day super-Earth' claim around this star was ruled out; the real planets were far smaller and closer."
                ],
                radiusEarths: 0.62, massEarths: 0.19, temperatureK: 310, orbitDays: 6.74,
                colorHex: "7F736A", claimYield: 14, destroyYield: 45
            ),
        ],
        act: 2,
        lore: "An old red ember hurrying past the Sun's neighbourhood, with four pebble worlds that took a century of false alarms to find.",
        warpCost: 35
    )

    private static let wolf359: StarSystem = StarSystem(
        id: SystemID.wolf359,
        name: "Wolf 359",
        distanceLY: 7.86,
        map: MapPoint(x: 0.41, y: 0.47),
        primary: CelestialBody(
            id: "wolf-359",
            name: "Wolf 359",
            kind: .star,
            blurb: "A faint, violently flaring M6 red dwarf — one of the smallest, dimmest stars near the Sun.",
            facts: [
                "Only ~0.1% of the Sun's luminosity; at magnitude 13.5 it is invisible without a telescope.",
                "A UV Ceti-type flare star whose brightness can more than double within minutes.",
                "Among the closest stars to the Sun — only Alpha Centauri and Barnard's Star are nearer (not counting brown dwarfs)."
            ],
            radiusEarths: 17,
            massEarths: 0.11 * solarMassEarths,
            temperatureK: 2800,
            colorHex: "FF5E3A",
            claimYield: 20
        ),
        bodies: [
            CelestialBody(
                id: "wolf-359-b", name: "Wolf 359 b", kind: .planet, planetClass: .iceGiant,
                blurb: "CANDIDATE — an unconfirmed frozen giant on an eight-year orbit around a star a thousand times dimmer than the Sun.",
                facts: [
                    "Unconfirmed 2019 radial-velocity candidate (Tuomi et al.); minimum mass ~44 Earths.",
                    "Would orbit every ~2,940 days (~8 years) at ~1.8 AU — about −230 °C in a star this dim.",
                    "A second candidate, Wolf 359 c (~3.8 Earths, 2.7-day orbit), sits deep in the flare zone."
                ],
                radiusEarths: 6.5, massEarths: 44, temperatureK: 40, orbitDays: 2938,
                colorHex: "5FB8C9", claimYield: 12, destroyYield: 55
            ),
        ],
        act: 2,
        lore: "A guttering red star that whole fictional fleets have died around; in reality, one cold giant and a great many flares.",
        warpCost: 40
    )

    private static let sirius: StarSystem = StarSystem(
        id: SystemID.sirius,
        name: "Sirius",
        distanceLY: 8.6,
        map: MapPoint(x: 0.19, y: 0.64),
        primary: CelestialBody(
            id: "sirius-a",
            name: "Sirius A",
            kind: .star,
            blurb: "The brightest star in Earth's night sky — a hot blue-white A-type twice the Sun's mass.",
            facts: [
                "Apparent magnitude −1.46; visible from nearly everywhere on Earth.",
                "About 25× more luminous than the Sun, yet only ~240 million years old.",
                "The ancient Egyptians timed the Nile flood by its dawn rising — the original 'Dog Star'."
            ],
            radiusEarths: 186,
            massEarths: 2.06 * solarMassEarths,
            temperatureK: 9940,
            colorHex: "BFD8FF",
            claimYield: 20
        ),
        bodies: [
            // A white dwarf: modelled as a star with no planet class so it can be claimed but never shattered.
            CelestialBody(
                id: "sirius-b", name: "Sirius B", kind: .star, planetClass: nil,
                blurb: "A white dwarf the size of Earth with the mass of the Sun — the dead core of a star that once outshone Sirius A.",
                facts: [
                    "The first white dwarf ever seen (Alvan Graham Clark, 1862), after Bessel predicted it from Sirius A's wobble in 1844.",
                    "Surface ~25,000 K; about one solar mass packed into an Earth-sized sphere — a teaspoon would weigh ~5 tonnes.",
                    "Orbits Sirius A every ~50 years."
                ],
                radiusEarths: 0.9, massEarths: 1.02 * solarMassEarths, temperatureK: 25_200, orbitDays: 18_300,
                colorHex: "E8F0FF", claimYield: 22, destroyYield: 40
            ),
        ],
        act: 2,
        lore: "The Dog Star and its dead white companion — a preview of what every sun eventually becomes.",
        warpCost: 45
    )

    private static let epsilonEridani: StarSystem = StarSystem(
        id: SystemID.epsilonEridani,
        name: "Epsilon Eridani",
        distanceLY: 10.5,
        map: MapPoint(x: 0.32, y: 0.76),
        primary: CelestialBody(
            id: "eps-eri",
            name: "Epsilon Eridani",
            kind: .star,
            blurb: "A young orange K-dwarf wrapped in two asteroid belts and a cold dust ring — a solar system still under construction.",
            facts: [
                "Only ~400–800 million years old, versus the Sun's 4.6 billion.",
                "Has a Kuiper-Belt-like debris disk at ~70 AU plus two inner asteroid belts.",
                "The third-closest star system visible to the naked eye, after Alpha Centauri and Sirius."
            ],
            radiusEarths: 81,
            massEarths: 0.82 * solarMassEarths,
            temperatureK: 5084,
            colorHex: "FFB870",
            claimYield: 20
        ),
        bodies: [
            CelestialBody(
                id: "eps-eri-b", name: "Epsilon Eridani b", kind: .planet, planetClass: .gasGiant,
                blurb: "Ægir: a cold Jupiter on a seven-year orbit around one of the nearest young stars.",
                facts: [
                    "A Jupiter-class world (~0.7–0.8 Jupiter masses) orbiting every ~7.4 years at about 3.5 AU.",
                    "Announced in 2000 but disputed for years because the young star is so active; combined radial-velocity and imaging work by 2019 pinned it down.",
                    "Officially named Ægir, after a Norse sea giant, in the IAU's 2015 NameExoWorlds vote."
                ],
                radiusEarths: 11.5, massEarths: 240, temperatureK: 115, orbitDays: 2690,
                colorHex: "C9975F", claimYield: 15, destroyYield: 70
            ),
        ],
        act: 2,
        lore: "A newborn system still shedding dust — planets are being made here right now, one collision at a time.",
        warpCost: 50
    )

    private static let tauCeti: StarSystem = StarSystem(
        id: SystemID.tauCeti,
        name: "Tau Ceti",
        distanceLY: 11.9,
        map: MapPoint(x: 0.14, y: 0.52),
        primary: CelestialBody(
            id: "tau-ceti",
            name: "Tau Ceti",
            kind: .star,
            blurb: "A quiet, metal-poor Sun-analogue — the closest single G-type star to home, and a science-fiction favourite.",
            facts: [
                "The nearest solitary G-class star to the Sun; visible to the naked eye at magnitude 3.5.",
                "Surrounded by ~10× more debris than the Solar System — its planets get pelted with comets.",
                "Metal-poor: only ~28% of the Sun's abundance of elements heavier than helium."
            ],
            radiusEarths: 86,
            massEarths: 0.78 * solarMassEarths,
            temperatureK: 5344,
            colorHex: "FFD98A",
            claimYield: 20
        ),
        bodies: [
            CelestialBody(
                id: "tau-ceti-e", name: "Tau Ceti e", kind: .planet, planetClass: .superEarth,
                blurb: "A four-Earth-mass world on the hot inner edge of the habitable zone — more Venus than Earth, probably.",
                facts: [
                    "Minimum mass ~3.9 Earths; orbits every ~163 days at 0.54 AU.",
                    "Receives ~1.8× the sunlight Earth does — likely a runaway greenhouse unless it is nearly airless.",
                    "Detected in 2012 (Tuomi et al.) and confirmed in 2017 with ultra-precise radial velocities."
                ],
                radiusEarths: 1.6, massEarths: 3.9, temperatureK: 320, orbitDays: 162.9,
                colorHex: "B39A75", claimYield: 20, destroyYield: 65
            ),
            CelestialBody(
                id: "tau-ceti-f", name: "Tau Ceti f", kind: .planet, planetClass: .superEarth,
                blurb: "A cold super-Earth at the far edge of the habitable zone, a Mars-like distance from a dimmer sun.",
                facts: [
                    "Minimum mass ~3.9 Earths on a ~636-day orbit at 1.33 AU — the outer fringe of the habitable zone.",
                    "Receives only ~29% of Earth's sunlight; it would need a thick greenhouse atmosphere to stay wet.",
                    "Its star was one of two targets of Project Ozma, the first SETI search, in 1960."
                ],
                radiusEarths: 1.6, massEarths: 3.9, temperatureK: 204, orbitDays: 636,
                colorHex: "8FA3B8", claimYield: 20, destroyYield: 65
            ),
        ],
        act: 2,
        lore: "The star every twentieth-century writer sent their colonists to; two heavy worlds wait there in a hail of comets.",
        warpCost: 55
    )

    private static let trappist1: StarSystem = StarSystem(
        id: SystemID.trappist1,
        name: "TRAPPIST-1",
        distanceLY: 40.7,
        map: MapPoint(x: 0.54, y: 0.31),
        primary: CelestialBody(
            id: "trappist-1",
            name: "TRAPPIST-1",
            kind: .star,
            blurb: "An ultracool red dwarf barely bigger than Jupiter, herding seven Earth-sized worlds in orbits tighter than Mercury's.",
            facts: [
                "Mass ~9% of the Sun's, radius ~12% — only slightly larger than Jupiter.",
                "All seven planets would fit inside Mercury's orbit; the outermost takes just 18.8 days.",
                "About 7.6 billion years old, and will keep burning for trillions of years more."
            ],
            radiusEarths: 13,
            massEarths: 0.0898 * solarMassEarths,
            temperatureK: 2566,
            colorHex: "FF5A3C",
            claimYield: 20
        ),
        // Masses, radii and periods from Agol et al. (2021).
        bodies: [
            CelestialBody(
                id: "trappist-1b", name: "TRAPPIST-1 b", kind: .planet, planetClass: .lava,
                blurb: "The innermost world: a bare, roasting rock with a year 36 hours long.",
                facts: [
                    "~1.37 Earth masses, ~1.12 Earth radii, 1.51-day orbit.",
                    "JWST measured its dayside at ~500 K (230 °C) in 2023 — no thick atmosphere to spread the heat.",
                    "Receives about 4× the starlight Earth does."
                ],
                radiusEarths: 1.116, massEarths: 1.374, temperatureK: 400, orbitDays: 1.511,
                colorHex: "D8502E", claimYield: 12, destroyYield: 50
            ),
            CelestialBody(
                id: "trappist-1c", name: "TRAPPIST-1 c", kind: .planet, planetClass: .rocky,
                blurb: "A dense Venus-sized rock that turned out not to be a Venus.",
                facts: [
                    "~1.31 Earth masses, ~1.10 Earth radii, 2.42-day orbit — the densest of the seven.",
                    "JWST (2023) found at most a thin atmosphere — no thick Venus-like CO₂ blanket.",
                    "Receives about 2.2× Earth's sunlight."
                ],
                radiusEarths: 1.097, massEarths: 1.308, temperatureK: 342, orbitDays: 2.422,
                colorHex: "B57A5A", claimYield: 12, destroyYield: 50
            ),
            CelestialBody(
                id: "trappist-1d", name: "TRAPPIST-1 d", kind: .planet, planetClass: .desert,
                blurb: "A small, light world on the hot edge of the habitable zone — possibly rich in volatiles.",
                facts: [
                    "~0.39 Earth masses, ~0.79 Earth radii, 4.05-day orbit.",
                    "Receives ~1.1× Earth's sunlight, right at the inner edge of the habitable zone.",
                    "Its low density hints at a volatile-rich composition — a thick atmosphere or a lot of water."
                ],
                radiusEarths: 0.788, massEarths: 0.388, temperatureK: 288, orbitDays: 4.050,
                colorHex: "C9A46A", claimYield: 15, destroyYield: 55
            ),
            CelestialBody(
                id: "trappist-1e", name: "TRAPPIST-1 e", kind: .planet, planetClass: .ocean,
                blurb: "The most Earth-like of the seven: rocky, temperate, and possibly wet.",
                facts: [
                    "~0.69 Earth masses, ~0.92 Earth radii, 6.1-day orbit.",
                    "Receives ~66% of Earth's sunlight; could hold liquid water with a modest atmosphere.",
                    "A density close to Earth's implies a rocky world with an iron core."
                ],
                radiusEarths: 0.920, massEarths: 0.692, temperatureK: 251, orbitDays: 6.100,
                colorHex: "2E5FB8", claimYield: 25, destroyYield: 80, habitable: true
            ),
            CelestialBody(
                id: "trappist-1f", name: "TRAPPIST-1 f", kind: .planet, planetClass: .ocean,
                blurb: "An Earth-mass world in the cool half of the habitable zone — maybe an ocean under a lid of ice.",
                facts: [
                    "~1.04 Earth masses, ~1.05 Earth radii, 9.2-day orbit; receives ~38% of Earth's sunlight.",
                    "Its density suggests a large water fraction — possibly a global ocean beneath ice.",
                    "Almost certainly tidally locked, with a permanent twilight ring between day and night."
                ],
                radiusEarths: 1.045, massEarths: 1.039, temperatureK: 219, orbitDays: 9.207,
                colorHex: "4A7FC2", claimYield: 22, destroyYield: 75, habitable: true
            ),
            CelestialBody(
                id: "trappist-1g", name: "TRAPPIST-1 g", kind: .planet, planetClass: .ice,
                blurb: "The largest of the seven — a frozen super-Earth-lite unless a greenhouse keeps it warm.",
                facts: [
                    "~1.32 Earth masses, ~1.13 Earth radii, 12.35-day orbit — the biggest planet in the system.",
                    "Receives ~26% of Earth's sunlight, similar to Mars.",
                    "Part of a resonant chain: g completes 3 orbits for every 4 of f, and 3 for every 2 of h."
                ],
                radiusEarths: 1.129, massEarths: 1.321, temperatureK: 199, orbitDays: 12.353,
                colorHex: "9FCBE8", claimYield: 22, destroyYield: 75, habitable: true
            ),
            CelestialBody(
                id: "trappist-1h", name: "TRAPPIST-1 h", kind: .planet, planetClass: .ice,
                blurb: "The outermost and smallest: a Mars-sized ice ball on a 19-day year.",
                facts: [
                    "~0.33 Earth masses, ~0.76 Earth radii, 18.8-day orbit.",
                    "Receives only ~14% of Earth's sunlight; equilibrium temperature around −100 °C.",
                    "Its orbit was pinned down in 2017 using Kepler data and the system's resonance pattern before it was fully observed."
                ],
                radiusEarths: 0.755, massEarths: 0.326, temperatureK: 173, orbitDays: 18.773,
                colorHex: "C8E4F2", claimYield: 12, destroyYield: 50
            ),
        ],
        act: 2,
        lore: "Seven worlds packed so tightly that each hangs in the others' skies like a moon — the best place we know to look for a second Earth.",
        warpCost: 80
    )

    // MARK: - Act III · The core

    private static let sagittariusA: StarSystem = StarSystem(
        id: SystemID.sagittariusA,
        name: "Sagittarius A*",
        distanceLY: 26_670,
        map: MapPoint(x: 0.78, y: 0.40),
        primary: CelestialBody(
            id: BodyID.sagittariusAStar,
            name: "Sagittarius A*",
            kind: .blackHole,
            blurb: "The supermassive black hole at the centre of the Milky Way — four million Suns folded behind a horizon that would fit inside Mercury's orbit.",
            facts: [
                "Mass ~4.3 million Suns, measured from stars whirling around it at up to ~8,000 km/s.",
                "Imaged by the Event Horizon Telescope in May 2022: a ring ~52 microarcseconds across — a doughnut on the Moon, seen from Earth.",
                "The 2020 Nobel Prize in Physics went to Genzel and Ghez for proving it is there."
            ],
            radiusEarths: 1.9,
            massEarths: 4.3e6 * solarMassEarths,
            colorHex: "000000",
            claimYield: 30
        ),
        bodies: [],
        act: 3,
        lore: "Everything in the galaxy falls toward this. Fold hard enough and you can fall past it.",
        warpCost: 150
    )

    private static let andromeda: StarSystem = StarSystem(
        id: SystemID.andromeda,
        name: "Andromeda",
        distanceLY: 2_537_000,
        map: MapPoint(x: 0.96, y: 0.08),
        primary: CelestialBody(
            id: BodyID.andromedaGalaxy,
            name: "Andromeda Galaxy",
            kind: .galaxy,
            blurb: "M31: a trillion-star spiral 2.5 million light-years away — the farthest thing most people will ever see with their own eyes.",
            facts: [
                "About 2.5 million light-years away; the light reaching Earth tonight left when Homo habilis walked Africa.",
                "On a collision course with the Milky Way — the merger begins in roughly 4.5 billion years.",
                "Edwin Hubble's 1920s measurements of Cepheid variables in M31 proved it was a separate galaxy, not a nebula."
            ],
            radiusEarths: 400,
            colorHex: "9BB7FF",
            claimYield: 50
        ),
        bodies: [],
        act: 3,
        lore: "Two and a half million years of light, folded into seven seconds. Nobody back home will ever hear you did it.",
        warpCost: 0
    )
}

extension UniverseData {
    /// Convenience lookup by system id (see `SystemID`).
    static func system(_ id: String) -> StarSystem? {
        universe.system(id)
    }
}
