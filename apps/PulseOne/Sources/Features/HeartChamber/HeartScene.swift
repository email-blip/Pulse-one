import PulseCore
import RealityKit
import UIKit

/// RealityKit entities of the Heart Chamber: procedural heart (no third-party asset),
/// studio lights and slowly drifting particles.
@MainActor
final class HeartScene {
    enum Look: String, CaseIterable, Identifiable {
        case anatomy, hologram
        var id: String { rawValue }
        var title: String { self == .anatomy ? "Anatomie" : "Hologramm" }
    }

    let root = Entity()
    private var parts: [HeartGeometry.Part: ModelEntity] = [:]
    private(set) var look: Look?

    func build() -> Entity {
        let meshes = HeartGeometry.make(detail: 64)
        for (part, mesh) in meshes {
            var descriptor = MeshDescriptor(name: part.rawValue)
            descriptor.positions = MeshBuffers.Positions(mesh.positions)
            descriptor.normals = MeshBuffers.Normals(mesh.normals)
            descriptor.primitives = .triangles(mesh.indices)
            guard let resource = try? MeshResource.generate(from: [descriptor]) else { continue }
            let entity = ModelEntity(mesh: resource, materials: [])
            root.addChild(entity)
            parts[part] = entity
        }
        apply(.anatomy)
        root.position = [0, -0.15, 0]

        let key = DirectionalLight()
        key.light.intensity = 3_000
        key.look(at: .zero, from: [1.2, 1.8, 2.0], relativeTo: nil)
        root.addChild(key)

        let rim = PointLight()
        rim.light.color = UIColor(red: 0.08, green: 0.85, blue: 0.95, alpha: 1)   // Bio Cyan
        rim.light.intensity = 30_000
        rim.light.attenuationRadius = 6
        rim.position = [-1.4, 0.8, -1.2]
        root.addChild(rim)

        let fill = PointLight()
        fill.light.color = UIColor(red: 0.61, green: 0.44, blue: 1.0, alpha: 1)   // Neural Violet
        fill.light.intensity = 15_000
        fill.light.attenuationRadius = 5
        fill.position = [1.4, -0.6, 1.0]
        root.addChild(fill)

        let particles = Entity()
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [1.4, 1.4, 1.4]
        emitter.speed = 0.03
        emitter.mainEmitter.birthRate = 40
        emitter.mainEmitter.lifeSpan = 4
        emitter.mainEmitter.size = 0.012
        emitter.mainEmitter.color = .constant(.single(UIColor(red: 1.0, green: 0.39, blue: 0.31, alpha: 0.8)))
        particles.components.set(emitter)
        root.addChild(particles)
        return root
    }

    func apply(_ newLook: Look) {
        guard newLook != look else { return }
        look = newLook
        for (part, entity) in parts {
            entity.model?.materials = [material(for: part, look: newLook)]
        }
    }

    /// Scales chambers with the beat. Contraction values come from `Heartbeat` (derived from BPM).
    func pose(_ contraction: Heartbeat.Contraction, yaw: Float, pitch: Float, zoom: Float) {
        parts[.ventricles]?.scale = SIMD3(repeating: 1 - 0.08 * Float(contraction.ventricles))
        parts[.atria]?.scale = SIMD3(repeating: 1 - 0.12 * Float(contraction.atria))
        root.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.scale = SIMD3(repeating: zoom)
    }

    private func material(for part: HeartGeometry.Part, look: Look) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        switch look {
        case .anatomy:
            let base: UIColor = switch part {
            case .ventricles: UIColor(red: 0.62, green: 0.10, blue: 0.12, alpha: 1)
            case .atria: UIColor(red: 0.70, green: 0.16, blue: 0.18, alpha: 1)
            case .vessels: UIColor(red: 0.78, green: 0.22, blue: 0.24, alpha: 1)
            }
            m.baseColor = .init(tint: base)
            m.roughness = .init(floatLiteral: 0.38)
            m.metallic = .init(floatLiteral: 0.0)
            m.clearcoat = .init(floatLiteral: 0.7)
            m.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.39, blue: 0.31, alpha: 1))
            m.emissiveIntensity = 0.15
        case .hologram:
            let glow = part == .vessels
                ? UIColor(red: 0.61, green: 0.44, blue: 1.0, alpha: 1)
                : UIColor(red: 0.08, green: 0.85, blue: 0.95, alpha: 1)
            m.baseColor = .init(tint: glow)
            m.emissiveColor = .init(color: glow)
            m.emissiveIntensity = 1.2
            m.roughness = .init(floatLiteral: 0.2)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.38))
        }
        return m
    }
}
