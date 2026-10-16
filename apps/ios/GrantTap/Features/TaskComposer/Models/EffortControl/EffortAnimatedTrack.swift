import SwiftUI

struct EffortAnimatedTrack: View {
    let effort: TurnEffort?
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24,
            paused: reduceMotion || scenePhase != .active || effort == nil)) { timeline in
            Canvas { context, size in
                let bounds = CGRect(x: 0, y: 7, width: size.width, height: size.height - 14)
                let capsule = Path(roundedRect: bounds, cornerRadius: bounds.height / 2)
                context.fill(capsule, with: .color(Theme.muted.opacity(0.14)))
                let center = 16 + CGFloat(fraction) * max(0, size.width - 32)
                if let effort, fraction == 0 {
                    var ambient = context
                    ambient.clip(to: capsule)
                    ambient.opacity = 0.22
                    drawParticles(in: &ambient, bounds: bounds, width: size.width, effort: effort,
                                  time: timeline.date.timeIntervalSinceReferenceDate, ink: tint)
                }
                if let effort {
                    var fill = context
                    fill.clip(to: capsule)
                    fill.clip(to: Path(CGRect(x: 0, y: 0, width: center, height: size.height)))
                    let colors: [Color] = effort == .ultra ? [.blue, .purple, .pink] : [tint, tint.opacity(0.75)]
                    fill.fill(capsule, with: .linearGradient(Gradient(colors: colors),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    if effort == .max || effort == .ultra {
                        drawPixelField(in: &fill, bounds: bounds, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    drawParticles(in: &fill, bounds: bounds, width: center, effort: effort,
                                  time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var tint: Color { effort == .max || effort == .ultra ? .purple : .blue }

    private func drawPixelField(in context: inout GraphicsContext, bounds: CGRect, time: Double) {
        let clock = reduceMotion ? 0 : time
        for column in 0..<40 {
            for row in 0..<5 {
                let wave = (sin(Double(column) * 0.35 - clock * 1.2 + Double(row) * 0.5) + 1) / 2
                let rect = CGRect(x: bounds.width * CGFloat(column) / 40,
                    y: bounds.minY + 3 + CGFloat(row) * (bounds.height - 6) / 5, width: 4, height: 4)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(wave * 0.19)))
            }
        }
    }

    private func drawParticles(in context: inout GraphicsContext, bounds: CGRect,
                              width: CGFloat, effort: TurnEffort, time: Double, ink: Color = .white) {
        for particle in EffortMotion.particles(for: effort, time: time, reduceMotion: reduceMotion) {
            let rect = CGRect(x: CGFloat(particle.x) * width, y: bounds.minY + CGFloat(particle.y) * bounds.height,
                              width: particle.size, height: particle.size)
            let path = effort == .max ? Path(roundedRect: rect, cornerRadius: 0.6) : Path(ellipseIn: rect)
            context.fill(path, with: .color(ink.opacity(particle.opacity)))
            if effort == .ultra {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                             with: .color(.white.opacity(particle.opacity * 0.13)))
            }
        }
    }
}
