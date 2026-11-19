import SwiftUI

struct FarmMotionState: Equatable {
    var liftedID: String? = nil
    var bounces: [String: Date] = [:]
    var sprouts: [String: Date] = [:]
    var reduceMotion: Bool = false
}

struct FarmGhost: Equatable {
    var tile: FarmTile
    var sprite: String?
    var valid: Bool
}

struct FarmSpark: Identifiable, Equatable {
    enum Kind: Equatable {
        case leaf
        case dust
        case chip
        case sparkle
        case ripple
        case floater
    }

    var id = UUID()
    var kind: Kind
    var tile: FarmTile
    var born: Date
    var text: String = ""
}

struct FallingTree: Identifiable, Equatable {
    var id = UUID()
    var tile: FarmTile
    var sprite: String
    var born: Date
    var held: Bool = false
}

/// Particles, the tipping tree, the brush ring, and the growth banner. The map itself stays still.
struct FarmJuiceOverlay: View {
    var sparks: [FarmSpark]
    var falling: [FallingTree]
    var brush: CGPoint?
    var banner: String?
    var selected: FarmTile?
    var camera: FarmCamera
    var canvasSize: CGSize
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.2 : 1.0 / 30.0)) { timeline in
            Canvas { context, _ in
                let now = timeline.date
                drawButterfly(at: now, in: context)
                if let selected {
                    drawPulse(at: selected, now: now, in: context)
                }
                for spark in sparks {
                    draw(spark, now: now, in: context)
                }
                for tree in falling {
                    drawTree(tree, now: now, in: context)
                }
                if let brush {
                    drawRing(at: brush, now: now, in: context)
                }
            }
        }
        .allowsHitTesting(false)
        .overlay(alignment: .top) {
            if let banner {
                Text(banner)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrchardColor.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 72)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    private func draw(_ spark: FarmSpark, now: Date, in context: GraphicsContext) {
        let age = now.timeIntervalSince(spark.born)
        let center = camera.screenPoint(IsoMap.center(spark.tile), in: canvasSize)
        switch spark.kind {
        case .leaf, .dust:
            let life = 0.7
            guard age < life else { return }
            let fade = 1 - age / life
            let radius = IsoMap.tileWidth * camera.scale * CGFloat(0.28 + age)
            let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.65, width: radius * 2, height: radius * 1.3)
            let color = spark.kind == .leaf
                ? Color(red: 0.45, green: 0.72, blue: 0.28)
                : Color(red: 0.62, green: 0.52, blue: 0.36)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.4 * fade)))
        case .chip:
            guard age < 0.55 else { return }
            let fade = 1 - age / 0.55
            for index in 0..<5 {
                let angle = Double(index) / 5 * .pi * 2 + age * 3
                let distance = CGFloat(10 + age * 46) * camera.scale
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance * 0.6 - CGFloat(age) * 18)
                let size: CGFloat = 4
                let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size * 0.6)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.55, green: 0.36, blue: 0.18).opacity(0.8 * fade)))
            }
        case .sparkle:
            guard age < 0.6 else { return }
            let fade = 1 - age / 0.6
            for index in 0..<6 {
                let angle = Double(index) / 6 * .pi * 2
                let distance = CGFloat(8 + age * 40) * max(camera.scale, 0.4)
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y - 20 * camera.scale + CGFloat(sin(angle)) * distance * 0.7)
                let rect = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.9 * fade)))
            }
        case .ripple:
            guard age < 0.35 else { return }
            let fade = 1 - age / 0.35
            let radius = IsoMap.tileWidth * camera.scale * CGFloat(0.35 + age * 1.4)
            let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.5, width: radius * 2, height: radius))
            context.stroke(path, with: .color(Color.white.opacity(0.55 * fade)), lineWidth: 2)
        case .floater:
            guard age < 1.1 else { return }
            let fade = age < 0.7 ? 1.0 : max(0, 1 - (age - 0.7) / 0.4)
            let lift = reduceMotion ? 0 : CGFloat(age) * 36
            let text = Text(spark.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(OrchardColor.ink)
            context.drawLayer { layer in
                layer.opacity = fade
                layer.draw(layer.resolve(text), at: CGPoint(x: center.x, y: center.y - 28 - lift), anchor: .center)
            }
        }
    }

    private func drawTree(_ tree: FallingTree, now: Date, in context: GraphicsContext) {
        let age = tree.held ? 0.32 : now.timeIntervalSince(tree.born)
        guard tree.held || age < 0.75 else { return }
        let progress = tree.held ? 0.45 : min(1, age / 0.7)
        let center = camera.screenPoint(IsoMap.center(tree.tile), in: canvasSize)
        let shake = tree.held || reduceMotion ? 0 : sin(progress * 18) * 4 * (1 - progress)
        let tip = reduceMotion ? 0 : progress * 0.9
        let fade = tree.held ? 1.0 : max(0, 1 - max(0, progress - 0.55) / 0.45)
        let width = IsoMap.tileWidth * 1.15 * camera.scale
        let height = width * 1.7
        let rect = CGRect(x: center.x - width / 2, y: center.y - height, width: width, height: height)
        context.drawLayer { layer in
            layer.opacity = fade
            layer.translateBy(x: center.x + shake, y: center.y)
            layer.rotate(by: .radians(tip))
            layer.translateBy(x: -center.x, y: -center.y)
            layer.draw(layer.resolve(Image(tree.sprite)), in: rect)
        }
    }

    private func drawPulse(at tile: FarmTile, now: Date, in context: GraphicsContext) {
        let center = camera.screenPoint(IsoMap.center(tile), in: canvasSize)
        let pulse = reduceMotion ? 0.7 : 0.45 + 0.35 * (0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 4))
        let width = IsoMap.tileWidth * camera.scale * 1.05
        let height = IsoMap.tileHeight * camera.scale * 1.05
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - height / 2))
        path.addLine(to: CGPoint(x: center.x + width / 2, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + height / 2))
        path.addLine(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.closeSubpath()
        context.stroke(path, with: .color(Color.white.opacity(pulse)), lineWidth: 2)
    }

    private func drawRing(at point: CGPoint, now: Date, in context: GraphicsContext) {
        let radius = IsoMap.tileWidth * max(camera.scale, 0.35) * 0.55
        let alpha = 0.35 + 0.15 * sin(now.timeIntervalSinceReferenceDate * 5)
        let rect = CGRect(x: point.x - radius, y: point.y - radius * 0.55, width: radius * 2, height: radius * 1.1)
        context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)), lineWidth: 3)
    }

    private func drawButterfly(at date: Date, in context: GraphicsContext) {
        guard !reduceMotion else { return }
        let time = date.timeIntervalSinceReferenceDate
        let x = canvasSize.width * 0.5 + CGFloat(sin(time * 0.35)) * canvasSize.width * 0.28
        let y = canvasSize.height * 0.32 + CGFloat(sin(time * 0.8)) * 24
        let wing = 5 + 3 * abs(sin(time * 14))
        let left = CGRect(x: x - wing - 1, y: y - 2, width: wing, height: 4)
        let right = CGRect(x: x + 1, y: y - 2, width: wing, height: 4)
        context.fill(Path(ellipseIn: left), with: .color(Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0.85)))
        context.fill(Path(ellipseIn: right), with: .color(Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0.85)))
    }
}
