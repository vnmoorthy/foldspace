import SceneKit
import UIKit
import CoreGraphics

/// Procedural SceneKit materials for every `CelestialBody`.
///
/// Nothing here comes from an asset catalog: textures are synthesised at runtime with tileable
/// value-noise / fBm and a little CoreGraphics on top (craters, storms, sunspots), then cached per
/// body id (+ size). The cache is lock-protected so `SpaceScene` can pre-warm the rest of a star
/// system on a background queue while the current planet is already on screen.
enum PlanetMaterials {

    /// Default equirectangular texture size (square; SCNSphere UVs wrap u around the equator).
    static let defaultSize = 512

    // MARK: - Public API

    /// A ready-to-use material for `body`. Stars are emissive/unlit, planets are PBR with a
    /// procedural albedo (lava worlds also get an emissive crack map), black holes are pure black
    /// and galaxies are an additive spiral sprite.
    static func material(for body: CelestialBody) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = body.id
        switch body.kind {
        case .star:
            let tex = texture(for: body)
            m.lightingModel = .constant
            m.diffuse.contents = tex
            m.emission.contents = tex
            m.emission.intensity = 0.55
        case .blackHole:
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.black
            m.emission.contents = UIColor.black
            m.specular.contents = UIColor.black
        case .galaxy:
            m.lightingModel = .constant
            m.diffuse.contents = galaxyTexture()
            m.blendMode = .additive
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
        case .planet, .dwarfPlanet:
            let cls = body.planetClass ?? .rocky
            m.lightingModel = .physicallyBased
            m.diffuse.contents = texture(for: body)
            m.metalness.contents = NSNumber(value: 0.0)
            m.roughness.contents = NSNumber(value: roughness(for: cls))
            if cls == .lava {
                m.emission.contents = lavaEmissionTexture(for: body)
                m.emission.intensity = 1.0
            }
        }
        configureSampling(m.diffuse)
        configureSampling(m.emission)
        return m
    }

    /// Flat-colour stand-in used by `SpaceScene` for the ~1 s a texture takes to synthesise the first
    /// time a body is shown (debug builds on the simulator are slow at per-pixel Swift).
    static func placeholderMaterial(for body: CelestialBody) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = body.id + "#placeholder"
        switch body.kind {
        case .star:
            m.lightingModel = .constant
            m.diffuse.contents = baseColor(for: body)
            m.emission.contents = baseColor(for: body)
            m.emission.intensity = 0.5
        case .blackHole:
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.black
        case .galaxy:
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.clear
        case .planet, .dwarfPlanet:
            m.lightingModel = .physicallyBased
            m.diffuse.contents = baseColor(for: body)
            m.metalness.contents = NSNumber(value: 0.0)
            m.roughness.contents = NSNumber(value: 0.9)
        }
        return m
    }

    /// The procedural surface texture for `body` (generated on first use, then cached).
    /// Safe to call from any thread.
    static func texture(for body: CelestialBody, size: Int = defaultSize) -> UIImage {
        let key = "\(body.id)#\(size)"
        if let hit = cache.get(key) { return hit }
        // Prefer a Blender-rendered equirect texture from the bundle when one exists
        // (assets/textures/planet-<id>.png, sun-photosphere.png — see docs/BLENDER-CODEX-BRIEF.md).
        if let bundled = bundledTexture(for: body) {
            cache.set(key, bundled)
            return bundled
        }
        let img = render(body, size: max(32, size))
        cache.set(key, img)
        return img
    }

    /// A hand/Blender-made texture shipped in the app bundle, if any. Names follow the asset contract:
    /// `planet-<bodyid>.png` for planets and `sun-photosphere.png` for the Sun.
    static func bundledTexture(for body: CelestialBody) -> UIImage? {
        let name = body.id == BodyID.sun ? "sun-photosphere" : "planet-\(body.id)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    /// Cache lookup that never renders. `SpaceScene` uses it to decide whether to show a placeholder.
    static func cachedTexture(for body: CelestialBody, size: Int = defaultSize) -> UIImage? {
        cache.get("\(body.id)#\(size)")
    }

    /// Generate (and cache) textures for `bodies` on a utility queue, skipping anything already cached.
    static func prewarm(_ bodies: [CelestialBody], size: Int = defaultSize) {
        let pending = bodies.filter { cache.get("\($0.id)#\(size)") == nil }
        guard !pending.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for b in pending {
                _ = texture(for: b, size: size)
                if (b.planetClass ?? .rocky) == .lava { _ = lavaEmissionTexture(for: b, size: size) }
            }
        }
    }

    /// Base colour parsed from `body.colorHex`.
    static func baseColor(for body: CelestialBody) -> UIColor {
        RGB(hex: body.colorHex).uiColor
    }

    // MARK: Extra procedural sprites used by SpaceScene

    /// Soft radial glow (premultiplied RGBA), transparent at the edge.
    static func haloTexture(color: UIColor, size: Int = 256, falloff: Float = 2.4) -> UIImage {
        let c = RGB(color)
        let key = "halo#\(c.hexString)#\(size)#\(falloff)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: size, height: size, alpha: true) else { return UIImage() }
        let half = Float(size) * 0.5
        for y in 0..<size {
            let dy = (Float(y) + 0.5 - half) / half
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                let a = powf(max(0, 1 - r), falloff)
                cv.set(x, y, c.mix(.white, a * 0.35), alpha: a)
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    /// Transparent 2:1 sky with ~1600 stars of varying size, brightness and tint. Wrapped on an
    /// inverted sphere this is the whole starfield in a single draw call.
    static func starfieldTexture(width: Int = 1024, height: Int = 512) -> UIImage {
        let key = "starfield#\(width)x\(height)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: width, height: height, alpha: true) else { return UIImage() }
        let ctx = cv.ctx
        var rng = SeededRNG(seed: 0x5EED_5747)
        let w = CGFloat(width), h = CGFloat(height)
        // Faint dust band along a tilted great circle (the Milky Way), drawn as soft blobs.
        for _ in 0..<140 {
            let t = CGFloat.random(in: 0..<1, using: &rng)
            let cx = t * w
            let cy = h * 0.5 + sin(t * .pi * 2) * h * 0.18 + CGFloat.random(in: -h * 0.07...h * 0.07, using: &rng)
            let r = CGFloat.random(in: 18...46, using: &rng)
            let colors = [UIColor(red: 0.55, green: 0.65, blue: 0.9, alpha: 0.05).cgColor,
                          UIColor(red: 0.55, green: 0.65, blue: 0.9, alpha: 0.0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
            }
        }
        for i in 0..<1600 {
            let x = CGFloat.random(in: 0..<w, using: &rng)
            // fewer stars right at the poles (they bunch up on the sphere)
            let y = CGFloat.random(in: 0..<h, using: &rng)
            let pole = abs(y / h - 0.5) * 2
            if pole > 0.9, Float.random(in: 0..<1, using: &rng) < 0.6 { continue }
            let mag = Float.random(in: 0..<1, using: &rng)
            let radius = CGFloat(0.55 + powf(mag, 3.2) * 1.9)
            let alpha = CGFloat(0.35 + mag * 0.65)
            let tint = Float.random(in: 0..<1, using: &rng)
            let color: UIColor
            if tint < 0.10 { color = UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: alpha) }
            else if tint < 0.18 { color = UIColor(red: 1.0, green: 0.82, blue: 0.62, alpha: alpha) }
            else { color = UIColor(white: 1.0, alpha: alpha) }
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            if i % 55 == 0 {
                // a handful of bright stars get a soft glow
                let gr = radius * 6
                let colors = [color.withAlphaComponent(0.35).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                           endCenter: CGPoint(x: x, y: y), endRadius: gr, options: [])
                }
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    /// Bodies that get a ring plane in the scene.
    static func hasRings(_ body: CelestialBody) -> Bool {
        body.id == "saturn" || body.id == "uranus"
    }

    /// Ring system as a square RGBA sprite for an `SCNPlane`. Normalised radius 1 = half the plane.
    /// Inner edge at 0.5, outer at 0.96 → plane width = 4.8 × planet radius puts the inner edge
    /// at 1.2 planet radii (Saturn-like).
    static func ringTexture(for body: CelestialBody, size: Int = 512) -> UIImage {
        let key = "rings#\(body.id)#\(size)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: size, height: size, alpha: true) else { return UIImage() }
        let seed = bodySeed(for: body) &+ 977
        let base = RGB(hex: body.colorHex)
        let faint: Float = body.id == "uranus" ? 0.28 : 1.0
        let inner: Float = 0.50, outer: Float = 0.96
        let half = Float(size) * 0.5
        for y in 0..<size {
            let dy = (Float(y) + 0.5 - half) / half
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                if r < inner || r > outer { cv.set(x, y, .black, alpha: 0); continue }
                let t = (r - inner) / (outer - inner)
                let band = Noise.fbm(u: t, v: 0.37, frequencyU: 24, frequencyV: 1, octaves: 3, seed: seed)
                var a = (0.3 + 0.7 * band) * smoothstep(inner, inner + 0.02, r) * (1 - smoothstep(outer - 0.03, outer, r))
                // Cassini-like division and a thin outer gap
                a *= 1 - 0.88 * smoothstep(0.79, 0.805, r) * (1 - smoothstep(0.83, 0.845, r))
                a *= 1 - 0.6 * smoothstep(0.915, 0.92, r) * (1 - smoothstep(0.928, 0.933, r))
                a *= faint
                let c = base.mix(.white, 0.3 + 0.35 * band)
                cv.set(x, y, c, alpha: a)
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    /// Accretion disc sprite: white-hot inner edge → orange → deep red, with streaky turbulence and
    /// Doppler beaming (one side brighter). Transparent hole in the middle for the shadow sphere.
    static func accretionDiskTexture(size: Int = 512) -> UIImage {
        let key = "accretion#\(size)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: size, height: size, alpha: true) else { return UIImage() }
        let inner: Float = 0.30, outer: Float = 0.98
        let half = Float(size) * 0.5
        let hot = RGB(1.0, 0.96, 0.85), orange = RGB(1.0, 0.55, 0.15), red = RGB(0.8, 0.14, 0.04), ember = RGB(0.22, 0.03, 0.0)
        for y in 0..<size {
            let dy = (Float(y) + 0.5 - half) / half
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                if r < inner - 0.03 || r > outer { cv.set(x, y, .black, alpha: 0); continue }
                let theta = atan2f(dy, dx)
                let u = theta / (2 * Float.pi) + 0.5          // tileable around the ring
                let t = max(0, (r - inner) / (outer - inner))
                let streak = Noise.fbm(u: u + t * 0.35, v: t * 3.0, frequencyU: 10, frequencyV: 3, octaves: 3, seed: 4242)
                var intensity = smoothstep(inner - 0.03, inner + 0.04, r) * powf(1 - t, 1.7)
                intensity *= 0.55 + 0.75 * streak
                intensity *= 1 + 0.45 * cosf(theta)           // beaming
                var c: RGB
                if t < 0.22 { c = hot.mix(orange, t / 0.22) }
                else if t < 0.6 { c = orange.mix(red, (t - 0.22) / 0.38) }
                else { c = red.mix(ember, (t - 0.6) / 0.4) }
                c = c.mix(.white, smoothstep(0.0, 0.05, t) * (1 - smoothstep(0.05, 0.12, t)) * 0.4)
                cv.set(x, y, c.scaled(min(1.6, intensity * 1.5)), alpha: min(1, intensity * 1.6))
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    /// Two-armed logarithmic spiral galaxy sprite (Andromeda finale). Warm bulge, blue arms,
    /// dust lanes, star specks. Premultiplied RGBA, designed for additive blending.
    static func galaxyTexture(size: Int = 512) -> UIImage {
        let key = "galaxy#\(size)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: size, height: size, alpha: true) else { return UIImage() }
        let half = Float(size) * 0.5
        let bulgeC = RGB(1.0, 0.9, 0.74), armC = RGB(0.66, 0.78, 1.0), pinkC = RGB(0.95, 0.65, 0.8)
        for y in 0..<size {
            let dy = (Float(y) + 0.5 - half) / half
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                if r > 1 { cv.set(x, y, .black, alpha: 0); continue }
                let theta = atan2f(dy, dx)
                let u = theta / (2 * Float.pi) + 0.5
                let phase = theta - 3.1 * logf(r + 0.07)
                let arm = powf(0.5 + 0.5 * cosf(2 * phase), 3.2)
                let dust = powf(0.5 + 0.5 * cosf(2 * phase + 0.95), 7) * expf(-r * 2.4) * 0.5
                let n = Noise.fbm(u: u, v: r * 3.5, frequencyU: 6, frequencyV: 4, octaves: 4, seed: 31337)
                let bulge = expf(-(r * r) / (0.11 * 0.11)) * 1.5 + expf(-r * 9) * 0.6
                var armB = arm * expf(-r * 2.7) * (0.45 + 0.9 * n) * smoothstep(0.02, 0.14, r)
                armB += expf(-r * 3.2) * 0.12 * n
                armB *= 1 - dust
                var b = bulge + armB
                b *= 1 - smoothstep(0.82, 1.0, r)
                let w = min(1, bulge / max(0.001, b))
                var c = armC.mix(bulgeC, w)
                // HII-region pink specks on the arms
                let speck = Noise.hash(Int32(x), Int32(y), 99)
                if speck > 0.996, armB > 0.08 { c = pinkC; b += 0.5 }
                else if speck > 0.9985 { c = .white; b += 0.7 }
                cv.set(x, y, c.scaled(min(1.4, b)), alpha: min(1, b))
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    // MARK: - Internals

    private static let cache = TextureCache()

    private static func roughness(for cls: PlanetClass) -> Double {
        switch cls {
        case .ocean: return 0.42
        case .earthlike: return 0.58
        case .ice: return 0.55
        case .gasGiant: return 0.78
        case .iceGiant: return 0.7
        case .superEarth: return 0.85
        case .rocky, .lava, .desert: return 0.95
        }
    }

    private static func configureSampling(_ p: SCNMaterialProperty) {
        p.wrapS = .repeat
        p.wrapT = .clamp
        p.mipFilter = .linear
        p.magnificationFilter = .linear
        p.minificationFilter = .linear
    }

    /// Deterministic per-body seed (djb2 over the id — never `hashValue`, which is per-process).
    private static func bodySeed(for body: CelestialBody) -> UInt32 {
        var h: UInt32 = 5381
        for b in body.id.utf8 { h = (h &* 33) &+ UInt32(b) }
        return h
    }

    private static func render(_ body: CelestialBody, size: Int) -> UIImage {
        switch body.kind {
        case .star: return renderStar(body, size: size)
        case .blackHole: return solid(.black, size: 4)
        case .galaxy: return galaxyTexture(size: size)
        case .planet, .dwarfPlanet: return renderPlanet(body, cls: body.planetClass ?? .rocky, size: size)
        }
    }

    private static func solid(_ c: RGB, size: Int) -> UIImage {
        guard let cv = Canvas(width: size, height: size, alpha: false) else { return UIImage() }
        for y in 0..<size { for x in 0..<size { cv.set(x, y, c) } }
        return cv.makeImage()
    }

    // MARK: Planets

    private static func renderPlanet(_ body: CelestialBody, cls: PlanetClass, size: Int) -> UIImage {
        guard let cv = Canvas(width: size, height: size, alpha: false) else { return UIImage() }
        let seed = bodySeed(for: body)
        let base = RGB(hex: body.colorHex)
        let dark = base.scaled(0.42)
        let light = base.mix(.white, 0.38)
        let tempK = Float(body.temperatureK ?? 280)
        let hasCaps = tempK < 245 || cls == .earthlike || cls == .ice
        let snow = RGB(0.93, 0.95, 0.98)
        let inv = 1 / Float(size)

        for y in 0..<size {
            let v = (Float(y) + 0.5) * inv
            let lat = abs(1 - 2 * v)          // 0 at the equator, 1 at the poles
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inv
                var c: RGB
                switch cls {
                case .rocky:
                    let n = Noise.fbm(u: u, v: v, frequency: 6, octaves: 5, seed: seed)
                    let m = Noise.fbm(u: u, v: v, frequency: 18, octaves: 3, seed: seed &+ 7)
                    c = dark.mix(light, n).scaled(0.8 + 0.4 * m)
                    if hasCaps {
                        let cap = smoothstep(0.80 + (m - 0.5) * 0.08, 0.90, lat)
                        c = c.mix(snow, cap)
                    }

                case .lava:
                    let n = Noise.fbm(u: u, v: v, frequency: 6, octaves: 5, seed: seed)
                    let crack = lavaCrack(u: u, v: v, seed: seed)
                    let basalt = RGB(0.12, 0.08, 0.07).mix(base.scaled(0.4), 0.35)
                    let hot = RGB(1.0, 0.45, 0.06).mix(RGB(1.0, 0.92, 0.5), crack * crack)
                    c = basalt.scaled(0.6 + 0.6 * n).mix(hot, crack * 0.95)

                case .desert:
                    let n = Noise.fbm(u: u, v: v, frequency: 5, octaves: 5, seed: seed)
                    let d = Noise.fbm(u: u, v: v, frequency: 12, octaves: 3, seed: seed &+ 11)
                    let m = Noise.fbm(u: u, v: v, frequency: 3, octaves: 3, seed: seed &+ 19)
                    let band = 0.5 + 0.5 * sinf((v * 9 + n * 1.2) * 2 * Float.pi)
                    c = dark.mix(light, 0.3 + 0.45 * n + 0.2 * band).scaled(0.85 + 0.3 * d)
                    c = c.mix(dark, smoothstep(0.34, 0.22, m) * 0.7)

                case .ice:
                    let n = Noise.fbm(u: u, v: v, frequency: 6, octaves: 5, seed: seed)
                    let r = Noise.ridged(u: u, v: v, frequency: 8, octaves: 4, seed: seed &+ 5)
                    c = base.mix(.white, 0.45 + 0.35 * n)
                    let crack = smoothstep(0.86, 0.98, r)
                    c = c.mix(base.scaled(0.6), crack * 0.7)

                case .ocean:
                    let n = Noise.fbm(u: u, v: v, frequency: 12, octaves: 4, seed: seed)
                    let land = Noise.fbm(u: u, v: v, frequency: 4, octaves: 5, seed: seed &+ 9)
                    let deep = base.scaled(0.5)
                    c = deep.mix(base, 0.35 + 0.5 * n)
                    if land > 0.62 {
                        let shallow = smoothstep(0.62, 0.68, land) * 0.6
                        c = c.mix(base.mix(.white, 0.3), shallow)
                        let t = smoothstep(0.68, 0.74, land)
                        let sand = RGB(0.78, 0.7, 0.5), veg = RGB(0.25, 0.45, 0.25)
                        c = c.mix(sand.mix(veg, smoothstep(0.72, 0.8, land)), t)
                    }
                    if hasCaps { c = c.mix(snow, smoothstep(0.86, 0.93, lat)) }

                case .superEarth:
                    let n = Noise.fbm(u: u, v: v, frequency: 5, octaves: 5, seed: seed)
                    let m = Noise.fbm(u: u, v: v, frequency: 16, octaves: 3, seed: seed &+ 2)
                    let h = Noise.fbm(u: u, v: v, frequency: 3, octaves: 3, seed: seed &+ 21)
                    let sea = base.scaled(0.45).mix(RGB(0.1, 0.2, 0.4), 0.5)
                    if n > 0.52 {
                        let land = dark.mix(light, m).mix(base, 0.3)
                        c = sea.mix(land, smoothstep(0.52, 0.56, n))
                    } else {
                        c = sea.mix(sea.scaled(1.3), n * 1.5)
                    }
                    c = c.mix(.white, 0.12 * smoothstep(0.55, 0.8, h) + 0.08 * lat)
                    if hasCaps { c = c.mix(snow, smoothstep(0.84, 0.92, lat)) }

                case .earthlike:
                    let cont = Noise.fbm(u: u, v: v, frequency: 4, octaves: 6, seed: seed)
                    let detail = Noise.fbm(u: u, v: v, frequency: 24, octaves: 3, seed: seed &+ 4)
                    let ocean = RGB(0.03, 0.16, 0.42).mix(base, 0.25)
                    if cont > 0.55 {
                        let t = smoothstep(0.55, 0.585, cont)
                        let alt = smoothstep(0.6, 0.85, cont)
                        let green = RGB(0.16, 0.38, 0.14), brown = RGB(0.44, 0.35, 0.2)
                        var landc = green.mix(brown, alt * 0.8 + detail * 0.2)
                        landc = landc.mix(snow, smoothstep(0.75, 0.95, alt + lat * 0.35))
                        landc = landc.scaled(0.85 + 0.3 * detail)
                        c = ocean.mix(landc, t)
                    } else {
                        c = ocean.mix(ocean.mix(.white, 0.25), smoothstep(0.5, 0.55, cont) * 0.5)
                        c = c.scaled(0.9 + 0.2 * detail)
                    }
                    let cap = smoothstep(0.84 + (cont - 0.5) * 0.1, 0.92, lat)
                    c = c.mix(snow, cap)
                    let cl = Noise.fbm(u: u, v: v, frequency: 7, octaves: 4, seed: seed &+ 33)
                    c = c.mix(.white, smoothstep(0.60, 0.78, cl) * 0.85)

                case .gasGiant:
                    let turb = Noise.fbm(u: u, v: v, frequency: 3, octaves: 4, seed: seed)
                    let streak = Noise.fbm(u: u, v: v, frequencyU: 3, frequencyV: 40, octaves: 3, seed: seed &+ 8)
                    let bandY = v * 11 + (turb - 0.5) * 0.9
                    let band = 0.5 + 0.5 * sinf(bandY * 2 * Float.pi)
                    let band2 = 0.5 + 0.5 * sinf(bandY * 2 * Float.pi * 2.7 + 1.3)
                    let t = band * 0.55 + band2 * 0.2 + streak * 0.35
                    c = dark.mix(light, t).mix(base, 0.25)

                case .iceGiant:
                    let n = Noise.fbm(u: u, v: v, frequency: 3, octaves: 4, seed: seed)
                    let s = Noise.fbm(u: u, v: v, frequencyU: 4, frequencyV: 24, octaves: 3, seed: seed &+ 8)
                    c = base.mix(light, 0.25 * n + 0.08 * sinf(v * 18 * 2 * Float.pi))
                    c = c.mix(.white, smoothstep(0.72, 0.9, s) * 0.35)
                }
                cv.set(x, y, c)
            }
        }

        // CoreGraphics overlays
        var rng = SeededRNG(seed: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15)
        switch cls {
        case .rocky, .desert:
            drawCraters(cv, count: cls == .rocky ? 26 : 9, base: base, rng: &rng)
        case .ice:
            drawCraters(cv, count: 7, base: base.mix(.white, 0.4), rng: &rng)
        case .gasGiant:
            drawStorm(cv, body: body, base: base, rng: &rng)
        default:
            break
        }
        return cv.makeImage()
    }

    /// Ridged-noise crack field shared by the lava albedo and its emission map.
    @inline(__always)
    private static func lavaCrack(u: Float, v: Float, seed: UInt32) -> Float {
        let r = Noise.ridged(u: u, v: v, frequency: 5, octaves: 4, seed: seed &+ 3)
        return smoothstep(0.80, 0.97, r)
    }

    private static func lavaEmissionTexture(for body: CelestialBody, size: Int = defaultSize) -> UIImage {
        let key = "\(body.id)#emission#\(size)"
        if let hit = cache.get(key) { return hit }
        guard let cv = Canvas(width: size, height: size, alpha: false) else { return UIImage() }
        let seed = bodySeed(for: body)
        let inv = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inv
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inv
                let crack = lavaCrack(u: u, v: v, seed: seed)
                let hot = RGB(1.0, 0.35, 0.03).mix(RGB(1.0, 0.85, 0.4), crack * crack)
                cv.set(x, y, RGB.black.mix(hot, crack))
            }
        }
        let img = cv.makeImage()
        cache.set(key, img)
        return img
    }

    private static func drawCraters(_ cv: Canvas, count: Int, base: RGB, rng: inout SeededRNG) {
        let ctx = cv.ctx
        let s = CGFloat(cv.width)
        for _ in 0..<count {
            let r = s * CGFloat(Float.random(in: 0.008...0.045, using: &rng))
            let cx = CGFloat(Float.random(in: 0..<1, using: &rng)) * s
            let cy = s * CGFloat(0.12 + Float.random(in: 0..<1, using: &rng) * 0.76)
            let floorC = base.scaled(0.55).uiColor.withAlphaComponent(0.55)
            let rimC = base.mix(.white, 0.35).uiColor.withAlphaComponent(0.35)
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            ctx.setFillColor(floorC.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(rimC.cgColor)
            ctx.setLineWidth(max(1, r * 0.22))
            ctx.strokeEllipse(in: rect.insetBy(dx: -r * 0.08, dy: -r * 0.08))
        }
    }

    private static func drawStorm(_ cv: Canvas, body: CelestialBody, base: RGB, rng: inout SeededRNG) {
        let ctx = cv.ctx
        let s = CGFloat(cv.width)
        let isJupiter = body.id == "jupiter"
        let cx = s * (isJupiter ? 0.62 : CGFloat(Float.random(in: 0.2...0.8, using: &rng)))
        let cy = s * (isJupiter ? 0.62 : CGFloat(Float.random(in: 0.3...0.7, using: &rng)))
        let w = s * (isJupiter ? 0.11 : 0.07), h = s * (isJupiter ? 0.055 : 0.035)
        let outer = (isJupiter ? RGB(0.75, 0.33, 0.22) : base.mix(.white, 0.45)).uiColor
        let inner = (isJupiter ? RGB(0.9, 0.5, 0.35) : base.mix(.white, 0.7)).uiColor
        ctx.setFillColor(outer.withAlphaComponent(0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - w, y: cy - h, width: w * 2, height: h * 2))
        ctx.setFillColor(inner.withAlphaComponent(0.7).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - w * 0.6, y: cy - h * 0.55, width: w * 1.2, height: h * 1.1))
        ctx.setStrokeColor(base.scaled(0.6).uiColor.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(max(1, s * 0.004))
        ctx.strokeEllipse(in: CGRect(x: cx - w * 1.08, y: cy - h * 1.15, width: w * 2.16, height: h * 2.3))
    }

    // MARK: Stars

    private static func renderStar(_ body: CelestialBody, size: Int) -> UIImage {
        guard let cv = Canvas(width: size, height: size, alpha: false) else { return UIImage() }
        let seed = bodySeed(for: body)
        let base = RGB(hex: body.colorHex)
        let hot = base.mix(.white, 0.55)
        let cool = base.scaled(0.7)
        let inv = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inv
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inv
                // granulation cells + bright filaments
                let g = Noise.fbm(u: u, v: v, frequency: 28, octaves: 4, seed: seed, gain: 0.55)
                let cells = min(1, powf(g, 1.6) * 1.35)
                let f = Noise.ridged(u: u, v: v, frequency: 9, octaves: 3, seed: seed &+ 4)
                var c = cool.mix(hot, cells)
                c = c.mix(.white, smoothstep(0.9, 1.0, f) * 0.35)
                cv.set(x, y, c.scaled(1.05))
            }
        }
        // Sunspots for anything Sun-like (cool red dwarfs are spot-covered too, but too dark to read).
        let tempK = body.temperatureK ?? 5800
        if tempK > 4200 {
            var rng = SeededRNG(seed: UInt64(seed) &* 0xD1B5_4A32_D192_ED03)
            let ctx = cv.ctx
            let s = CGFloat(size)
            for _ in 0..<6 {
                let r = s * CGFloat(Float.random(in: 0.012...0.03, using: &rng))
                let cx = CGFloat(Float.random(in: 0..<1, using: &rng)) * s
                let cy = s * CGFloat(0.3 + Float.random(in: 0..<1, using: &rng) * 0.4)
                ctx.setFillColor(base.scaled(0.45).uiColor.withAlphaComponent(0.55).cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - r * 1.8, y: cy - r * 1.3, width: r * 3.6, height: r * 2.6))
                ctx.setFillColor(UIColor(white: 0.05, alpha: 0.75).cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r * 0.7, width: r * 2, height: r * 1.4))
            }
        }
        return cv.makeImage()
    }
}

// MARK: - Helpers

@inline(__always)
private func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    if e0 == e1 { return x < e0 ? 0 : 1 }
    let t = min(1, max(0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

/// Tiny linear-RGB colour used inside the pixel loops.
private struct RGB {
    var r: Float
    var g: Float
    var b: Float

    init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }

    /// Parses "RRGGBB" / "#RRGGBB"; anything unparsable becomes mid grey.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = RGB(0.5, 0.5, 0.5); return }
        r = Float((v >> 16) & 0xFF) / 255
        g = Float((v >> 8) & 0xFF) / 255
        b = Float(v & 0xFF) / 255
    }

    init(_ color: UIColor) {
        var cr: CGFloat = 1, cg: CGFloat = 1, cb: CGFloat = 1, ca: CGFloat = 1
        if !color.getRed(&cr, green: &cg, blue: &cb, alpha: &ca) {
            var w: CGFloat = 1
            if color.getWhite(&w, alpha: &ca) { cr = w; cg = w; cb = w }
        }
        r = Float(cr); g = Float(cg); b = Float(cb)
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)

    @inline(__always) func mix(_ o: RGB, _ t: Float) -> RGB {
        let k = min(1, max(0, t))
        return RGB(r + (o.r - r) * k, g + (o.g - g) * k, b + (o.b - b) * k)
    }
    @inline(__always) func scaled(_ k: Float) -> RGB { RGB(r * k, g * k, b * k) }

    var uiColor: UIColor {
        UIColor(red: CGFloat(min(1, max(0, r))), green: CGFloat(min(1, max(0, g))), blue: CGFloat(min(1, max(0, b))), alpha: 1)
    }
    var hexString: String {
        String(format: "%02X%02X%02X", Int(min(1, max(0, r)) * 255), Int(min(1, max(0, g)) * 255), Int(min(1, max(0, b)) * 255))
    }
}

/// Hash-based value noise, tileable along u with an integer period (so it wraps seamlessly around a sphere).
private enum Noise {
    @inline(__always)
    static func hash(_ x: Int32, _ y: Int32, _ seed: UInt32) -> Float {
        var h: UInt32 = UInt32(bitPattern: x) &* 0x27d4_eb2d
        h ^= UInt32(bitPattern: y) &* 0x1656_67b1
        h ^= seed &* 0x9E37_79B9
        h ^= h >> 15
        h &*= 0x2c1b_3c6d
        h ^= h >> 12
        h &*= 0x297a_2d39
        h ^= h >> 15
        return Float(h & 0x00FF_FFFF) * (1.0 / 16_777_215.0)
    }

    /// Smooth value noise at (x, y); x wraps with `period` cells.
    @inline(__always)
    static func value(_ x: Float, _ y: Float, period: Int32, seed: UInt32) -> Float {
        let fx0 = x.rounded(.down), fy0 = y.rounded(.down)
        var xi = Int32(fx0)
        let yi = Int32(fy0)
        let tx = x - fx0, ty = y - fy0
        let sx = tx * tx * (3 - 2 * tx)
        let sy = ty * ty * (3 - 2 * ty)
        xi = xi % period
        if xi < 0 { xi += period }
        var xi1 = xi + 1
        if xi1 >= period { xi1 = 0 }
        let a = hash(xi, yi, seed), b = hash(xi1, yi, seed)
        let c = hash(xi, yi + 1, seed), d = hash(xi1, yi + 1, seed)
        let top = a + (b - a) * sx
        let bot = c + (d - c) * sx
        return top + (bot - top) * sy
    }

    /// fBm in 0...1. `frequencyU` = number of cells across u ∈ 0..1 at the base octave (tileable),
    /// `frequencyV` likewise for v (not tileable, doesn't need to be).
    static func fbm(u: Float, v: Float, frequencyU: Int, frequencyV: Int, octaves: Int, seed: UInt32, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0
        var fu = max(1, frequencyU), fv = max(1, frequencyV)
        for o in 0..<max(1, octaves) {
            let n = value(u * Float(fu), v * Float(fv), period: Int32(fu), seed: seed &+ UInt32(o) &* 131)
            sum += n * amp
            norm += amp
            amp *= gain
            fu *= 2
            fv *= 2
        }
        return sum / norm
    }

    @inline(__always)
    static func fbm(u: Float, v: Float, frequency: Int, octaves: Int, seed: UInt32, gain: Float = 0.5) -> Float {
        fbm(u: u, v: v, frequencyU: frequency, frequencyV: frequency, octaves: octaves, seed: seed, gain: gain)
    }

    /// Ridged multifractal look: 1 at the "ridges", 0 far from them.
    static func ridged(u: Float, v: Float, frequency: Int, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0
        var f = max(1, frequency)
        for o in 0..<max(1, octaves) {
            let n = value(u * Float(f), v * Float(f), period: Int32(f), seed: seed &+ UInt32(o) &* 131)
            sum += (1 - abs(2 * n - 1)) * amp
            norm += amp
            amp *= 0.5
            f *= 2
        }
        return sum / norm
    }
}

/// RGBA8 bitmap with a top-left origin for both pixel writes and CoreGraphics drawing.
private final class Canvas {
    let width: Int
    let height: Int
    let ctx: CGContext
    private let base: UnsafeMutablePointer<UInt8>
    private let bytesPerRow: Int
    private let alpha: Bool

    init?(width: Int, height: Int, alpha: Bool) {
        let info: UInt32 = (alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              let data = ctx.data else { return nil }
        self.width = width
        self.height = height
        self.ctx = ctx
        self.alpha = alpha
        self.base = data.assumingMemoryBound(to: UInt8.self)
        self.bytesPerRow = ctx.bytesPerRow
        memset(base, 0, bytesPerRow * height)
        // Flip so CG drawing uses the same top-left origin as the pixel writes below.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
    }

    /// Writes a (premultiplied) pixel. Values are clamped.
    @inline(__always)
    func set(_ x: Int, _ y: Int, _ c: RGB, alpha a: Float = 1) {
        let p = base + y * bytesPerRow + x * 4
        let k = alpha ? min(1, max(0, a)) : 1
        p[0] = UInt8(min(1, max(0, c.r * k)) * 255 + 0.5)
        p[1] = UInt8(min(1, max(0, c.g * k)) * 255 + 0.5)
        p[2] = UInt8(min(1, max(0, c.b * k)) * 255 + 0.5)
        p[3] = UInt8(k * 255 + 0.5)
    }

    func makeImage() -> UIImage {
        guard let cg = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

/// Lock-protected image cache; generation happens outside the lock so a slow render never blocks lookups.
private final class TextureCache: @unchecked Sendable {
    private var images: [String: UIImage] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[key]
    }

    func set(_ key: String, _ image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        images[key] = image
    }
}

/// SplitMix64 — deterministic so every launch draws the same craters and storms.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
