import Foundation

/// Camera framing is independent of display scale and repository input order.
enum ProjectArchitectureViewport {
    struct Frame {
        let center: SIMD3<Float>
        let distance: Float
    }

    static func frame(points: [SIMD3<Float>], size: CGSize) -> Frame {
        let points = points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        guard !points.isEmpty else { return Frame(center: .zero, distance: 12) }
        let minimum = points.reduce(points[0]) { simdMin($0, $1) }
        let maximum = points.reduce(points[0]) { simdMax($0, $1) }
        let center = (minimum + maximum) / 2
        let aspect = Float(max(size.width, 1) / max(size.height, 1))
        let tangent = tan(Float(57) * .pi / 360)
        let distance = points.map { point -> Float in
            let delta = point - center
            let horizontal = (abs(delta.x) + 3.2) / (tangent * aspect)
            let vertical = (abs(delta.y) + 2.5) / tangent
            return delta.z + max(horizontal, vertical)
        }.max() ?? 12
        return Frame(center: center, distance: max(10, distance * 1.08))
    }

    private static func simdMin(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
    }

    private static func simdMax(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    }
}
