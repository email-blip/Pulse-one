import Foundation
import simd

/// A triangle mesh as plain arrays, ready for RealityKit's `MeshDescriptor`.
public struct TriangleMesh: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var indices: [UInt32] = []

    public init() {}

    public var triangleCount: Int { indices.count / 3 }

    /// Axis-aligned bounds (min, max). Empty meshes return zeros.
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = positions.first else { return (.zero, .zero) }
        return positions.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    mutating func append(_ other: TriangleMesh) {
        let offset = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        indices += other.indices.map { $0 + offset }
    }

    /// Smooth vertex normals from the triangle faces.
    mutating func computeNormals() {
        var sums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            sums[a] += n; sums[b] += n; sums[c] += n
        }
        normals = sums.map { simd_length($0) > 1e-9 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0) }
    }
}

/// Procedural, anatomically plausible (stylised) heart: ventricles with apex tilted to the left,
/// two atria, aorta with arch, pulmonary trunk and superior vena cava.
/// Built in code so there is no third-party asset to license. Units: about 1 = heart height.
public enum HeartGeometry {
    public enum Part: String, CaseIterable, Sendable {
        case ventricles, atria, vessels
    }

    /// One mesh per part, so parts can contract and be coloured independently.
    public static func make(detail: Int = 48) -> [Part: TriangleMesh] {
        let d = max(12, detail)
        var atria = TriangleMesh()
        atria.append(ellipsoid(center: [0.28, 0.42, -0.08], radii: [0.26, 0.22, 0.24], detail: d / 2))   // right atrium
        atria.append(ellipsoid(center: [-0.24, 0.46, -0.18], radii: [0.24, 0.20, 0.22], detail: d / 2)) // left atrium
        var vessels = TriangleMesh()
        // Aorta: rises from the centre, arches over to the left and descends behind.
        vessels.append(tube(along: [[0.02, 0.35, 0.02], [0.05, 1.05, 0.05], [-0.45, 1.10, -0.10], [-0.42, 0.55, -0.30]],
                            radius: 0.11, segments: d, sides: d / 3))
        // Pulmonary trunk: in front, rising to the left.
        vessels.append(tube(along: [[-0.08, 0.30, 0.18], [-0.12, 0.75, 0.25], [-0.30, 0.90, 0.10], [-0.48, 0.92, 0.0]],
                            radius: 0.09, segments: d, sides: d / 3))
        // Superior vena cava: right side, straight up.
        vessels.append(tube(along: [[0.36, 0.50, -0.10], [0.37, 0.75, -0.10], [0.38, 0.95, -0.10], [0.38, 1.10, -0.10]],
                            radius: 0.07, segments: d / 2, sides: d / 3))
        return [.ventricles: ventricles(detail: d), .atria: atria, .vessels: vessels]
    }

    /// Cone-like ventricles: wide base, rounded apex pointing down-left, shallow groove between the chambers.
    static func ventricles(detail d: Int) -> TriangleMesh {
        let tilt = simd_quatf(angle: -0.45, axis: [0, 0, 1])
        return surface(rings: d, sides: d) { u, v in
            // u: 0 = base (top) … 1 = apex; v: 0 … 2π around.
            let theta = Double(u) * .pi
            let taper = 0.55 + 0.45 * cos(Double(u) * .pi / 2)       // narrower towards the apex
            let groove = 1 - 0.07 * exp(-pow(angleDistance(Double(v), 1.9), 2) / 0.04)
            let r = 0.48 * sin(theta).magnitude.squareRoot() * taper * groove
            let x = Float(r * cos(Double(v)))
            let z = Float(r * sin(Double(v)) * 0.85)
            let y = Float(0.30 - 0.95 * (1 - cos(theta)) / 2)
            return tilt.act([x, y, z])
        }
    }

    static func ellipsoid(center: SIMD3<Float>, radii: SIMD3<Float>, detail: Int) -> TriangleMesh {
        surface(rings: max(8, detail), sides: max(8, detail)) { u, v in
            let theta = Double(u) * .pi
            let p = SIMD3<Float>(Float(sin(theta) * cos(Double(v))), Float(cos(theta)), Float(sin(theta) * sin(Double(v))))
            return center + p * radii
        }
    }

    /// A closed tube along a cubic Bézier curve.
    static func tube(along c: [SIMD3<Float>], radius: Float, segments: Int, sides: Int) -> TriangleMesh {
        precondition(c.count == 4)
        func point(_ t: Float) -> SIMD3<Float> {
            let m = 1 - t
            return m * m * m * c[0] + 3 * m * m * t * c[1] + 3 * m * t * t * c[2] + t * t * t * c[3]
        }
        var mesh = TriangleMesh()
        let rings = max(4, segments)
        let around = max(6, sides)
        var reference = SIMD3<Float>(0, 0, 1)
        for i in 0...rings {
            let t = Float(i) / Float(rings)
            let p = point(t)
            let ahead = point(min(1, t + 0.01)) - point(max(0, t - 0.01))
            let tangent = simd_normalize(ahead)
            if abs(simd_dot(tangent, reference)) > 0.95 { reference = [1, 0, 0] }
            let side = simd_normalize(simd_cross(tangent, reference))
            let up = simd_cross(side, tangent)
            reference = up
            let flare: Float = 1 + 0.25 * max(0, 1 - t * 6)        // vessels widen where they leave the heart
            for j in 0..<around {
                let a = Float(j) / Float(around) * 2 * .pi
                mesh.positions.append(p + (side * cos(a) + up * sin(a)) * radius * flare)
            }
        }
        for i in 0..<rings {
            for j in 0..<around {
                let a = UInt32(i * around + j), b = UInt32(i * around + (j + 1) % around)
                let c2 = a + UInt32(around), d2 = b + UInt32(around)
                mesh.indices += [a, c2, b, b, c2, d2]
            }
        }
        mesh.computeNormals()
        return mesh
    }

    /// Grid surface over u ∈ [0,1], v ∈ [0, 2π), poles collapsed by the shape function.
    static func surface(rings: Int, sides: Int, _ f: (Float, Float) -> SIMD3<Float>) -> TriangleMesh {
        var mesh = TriangleMesh()
        for i in 0...rings {
            let u = Float(i) / Float(rings)
            for j in 0..<sides {
                mesh.positions.append(f(u, Float(j) / Float(sides) * 2 * .pi))
            }
        }
        for i in 0..<rings {
            for j in 0..<sides {
                let a = UInt32(i * sides + j), b = UInt32(i * sides + (j + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                mesh.indices += [a, b, c, b, d, c]
            }
        }
        mesh.computeNormals()
        return mesh
    }

    static func angleDistance(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(abs(d), 2 * .pi - abs(d))
    }
}
