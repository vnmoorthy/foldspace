import SceneKit
import UIKit

/// The 3D "hologram in the fold". One instance lives in `SceneViewport`'s coordinator.
///
/// Camera model: a `rig` node at the origin pitches with the hinge; the camera sits on the rig's +z
/// axis looking back at the origin, and the key/fill/rim lights ride on the rig so the lit side of the
/// planet never changes relative to the viewer (it's a hologram, not a sunlit world). The current body
/// is positioned, in rig space, so that its lowest point sits just *below* the bottom edge of the
/// viewport — i.e. on the physical fold between the two halves of the inner display. Closing the lid
/// raises the camera pitch (you look down onto the body, revealing its pole / ring plane / accretion
/// disc), opening it flattens the view and brings the camera slightly closer.
///
/// Node budget is deliberately tiny (starfield sphere + ≤ 6 body nodes + 4 lights + 2 glow nodes +
/// 1 particle emitter; ~40 short-lived fragments during a shatter) so it runs at 60 fps in the simulator.
@MainActor
final class SpaceScene {

    let scene: SCNScene
    let cameraNode: SCNNode

    // MARK: - Tunables

    private enum Cam {
        static let fov: CGFloat = 42                 // vertical field of view, degrees
        static let baseDistance: Float = 4.2          // camera distance when the phone is flat
        static let distanceGrowth: Float = 0.22       // extra distance (fraction) when fully closed
        static let pitchPerDegree: Double = 0.35      // camera pitch = (180 − angle) × this
        static let floorFraction: Float = 0.92        // 8 % of the body dips below the fold
        static let hingeAnimation: CFTimeInterval = 0.08
    }

    // MARK: - Nodes

    private let rig = SCNNode()          // pitches with the hinge; camera + lights live here
    private let camera = SCNCamera()
    private let bodyAnchor = SCNNode()   // placed so the body's floor sits on the fold
    private let bodyTilt = SCNNode()     // axial tilt (rings / discs inherit it)
    private let bodySpin = SCNNode()     // rotates the sphere about its axis
    private var bodySphereNode: SCNNode?
    private let starfield = SCNNode()
    private let keyLight = SCNNode()
    private let fillLight = SCNNode()
    private let rimLight = SCNNode()
    private let ambientLight = SCNNode()
    private let chargeLightNode = SCNNode()
    private let chargeOrb = SCNNode()
    private let chargeHalo = SCNNode()
    private let warpEmitter = SCNNode()
    private let warpSystem = SCNParticleSystem()
    private let fragmentRoot = SCNNode()

    // MARK: - State

    private var currentBody: CelestialBody?
    private var currentRadius: Float = 1
    private var hingeAngle: Double = 110
    private var warpActive = false
    private var shatteredBodyID: String?

    // Camera-local spot where the Nova Lance emitter (in the console, below the fold) bleeds into the view.
    private let chargeLocal = SCNVector3(0, -1.32, -3.2)

    // MARK: - Init

    init() {
        scene = SCNScene()
        scene.background.contents = nil          // transparent: the cockpit gradient shows through
        scene.lightingEnvironment.contents = nil

        camera.fieldOfView = Cam.fov
        camera.projectionDirection = .vertical
        camera.zNear = 0.05
        camera.zFar = 250
        camera.wantsHDR = false                  // HDR breaks the transparent backdrop
        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        cameraNode.position = SCNVector3(0, 0, Cam.baseDistance)

        rig.name = "rig"
        rig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(rig)

        bodyAnchor.name = "bodyAnchor"
        bodyAnchor.addChildNode(bodyTilt)
        bodyTilt.addChildNode(bodySpin)
        scene.rootNode.addChildNode(bodyAnchor)

        fragmentRoot.name = "fragments"
        scene.rootNode.addChildNode(fragmentRoot)

        buildStarfield()
        buildLights()
        buildChargeGlow()
        buildWarpStreaks()
        updateRig(animated: false)
    }

    // MARK: - Public API

