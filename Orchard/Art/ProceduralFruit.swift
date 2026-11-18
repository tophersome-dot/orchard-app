import SwiftUI

struct ProceduralFruit: View {
    var form: PlantForm
    var skin: FruitSkin

    var body: some View {
        Canvas { context, size in
            switch form {
            case .apple:
                drawApple(in: context, size: size)
            case .pear:
                drawPear(in: context, size: size)
            case .mango:
                drawMango(in: context, size: size)
            case .grape:
                drawGrapes(in: context, size: size)
            case .carrot:
                drawCarrot(in: context, size: size)
            case .tomato:
                drawTomato(in: context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawApple(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: size.width * 0.08, y: size.height * 0.16, width: size.width * 0.84, height: size.height * 0.78)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.16))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.minY - rect.height * 0.02),
            control2: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.minY + rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.12),
            control2: CGPoint(x: rect.midX + rect.width * 0.36, y: rect.maxY + rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.midX - rect.width * 0.36, y: rect.maxY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.16),
            control1: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.minY + rect.height * 0.22),
            control2: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.minY - rect.height * 0.02)
        )
        paint(path: path, in: context, rect: rect, seed: 7)
        stem(in: context, at: CGPoint(x: rect.midX, y: rect.minY + 2), length: rect.height * 0.16)
        leaf(in: context, at: CGPoint(x: rect.midX + 2, y: rect.minY), flip: false)
    }

    private func drawPear(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: size.width * 0.22, y: size.height * 0.14, width: size.width * 0.56, height: size.height * 0.8)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.38),
            control1: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX + rect.width * 0.18, y: rect.midY + rect.height * 0.12),
            control2: CGPoint(x: rect.midX + rect.width * 0.55, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.38),
            control1: CGPoint(x: rect.midX - rect.width * 0.55, y: rect.maxY),
            control2: CGPoint(x: rect.minX - rect.width * 0.18, y: rect.midY + rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY)
        )
        paint(path: path, in: context, rect: rect, seed: 13)
        stem(in: context, at: CGPoint(x: rect.midX, y: rect.minY), length: size.height * 0.12)
    }

    private func drawMango(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: size.width * 0.12, y: size.height * 0.22, width: size.width * 0.76, height: size.height * 0.62)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35),
            control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY),
            control1: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.maxY),
            control2: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.05)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY),
            control1: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.maxY * 0.7 + rect.minY * 0.3),
            control2: CGPoint(x: rect.minX, y: rect.midY)
        )
        paint(path: path, in: context, rect: rect, seed: 19)
    }

    private func drawTomato(in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: size.width * 0.1, y: size.height * 0.18, width: size.width * 0.8, height: size.height * 0.74)
        let path = Path(ellipseIn: rect)
        paint(path: path, in: context, rect: rect, seed: 23)
        var calyx = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        for index in 0..<5 {
            let angle = Double(index) / 5 * .pi * 2 - .pi / 2
            let tip = CGPoint(
                x: top.x + CGFloat(cos(angle)) * rect.width * 0.28,
                y: top.y + CGFloat(sin(angle)) * rect.height * 0.16
            )
            calyx.move(to: top)
            calyx.addLine(to: tip)
        }
        context.stroke(calyx, with: .color(OrchardColor.leaf), lineWidth: max(2, size.width * 0.045))
    }

    private func drawCarrot(in context: GraphicsContext, size: CGSize) {
        let root = CGRect(x: size.width * 0.34, y: size.height * 0.34, width: size.width * 0.32, height: size.height * 0.62)
        var path = Path()
        path.move(to: CGPoint(x: root.minX, y: root.minY))
        path.addQuadCurve(to: CGPoint(x: root.midX, y: root.maxY), control: CGPoint(x: root.minX - 4, y: root.midY))
        path.addQuadCurve(to: CGPoint(x: root.maxX, y: root.minY), control: CGPoint(x: root.maxX + 4, y: root.midY))
        path.closeSubpath()
        paint(path: path, in: context, rect: root, seed: 31)
        let greens = OrchardColor.leaf
        var tops = Path()
        let origin = CGPoint(x: root.midX, y: root.minY)
        for index in -2...2 {
            tops.move(to: origin)
            tops.addQuadCurve(
                to: CGPoint(x: origin.x + CGFloat(index) * size.width * 0.16, y: size.height * 0.08),
                control: CGPoint(x: origin.x + CGFloat(index) * size.width * 0.2, y: size.height * 0.22)
            )
        }
        context.stroke(tops, with: .color(greens), style: StrokeStyle(lineWidth: max(3, size.width * 0.06), lineCap: .round))
    }

    private func drawGrapes(in context: GraphicsContext, size: CGSize) {
        let spots: [CGPoint] = [
            CGPoint(x: 0.50, y: 0.28),
            CGPoint(x: 0.34, y: 0.42),
            CGPoint(x: 0.66, y: 0.42),
            CGPoint(x: 0.28, y: 0.60),
            CGPoint(x: 0.50, y: 0.58),
            CGPoint(x: 0.72, y: 0.60),
            CGPoint(x: 0.40, y: 0.76),
            CGPoint(x: 0.60, y: 0.76)
        ]
        let diameter = min(size.width, size.height) * 0.28
        for (index, spot) in spots.enumerated() {
            let rect = CGRect(
                x: size.width * spot.x - diameter / 2,
                y: size.height * spot.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            paint(path: Path(ellipseIn: rect), in: context, rect: rect, seed: index + 3)
        }
        stem(in: context, at: CGPoint(x: size.width * 0.5, y: size.height * 0.12), length: size.height * 0.12)
    }

    private func paint(path: Path, in context: GraphicsContext, rect: CGRect, seed: Int) {
        let light = skin.base.mixed(with: .white, amount: 0.35)
        let dark = skin.base.mixed(with: .black, amount: 0.28)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [light, skin.base, dark]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
        context.drawLayer { layer in
            layer.clip(to: path)
            switch skin.pattern {
            case .solid:
                break
            case .blush:
                let radius = max(rect.width, rect.height) * (0.45 + CGFloat(skin.blushAmount) * 0.35)
                let center = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.midY)
                layer.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [skin.blush.opacity(0.95), skin.blush.opacity(0)]),
                        center: center,
                        startRadius: radius * 0.1,
                        endRadius: radius
                    )
                )
            case .stripe:
                var x = rect.minX - rect.height
                let band = max(6, rect.width * 0.18)
                while x < rect.maxX + rect.height {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: x, y: rect.maxY))
                    stripe.addLine(to: CGPoint(x: x + band * 0.55, y: rect.maxY))
                    stripe.addLine(to: CGPoint(x: x + band * 0.55 + rect.height * 0.55, y: rect.minY))
                    stripe.addLine(to: CGPoint(x: x + rect.height * 0.55, y: rect.minY))
                    stripe.closeSubpath()
                    layer.fill(stripe, with: .color(skin.blush.opacity(0.35 + skin.blushAmount * 0.55)))
                    x += band * 1.7
                }
            case .speckle:
                speckles(in: layer, rect: rect, seed: seed, count: 16, radius: rect.width * 0.055, color: skin.blush)
            }
            if skin.lenticels {
                speckles(in: layer, rect: rect, seed: seed + 9, count: 12, radius: max(1.5, rect.width * 0.025), color: Color.white.opacity(0.75))
            }
            let gloss = CGRect(
                x: rect.minX + rect.width * 0.18,
                y: rect.minY + rect.height * 0.14,
                width: rect.width * 0.28,
                height: rect.height * 0.16
            )
            layer.fill(Path(ellipseIn: gloss), with: .color(Color.white.opacity(0.42)))
        }
        context.stroke(path, with: .color(dark.opacity(0.45)), lineWidth: 1.5)
    }

    private func speckles(in layer: GraphicsContext, rect: CGRect, seed: Int, count: Int, radius: CGFloat, color: Color) {
        var rng = SeededRNG(seed: UInt64(seed + 1))
        for _ in 0..<count {
            let px = rect.minX + CGFloat(rng.next()) * rect.width
            let py = rect.minY + CGFloat(rng.next()) * rect.height
            let dot = CGRect(x: px, y: py, width: radius * 2, height: radius * 1.3)
            layer.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }

    private func stem(in context: GraphicsContext, at point: CGPoint, length: CGFloat) {
        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: point.x, y: point.y - length))
        context.stroke(path, with: .color(OrchardColor.woodDark), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func leaf(in context: GraphicsContext, at point: CGPoint, flip: Bool) {
        var path = Path()
        let direction: CGFloat = flip ? -1 : 1
        path.move(to: point)
        path.addQuadCurve(
            to: CGPoint(x: point.x + 18 * direction, y: point.y - 8),
            control: CGPoint(x: point.x + 16 * direction, y: point.y - 16)
        )
        path.addQuadCurve(
            to: point,
            control: CGPoint(x: point.x + 10 * direction, y: point.y + 2)
        )
        context.fill(path, with: .color(OrchardColor.leaf))
    }
}

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> Double {
        state = 6364136223846793005 &* state &+ 1
        return Double((state >> 33) % 10_000) / 10_000
    }
}

struct FruitGlyph: View {
    var id: String?
    var form: PlantForm
    var skin: FruitSkin

    var body: some View {
        if let id, let image = FarmSprite.image(named: FarmSprite.fruit(varietyID: id)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let id, let image = VarietyArt.fruitImage(id: id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ProceduralFruit(form: form, skin: skin)
        }
    }
}