    /// Rebuilds the hologram for `body`. `system` tints the key light with the primary star's colour.
    func show(body: CelestialBody, system: StarSystem, animated: Bool) {
        currentBody = body
        shatteredBodyID = nil
        rebuildBody(body)
        tintLights(for: system, body: body)

        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        updateRig(animated: false)
        bodyAnchor.opacity = animated ? 0 : 1
        bodyAnchor.scale = animated ? SCNVector3(0.7, 0.7, 0.7) : SCNVector3(1, 1, 1)
        SCNTransaction.commit()

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            bodyAnchor.opacity = 1
            bodyAnchor.scale = SCNVector3(1, 1, 1)
            SCNTransaction.commit()
        }

        // Warm the rest of the system in the background so hops don't stall on texture synthesis.
        PlanetMaterials.prewarm(system.allBodies.filter { $0.id != body.id })
    }

    /// Hinge angle in degrees (0 closed … 180 flat). Drives camera pitch, distance and the body's
    /// anchor so it stays glued to the fold.
    func setHinge(angle: Double) {
        hingeAngle = min(180, max(0, angle))
        updateRig(animated: true)
    }

    /// Warp / hop streaks. `progress` 0…1 ramps the streak density and speed; the current body fades
    /// out over the first ~40 % so the destination can fade in via `show`.
    func setWarp(progress: Double, active: Bool) {
        let p = CGFloat(min(1, max(0, progress)))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.1
        if active {
            warpSystem.birthRate = 220 + 900 * p
            warpSystem.speedFactor = 1 + p * 1.6
            camera.fieldOfView = Cam.fov + 16 * CGFloat(sin(Double(p) * .pi))
            if shatteredBodyID == nil {
                bodyAnchor.opacity = max(0, 1 - p * 2.4)
            }
        } else if warpActive {
            warpSystem.birthRate = 0
            warpSystem.speedFactor = 1
            camera.fieldOfView = Cam.fov
            if shatteredBodyID == nil {
                bodyAnchor.opacity = 1
            }
        }
        SCNTransaction.commit()
        warpActive = active
    }

    /// Nova Lance fired: flash + beam from the console emitter, the body bursts into ~40 fragments that
    /// fly outward and fade. The next `show(body:…)` rebuilds a fresh sphere.
    func shatter(bodyID: String) {
        guard let body = currentBody else { return }
        shatteredBodyID = bodyID
        let center = bodyAnchor.worldPosition
        let radius = currentRadius
        let material = bodySphereNode?.geometry?.firstMaterial ?? PlanetMaterials.placeholderMaterial(for: body)

        // Hide the intact body immediately.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        bodyAnchor.opacity = 0
        SCNTransaction.commit()

        spawnBeam(to: center)
        spawnFlash(at: center, radius: radius)
        spawnFragments(at: center, radius: radius, material: material)
    }

    /// Nova Lance charge 0…1: a cyan point light + glowing orb peek up from the fold (the emitter lives
    /// in the console below), lighting the planet from beneath as the squeeze tightens.
    func setWeaponCharge(_ c: Double) {
        let k = CGFloat(min(1, max(0, c)))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.1
        chargeLightNode.light?.intensity = 3200 * k
        chargeOrb.opacity = k
        let s = 0.5 + 1.6 * k
        chargeOrb.scale = SCNVector3(s, s, s)
        chargeOrb.geometry?.firstMaterial?.emission.intensity = 0.6 + 2.2 * k
        chargeHalo.opacity = k * k
        let hs = 0.6 + 1.8 * k
        chargeHalo.scale = SCNVector3(hs, hs, hs)
        SCNTransaction.commit()
    }

    // MARK: - Camera rig / hologram placement

    /// Places the camera and the body so the body's floor sits on the fold for the current hinge angle.
    private func updateRig(animated: Bool) {
        let closedness = (180 - hingeAngle) / 180                       // 0 flat … 1 closed
        let pitchDeg = (180 - hingeAngle) * Cam.pitchPerDegree
        let pitch = Float(pitchDeg * .pi / 180)
        let distance = Cam.baseDistance * (1 + Cam.distanceGrowth * Float(closedness))
        let halfH = distance * tanf(Float(Cam.fov) * 0.5 * Float.pi / 180)  // half visible height at the origin's depth
        let centerY = -halfH + currentRadius * Cam.floorFraction              // rig-space y of the body's centre

        // rig-local (0, centerY, 0) → world, for a rig rotated by −pitch about x
        let worldY = centerY * cosf(pitch)
        let worldZ = -centerY * sinf(pitch)

        SCNTransaction.begin()
        if animated {
            SCNTransaction.animationDuration = Cam.hingeAnimation
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        } else {
            SCNTransaction.disableActions = true
        }
        rig.eulerAngles = SCNVector3(-pitch, 0, 0)
        cameraNode.position = SCNVector3(0, 0, distance)
        bodyAnchor.position = SCNVector3(0, worldY, worldZ)
        SCNTransaction.commit()
    }

    // MARK: - Body construction

    private static func visualRadius(for body: CelestialBody) -> Float {
        switch body.kind {
        case .star: return 1.05
        case .blackHole: return 0.72
        case .galaxy: return 1.1
        case .dwarfPlanet: return 0.72
        case .planet:
            switch body.planetClass ?? .rocky {
            case .gasGiant: return 1.15
            case .iceGiant: return 1.05
            case .superEarth: return 1.0
            default: return 0.92
            }
        }
    }

    private func rebuildBody(_ body: CelestialBody) {
        bodySpin.removeAllActions()
        bodyTilt.removeAllActions()
        for n in bodySpin.childNodes { n.removeFromParentNode() }
        for n in bodyTilt.childNodes where n !== bodySpin { n.removeFromParentNode() }
        for n in bodyAnchor.childNodes where n !== bodyTilt { n.removeFromParentNode() }
        bodyTilt.eulerAngles = SCNVector3(0, 0, 0)
        bodySpin.eulerAngles = SCNVector3(0, 0, 0)
        bodySphereNode = nil

        let r = Self.visualRadius(for: body)
        currentRadius = r

        switch body.kind {
        case .star:
            addSphere(body, radius: r, segments: 56)
            addHalo(color: PlanetMaterials.baseColor(for: body), size: r * 3.6, opacity: 0.95, falloff: 2.2)
            spin(period: 70)

        case .blackHole:
            addBlackHole(body, radius: r)

        case .galaxy:
            addGalaxy(body, radius: r)

        case .planet, .dwarfPlanet:
            let cls = body.planetClass ?? .rocky
            addSphere(body, radius: r, segments: 56)
            if Self.hasAtmosphere(cls) {
                addAtmosphere(color: Self.atmosphereColor(body, cls), radius: r)
            }
            if PlanetMaterials.hasRings(body) {
                addRings(body, radius: r)
                bodyTilt.eulerAngles = SCNVector3(0.3, 0, body.id == "saturn" ? 0.47 : 1.7)
            } else {
                bodyTilt.eulerAngles = SCNVector3(0, 0, 0.18)
            }
            let period: Double
            switch cls {
            case .gasGiant: period = 22
            case .iceGiant: period = 30
            default: period = body.kind == .dwarfPlanet ? 34 : 42
            }
            spin(period: period)
        }
    }

    private func spin(period: Double) {
        let rotate = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: period)
        bodySpin.runAction(SCNAction.repeatForever(rotate), forKey: "spin")
    }

    /// The main sphere. Shows a flat-colour placeholder while the procedural texture is synthesised
    /// off the main thread, then swaps in the real material.
    private func addSphere(_ body: CelestialBody, radius: Float, segments: Int) {
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = segments
        let node = SCNNode(geometry: sphere)
        node.name = "body"
        if PlanetMaterials.cachedTexture(for: body) != nil {
            sphere.firstMaterial = PlanetMaterials.material(for: body)
        } else {
            sphere.firstMaterial = PlanetMaterials.placeholderMaterial(for: body)
            loadTextureAsync(for: body)
        }
        bodySpin.addChildNode(node)
        bodySphereNode = node
    }

    private func loadTextureAsync(for body: CelestialBody) {
        let id = body.id
        DispatchQueue.global(qos: .userInitiated).async {
            _ = PlanetMaterials.texture(for: body)
            Task { @MainActor [weak self] in
                self?.applyTexture(forBodyID: id)
            }
        }
    }

    private func applyTexture(forBodyID id: String) {
        guard let body = currentBody, body.id == id, let node = bodySphereNode, shatteredBodyID == nil else { return }
        let material = PlanetMaterials.material(for: body)
        material.transparency = 0
        node.geometry?.firstMaterial = material
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        material.transparency = 1
        SCNTransaction.commit()
    }

    private static func hasAtmosphere(_ cls: PlanetClass) -> Bool {
        switch cls {
        case .earthlike, .ocean, .gasGiant, .iceGiant, .superEarth: return true
        case .rocky, .lava, .desert, .ice: return false
        }
    }

    private static func atmosphereColor(_ body: CelestialBody, _ cls: PlanetClass) -> UIColor {
        switch cls {
        case .earthlike, .ocean: return UIColor(red: 0.45, green: 0.7, blue: 1.0, alpha: 1)
        case .iceGiant: return UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
        default: return PlanetMaterials.baseColor(for: body)
        }
    }

    /// Back-face-culled shell slightly larger than the planet: only the limb survives the depth test,
    /// giving a cheap additive atmosphere rim.
    private func addAtmosphere(color: UIColor, radius: Float) {
        let shell = SCNSphere(radius: CGFloat(radius * 1.04))
        shell.segmentCount = 40
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.emission.contents = color
        m.blendMode = .add
        m.cullMode = .front
        m.transparency = 0.42
        m.writesToDepthBuffer = false
        shell.firstMaterial = m
        let node = SCNNode(geometry: shell)
        node.name = "atmosphere"
        bodyTilt.addChildNode(node)
    }

    /// Camera-facing additive glow sprite centred on the body.
    @discardableResult
    private func addHalo(color: UIColor, size: Float, opacity: CGFloat, falloff: Float, parent: SCNNode? = nil) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlanetMaterials.haloTexture(color: color, size: 256, falloff: falloff)
        m.blendMode = .add
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "halo"
        node.opacity = opacity
        node.constraints = [SCNBillboardConstraint()]
        (parent ?? bodyAnchor).addChildNode(node)
        return node
    }

    private func addRings(_ body: CelestialBody, radius: Float) {
        let plane = SCNPlane(width: CGFloat(radius * 4.8), height: CGFloat(radius * 4.8))
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = PlanetMaterials.ringTexture(for: body)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "rings"
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)   // lie in the equatorial plane
        bodyTilt.addChildNode(node)
    }

    private func addBlackHole(_ body: CelestialBody, radius: Float) {
        // Shadow sphere
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 48
        sphere.firstMaterial = PlanetMaterials.material(for: body)
        let shadow = SCNNode(geometry: sphere)
        shadow.name = "body"
        bodySpin.addChildNode(shadow)
        bodySphereNode = shadow

        // Photon ring: thin emissive torus that always faces the camera.
        let ringHolder = SCNNode()
        ringHolder.constraints = [SCNBillboardConstraint()]
        let torus = SCNTorus(ringRadius: CGFloat(radius * 1.03), pipeRadius: CGFloat(radius * 0.035))
        torus.ringSegmentCount = 72
        torus.pipeSegmentCount = 12
        let tm = SCNMaterial()
        tm.lightingModel = .constant
        tm.diffuse.contents = UIColor.black
        tm.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1)
        tm.emission.intensity = 1.6
        tm.blendMode = .add
        torus.firstMaterial = tm
        let ring = SCNNode(geometry: torus)
        ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        ringHolder.addChildNode(ring)
        bodyAnchor.addChildNode(ringHolder)

        // Accretion disc: flattened emissive torus (the dense inner flow) + wide gradient plane.
        let diskTilt = SCNNode()
        diskTilt.name = "diskTilt"
        diskTilt.eulerAngles = SCNVector3(-(Float.pi / 2 - 0.35), 0, 0)   // seen from ~20° above when flat
        bodyTilt.addChildNode(diskTilt)

        let innerTorus = SCNTorus(ringRadius: CGFloat(radius * 1.55), pipeRadius: CGFloat(radius * 0.32))
        innerTorus.ringSegmentCount = 64
        innerTorus.pipeSegmentCount = 10
        let im = SCNMaterial()
        im.lightingModel = .constant
        im.diffuse.contents = UIColor.black
        im.emission.contents = UIColor(red: 1.0, green: 0.55, blue: 0.18, alpha: 1)
        im.emission.intensity = 1.2
        im.blendMode = .add
        im.transparency = 0.55
        im.writesToDepthBuffer = false
        innerTorus.firstMaterial = im
        let inner = SCNNode(geometry: innerTorus)
        inner.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)     // torus axis → plane normal (z)
        inner.scale = SCNVector3(1, 1, 0.12)                    // flatten along the normal
        diskTilt.addChildNode(inner)

        let plane = SCNPlane(width: CGFloat(radius * 5.4), height: CGFloat(radius * 5.4))
        let pm = SCNMaterial()
        pm.lightingModel = .constant
        pm.diffuse.contents = PlanetMaterials.accretionDiskTexture()
        pm.blendMode = .add
        pm.isDoubleSided = true
        pm.writesToDepthBuffer = false
        plane.firstMaterial = pm
        let disk = SCNNode(geometry: plane)
        disk.name = "accretion"
        diskTilt.addChildNode(disk)
        disk.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: -CGFloat.pi * 2, duration: 11)))
        inner.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: -CGFloat.pi * 2, z: 0, duration: 6)))

        // Warm lensing glow behind everything.
        addHalo(color: UIColor(red: 1.0, green: 0.45, blue: 0.15, alpha: 1), size: radius * 5.2, opacity: 0.35, falloff: 3.0)
    }

    private func addGalaxy(_ body: CelestialBody, radius: Float) {
        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(-(Float.pi / 2 - 0.6), 0, 0)      // ~34° above the disc when flat
        bodyTilt.addChildNode(tilt)
        let plane = SCNPlane(width: CGFloat(radius * 3.6), height: CGFloat(radius * 3.6))
        plane.firstMaterial = PlanetMaterials.material(for: body)
        let disc = SCNNode(geometry: plane)
        disc.name = "galaxy"
        tilt.addChildNode(disc)
        disc.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: -CGFloat.pi * 2, duration: 140)))
        addHalo(color: UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1), size: radius * 1.6, opacity: 0.8, falloff: 2.6)
        bodySphereNode = disc
    }

    // MARK: - Fixed scenery

    private func buildStarfield() {
        let sphere = SCNSphere(radius: 70)
        sphere.segmentCount = 36
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlanetMaterials.starfieldTexture()
        m.cullMode = .front                      // we're inside it
        m.isDoubleSided = false
        m.writesToDepthBuffer = false
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        sphere.firstMaterial = m
        starfield.geometry = sphere
        starfield.name = "starfield"
        starfield.eulerAngles = SCNVector3(0.35, 0, 0.2)
        scene.rootNode.addChildNode(starfield)
        starfield.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 900)))
    }

    private func buildLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1400
        key.color = UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1)
        key.castsShadow = false
        keyLight.light = key
        keyLight.name = "key"
        keyLight.position = SCNVector3(-4, 4, 5)
        keyLight.look(at: SCNVector3(0, 0, 0))
        rig.addChildNode(keyLight)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 240
        fill.color = UIColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 1)
        fillLight.light = fill
        fillLight.name = "fill"
        fillLight.position = SCNVector3(5, -1, 4)
        fillLight.look(at: SCNVector3(0, 0, 0))
        rig.addChildNode(fillLight)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 750
        rim.color = UIColor(red: 0.35, green: 0.9, blue: 1.0, alpha: 1)
        rimLight.light = rim
        rimLight.name = "rim"
        rimLight.position = SCNVector3(3, 2.5, -6)
        rimLight.look(at: SCNVector3(0, 0, 0))
        rig.addChildNode(rimLight)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 90
        amb.color = UIColor(red: 0.35, green: 0.45, blue: 0.7, alpha: 1)
        ambientLight.light = amb
        ambientLight.name = "ambient"
        scene.rootNode.addChildNode(ambientLight)
    }

    /// Key light takes the colour of the system's primary (a red dwarf lights its worlds red).
    private func tintLights(for system: StarSystem, body: CelestialBody) {
        let primary = system.primary
        var tint = PlanetMaterials.baseColor(for: primary)
        var intensity: CGFloat = 1400
        switch primary.kind {
        case .blackHole:
            tint = UIColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 1)
            intensity = 700
        case .galaxy:
            tint = UIColor(red: 0.9, green: 0.9, blue: 1.0, alpha: 1)
            intensity = 1000
        default:
            break
        }
        // Blend toward white so the palette stays readable; the hue still comes through.
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        if tint.getRed(&r, green: &g, blue: &b, alpha: &a) {
            tint = UIColor(red: r + (1 - r) * 0.45, green: g + (1 - g) * 0.45, blue: b + (1 - b) * 0.45, alpha: 1)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        keyLight.light?.color = tint
        keyLight.light?.intensity = intensity
        SCNTransaction.commit()
    }

    private func buildChargeGlow() {
        let light = SCNLight()
        light.type = .omni
        light.intensity = 0
        light.color = UIColor(red: 0.24, green: 0.95, blue: 1.0, alpha: 1)
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 14
        chargeLightNode.light = light
        chargeLightNode.name = "chargeLight"
        chargeLightNode.position = chargeLocal
        cameraNode.addChildNode(chargeLightNode)

        let orb = SCNSphere(radius: 0.11)
        orb.segmentCount = 24
        let om = SCNMaterial()
        om.lightingModel = .constant
        om.diffuse.contents = UIColor(red: 0.6, green: 0.98, blue: 1.0, alpha: 1)
        om.emission.contents = UIColor(red: 0.24, green: 0.95, blue: 1.0, alpha: 1)
        om.emission.intensity = 0.6
        orb.firstMaterial = om
        chargeOrb.geometry = orb
        chargeOrb.name = "chargeOrb"
        chargeOrb.position = chargeLocal
        chargeOrb.opacity = 0
        cameraNode.addChildNode(chargeOrb)

        let halo = SCNPlane(width: 1.4, height: 1.4)
        let hm = SCNMaterial()
        hm.lightingModel = .constant
        hm.diffuse.contents = PlanetMaterials.haloTexture(color: UIColor(red: 0.24, green: 0.95, blue: 1.0, alpha: 1), size: 128, falloff: 2.8)
        hm.blendMode = .add
        hm.writesToDepthBuffer = false
        hm.readsFromDepthBuffer = false
        halo.firstMaterial = hm
        chargeHalo.geometry = halo
        chargeHalo.name = "chargeHalo"
        chargeHalo.position = chargeLocal
        chargeHalo.opacity = 0
        cameraNode.addChildNode(chargeHalo)
    }

    /// Warp streaks: particles born on a plane far in front of the camera rushing toward it.
    private func buildWarpStreaks() {
        warpSystem.birthRate = 0
        warpSystem.loops = true
        warpSystem.emitterShape = SCNPlane(width: 26, height: 16)
        warpSystem.birthLocation = .surface
        warpSystem.birthDirection = .constant
        warpSystem.emittingDirection = SCNVector3(0, 0, 1)   // toward the camera (emitter sits at −z)
        warpSystem.spreadingAngle = 1.5
        warpSystem.particleVelocity = 60
        warpSystem.particleVelocityVariation = 25
        warpSystem.particleLifeSpan = 0.9
        warpSystem.particleLifeSpanVariation = 0.3
        warpSystem.particleSize = 0.07
        warpSystem.particleSizeVariation = 0.03
        warpSystem.stretchFactor = 0.35
        warpSystem.particleColor = UIColor(red: 0.62, green: 0.95, blue: 1.0, alpha: 1)
        warpSystem.particleColorVariation = SCNVector4(0.15, 0.05, 0, 0.25)
        warpSystem.particleImage = PlanetMaterials.haloTexture(color: .white, size: 32, falloff: 1.6)
        warpSystem.blendMode = .add
        warpSystem.isLightingEnabled = false
        warpSystem.isAffectedByGravity = false
        warpSystem.isLocal = true                              // streaks ride with the camera
        warpSystem.orientationMode = .billboardViewAligned
        warpEmitter.name = "warp"
        warpEmitter.position = SCNVector3(0, 0, -32)
        warpEmitter.addParticleSystem(warpSystem)
        cameraNode.addChildNode(warpEmitter)
    }

    // MARK: - Shatter effects

    private func spawnBeam(to target: SCNVector3) {
        let origin = cameraNode.convertPosition(chargeLocal, to: nil)
        let dx = target.x - origin.x, dy = target.y - origin.y, dz = target.z - origin.z
        let length = (dx * dx + dy * dy + dz * dz).squareRoot()
        guard length > 0.01 else { return }
        let mid = SCNVector3((origin.x + target.x) / 2, (origin.y + target.y) / 2, (origin.z + target.z) / 2)

        func cylinder(radius: CGFloat, color: UIColor, intensity: CGFloat) -> SCNNode {
            let geo = SCNCylinder(radius: radius, height: CGFloat(length))
            geo.radialSegmentCount = 12
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.black
            m.emission.contents = color
            m.emission.intensity = intensity
            m.blendMode = .add
            m.writesToDepthBuffer = false
            geo.firstMaterial = m
            let n = SCNNode(geometry: geo)
            n.position = mid
            // The cylinder's axis is local +y; aim it along origin → target. `up` is any vector not
            // parallel to the beam (the beam has no x component).
            n.look(at: target, up: SCNVector3(1, 0, 0), localFront: SCNVector3(0, 1, 0))
            return n
        }
        let outer = cylinder(radius: 0.07, color: UIColor(red: 0.24, green: 0.95, blue: 1.0, alpha: 1), intensity: 1.4)
        let core = cylinder(radius: 0.022, color: .white, intensity: 2.0)
        fragmentRoot.addChildNode(outer)
        fragmentRoot.addChildNode(core)
        let fade = SCNAction.sequence([SCNAction.wait(duration: 0.12), SCNAction.fadeOut(duration: 0.4), SCNAction.removeFromParentNode()])
        outer.runAction(fade)
        core.runAction(fade)
    }

    private func spawnFlash(at center: SCNVector3, radius: Float) {
        let holder = SCNNode()
        holder.position = center
        fragmentRoot.addChildNode(holder)
        let flash = addHalo(color: UIColor(red: 0.8, green: 0.98, blue: 1.0, alpha: 1), size: radius * 1.2, opacity: 1, falloff: 1.8, parent: holder)
        let grow = SCNAction.scale(to: 6, duration: 0.6)
        grow.timingMode = .easeOut
        flash.runAction(SCNAction.group([grow, SCNAction.fadeOut(duration: 0.6)]))
        holder.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.75), SCNAction.removeFromParentNode()]))

        let light = SCNLight()
        light.type = .omni
        light.intensity = 6000
        light.color = UIColor(red: 0.7, green: 0.95, blue: 1.0, alpha: 1)
        light.attenuationEndDistance = 20
        let lightNode = SCNNode()
        lightNode.light = light
        holder.addChildNode(lightNode)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.65
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        light.intensity = 0
        SCNTransaction.commit()
    }

    private func spawnFragments(at center: SCNVector3, radius: Float, material: SCNMaterial) {
        let count = 40
        for i in 0..<count {
            // Random point on the sphere → fragment start position and flight direction.
            let theta = Float.random(in: 0..<(2 * Float.pi))
            let z = Float.random(in: -1...1)
            let s = (1 - z * z).squareRoot()
            let dir = SCNVector3(s * cosf(theta), s * sinf(theta), z)
            let start = SCNVector3(center.x + dir.x * radius * 0.75, center.y + dir.y * radius * 0.75, center.z + dir.z * radius * 0.75)

            let node: SCNNode
            if i % 5 == 4 {
                let ball = SCNSphere(radius: CGFloat(radius * Float.random(in: 0.08...0.16)))
                ball.segmentCount = 10
                ball.firstMaterial = material
                node = SCNNode(geometry: ball)
            } else {
                let geo = Self.makeTetrahedron(uvOrigin: CGPoint(x: CGFloat(Float.random(in: 0..<0.9)), y: CGFloat(Float.random(in: 0..<0.9))))
                geo.firstMaterial = material
                node = SCNNode(geometry: geo)
                let sc = radius * Float.random(in: 0.18...0.42)
                node.scale = SCNVector3(sc, sc, sc)
            }
            node.position = start
            node.eulerAngles = SCNVector3(Float.random(in: 0..<Float.pi), Float.random(in: 0..<Float.pi), 0)
            fragmentRoot.addChildNode(node)

            let dist = radius * Float.random(in: 2.6...6.0)
            let jitter = SCNVector3(Float.random(in: -0.25...0.25), Float.random(in: -0.25...0.25), Float.random(in: -0.25...0.25))
            let delta = SCNVector3((dir.x + jitter.x) * dist, (dir.y + jitter.y) * dist + 0.3, (dir.z + jitter.z) * dist)
            let dur = Double(Float.random(in: 1.9...2.5))
            let move = SCNAction.move(by: delta, duration: dur)
            move.timingMode = .easeOut
            let tumble = SCNAction.rotateBy(x: CGFloat(Float.random(in: -6...6)), y: CGFloat(Float.random(in: -6...6)), z: CGFloat(Float.random(in: -6...6)), duration: dur)
            let fade = SCNAction.sequence([SCNAction.wait(duration: dur * 0.4), SCNAction.fadeOut(duration: dur * 0.6)])
            let shrink = SCNAction.scale(by: 0.35, duration: dur)
            node.runAction(SCNAction.sequence([SCNAction.group([move, tumble, fade, shrink]), SCNAction.removeFromParentNode()]))
        }
    }

    /// Regular tetrahedron (edge ≈ 1.41) with flat-shaded faces and a small UV patch at `uvOrigin`
    /// so each fragment samples a different bit of the planet's texture.
    private static func makeTetrahedron(uvOrigin: CGPoint) -> SCNGeometry {
        let s: Float = 0.5
        let p = [SCNVector3(s, s, s), SCNVector3(s, -s, -s), SCNVector3(-s, s, -s), SCNVector3(-s, -s, s)]
        let faces: [(Int, Int, Int)] = [(0, 1, 2), (0, 3, 1), (0, 2, 3), (1, 3, 2)]   // CCW from outside
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var idx: [UInt16] = []
        for (a, b, c) in faces {
            let ab = SCNVector3(p[b].x - p[a].x, p[b].y - p[a].y, p[b].z - p[a].z)
            let ac = SCNVector3(p[c].x - p[a].x, p[c].y - p[a].y, p[c].z - p[a].z)
            var n = SCNVector3(ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z, ab.x * ac.y - ab.y * ac.x)
            let len = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
            if len > 0 { n = SCNVector3(n.x / len, n.y / len, n.z / len) }
            let base = UInt16(verts.count)
            verts.append(p[a]); verts.append(p[b]); verts.append(p[c])
            norms.append(n); norms.append(n); norms.append(n)
            uvs.append(uvOrigin)
            uvs.append(CGPoint(x: uvOrigin.x + 0.08, y: uvOrigin.y))
            uvs.append(CGPoint(x: uvOrigin.x + 0.04, y: uvOrigin.y + 0.08))
            idx.append(base); idx.append(base + 1); idx.append(base + 2)
        }
        let vSrc = SCNGeometrySource(vertices: verts)
        let nSrc = SCNGeometrySource(normals: norms)
        let tSrc = SCNGeometrySource(textureCoordinates: uvs)
        let element = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: [vSrc, nSrc, tSrc], elements: [element])
    }
}
