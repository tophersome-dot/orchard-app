import SwiftUI

struct FarmGround: View {
    var layout: PlotLayout

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [OrchardColor.grass, OrchardColor.grassDark]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            var rng = SeededRNG(seed: 42)
            for _ in 0..<90 {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                var tuft = Path()
                tuft.move(to: CGPoint(x: x, y: y))
                tuft.addQuadCurve(to: CGPoint(x: x + 8, y: y - 10), control: CGPoint(x: x + 2, y: y - 8))
                context.stroke(tuft, with: .color(OrchardColor.grassDeep.opacity(0.35)), lineWidth: 2)
            }
            for index in 0..<28 {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let color: Color = index % 3 == 0 ? OrchardColor.sun : (index % 3 == 1 ? Color.white : Color(red: 1, green: 0.45, blue: 0.55))
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 7, height: 7)), with: .color(color.opacity(0.9)))
            }

            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.5, y: size.height - 10))
            path.addCurve(
                to: layout.house,
                control1: CGPoint(x: size.width * 0.62, y: size.height * 0.72),
                control2: CGPoint(x: layout.house.x + 30, y: layout.house.y + 180)
            )
            context.stroke(
                path,
                with: .color(OrchardColor.path),
                style: StrokeStyle(lineWidth: 54, lineCap: .round)
            )
            context.stroke(
                path,
                with: .color(OrchardColor.pathEdge.opacity(0.7)),
                style: StrokeStyle(lineWidth: 58, lineCap: .round)
            )
            context.stroke(
                path,
                with: .color(OrchardColor.path),
                style: StrokeStyle(lineWidth: 46, lineCap: .round)
            )

            let bed = CGRect(x: 40, y: layout.house.y + 180, width: 390, height: max(180, layout.greenhouse.y - layout.house.y - 220))
            if bed.height > 40 {
                let bedPath = Path(roundedRect: bed, cornerRadius: 28)
                context.fill(bedPath, with: .color(OrchardColor.soil))
                context.stroke(bedPath, with: .color(OrchardColor.soilDark), lineWidth: 6)
            }
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height)
    }
}

struct FarmhouseArt: View {
    var tier: HouseTier

    var body: some View {
        ZStack {
            switch tier {
            case .shed:
                shed
            case .cottage:
                cottage
            case .farmhouse:
                farmhouse
            case .homestead:
                homestead
            }
        }
        .frame(width: 230, height: 190)
        .accessibilityLabel(tier.title)
    }

    private var shed: some View {
        ZStack {
            roof(width: 150, height: 58, color: OrchardColor.roof)
                .offset(y: -36)
            wall(width: 120, height: 78, color: OrchardColor.wood)
            door(width: 28, height: 40)
                .offset(y: 18)
            window(size: 22)
                .offset(x: 34, y: -4)
        }
    }

    private var cottage: some View {
        ZStack {
            chimney.offset(x: 48, y: -78)
            roof(width: 180, height: 70, color: OrchardColor.roof)
                .offset(y: -48)
            wall(width: 150, height: 86, color: Color(red: 0.98, green: 0.93, blue: 0.82))
            porch.offset(y: 36)
            window(size: 24).offset(x: -36, y: -6)
            window(size: 24).offset(x: 36, y: -6)
            door(width: 26, height: 36).offset(y: 16)
            flowerBox.offset(x: -36, y: 14)
        }
    }

    private var farmhouse: some View {
        ZStack {
            chimney.offset(x: 62, y: -88)
            roof(width: 200, height: 64, color: OrchardColor.roofDark)
                .offset(y: -62)
            wall(width: 168, height: 108, color: Color(red: 0.99, green: 0.95, blue: 0.86))
            window(size: 22).offset(x: -48, y: -28)
            window(size: 22).offset(x: 8, y: -28)
            window(size: 22).offset(x: 52, y: -28)
            porch.offset(y: 42)
            door(width: 28, height: 40).offset(y: 18)
            window(size: 22).offset(x: -46, y: 8)
            flowerBox.offset(x: -46, y: 26)
            weathervane.offset(y: -96)
        }
    }

    private var homestead: some View {
        ZStack {
            silo.offset(x: 92, y: 6)
            gambrel.offset(y: -36)
            wall(width: 150, height: 96, color: OrchardColor.barn)
            barnDoor.offset(y: 16)
            window(size: 20).offset(y: -22)
            loftLight.offset(x: -40, y: -8)
            loftLight.offset(x: 40, y: -8)
            cupola.offset(y: -92)
        }
    }

    private func wall(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.mixed(with: .black, amount: 0.25), lineWidth: 3)
            )
            .offset(y: 18)
    }

    private func roof(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoofShape()
            .fill(LinearGradient(colors: [color.mixed(with: .white, amount: 0.2), color], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .overlay(RoofShape().stroke(color.mixed(with: .black, amount: 0.3), lineWidth: 3))
    }

    private func door(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(OrchardColor.woodDark)
            .frame(width: width, height: height)
            .overlay(alignment: .trailing) {
                Circle().fill(OrchardColor.sun).frame(width: 5, height: 5).padding(4)
            }
    }

    private func window(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: 1, green: 0.9, blue: 0.45))
            .frame(width: size, height: size)
            .overlay(
                ZStack {
                    Rectangle().frame(width: 2, height: size)
                    Rectangle().frame(width: size, height: 2)
                }
                .foregroundStyle(OrchardColor.woodDark)
            )
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(OrchardColor.woodDark, lineWidth: 2))
    }

    private var porch: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(OrchardColor.wood)
            .frame(width: 118, height: 16)
            .overlay(alignment: .top) {
                HStack(spacing: 40) {
                    post
                    post
                }
                .offset(y: -22)
            }
    }

    private var post: some View {
        Rectangle().fill(OrchardColor.woodDark).frame(width: 6, height: 24)
    }

    private var chimney: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: 0.55, green: 0.28, blue: 0.22))
            .frame(width: 18, height: 36)
            .overlay(alignment: .top) {
                smoke.offset(y: -18)
            }
    }

    private var smoke: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.white.opacity(0.8)).frame(width: 8, height: 8)
            Circle().fill(Color.white.opacity(0.55)).frame(width: 12, height: 12)
        }
    }

    private var flowerBox: some View {
        HStack(spacing: 3) {
            Circle().fill(Color(red: 0.95, green: 0.25, blue: 0.35)).frame(width: 8, height: 8)
            Circle().fill(OrchardColor.sun).frame(width: 8, height: 8)
            Circle().fill(Color.white).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(OrchardColor.woodDark, in: Capsule())
    }

    private var weathervane: some View {
        VStack(spacing: 0) {
            Capsule().fill(OrchardColor.ink).frame(width: 22, height: 3)
            Rectangle().fill(OrchardColor.ink).frame(width: 2, height: 16)
        }
    }

    private var gambrel: some View {
        GambrelShape()
            .fill(LinearGradient(colors: [OrchardColor.barn.mixed(with: .white, amount: 0.15), OrchardColor.barnDark], startPoint: .top, endPoint: .bottom))
            .frame(width: 190, height: 78)
            .overlay(GambrelShape().stroke(Color.white.opacity(0.85), lineWidth: 4))
    }

    private var barnDoor: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(OrchardColor.cream)
            .frame(width: 54, height: 58)
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 6, y: 6))
                    path.addLine(to: CGPoint(x: 48, y: 52))
                    path.move(to: CGPoint(x: 48, y: 6))
                    path.addLine(to: CGPoint(x: 6, y: 52))
                }
                .stroke(OrchardColor.barnDark, lineWidth: 3)
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(OrchardColor.barnDark, lineWidth: 3))
    }

    private var silo: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 0.75, green: 0.8, blue: 0.78), Color(red: 0.55, green: 0.6, blue: 0.58)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 42, height: 120)
            Capsule()
                .fill(OrchardColor.roof)
                .frame(width: 48, height: 28)
                .offset(y: -52)
        }
    }

    private var cupola: some View {
        VStack(spacing: 0) {
            RoofShape().fill(OrchardColor.roofDark).frame(width: 28, height: 14)
            Rectangle().fill(OrchardColor.cream).frame(width: 16, height: 12)
        }
    }

    private var loftLight: some View {
        Circle().fill(OrchardColor.sun).frame(width: 8, height: 8)
    }
}

struct RoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GambrelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.38))
        path.closeSubpath()
        return path
    }
}

struct TractorArt: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.15))
                .frame(width: 92, height: 12)
                .offset(y: 28)
            wheel(diameter: 46).offset(x: 28, y: 16)
            wheel(diameter: 28).offset(x: -34, y: 22)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(OrchardColor.barn)
                .frame(width: 78, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(OrchardColor.barnDark, lineWidth: 3)
                )
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 6)
                .fill(OrchardColor.barnDark)
                .frame(width: 34, height: 28)
                .offset(x: 16, y: -16)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.55, green: 0.85, blue: 0.95))
                .frame(width: 16, height: 12)
                .offset(x: 20, y: -18)
            Capsule()
                .fill(OrchardColor.ink)
                .frame(width: 8, height: 16)
                .offset(x: 30, y: -30)
            RoundedRectangle(cornerRadius: 2)
                .fill(OrchardColor.woodDark)
                .frame(width: 16, height: 8)
                .offset(x: -8, y: -8)
        }
        .frame(width: 130, height: 90)
        .accessibilityLabel("Tractor")
    }

    private func wheel(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(red: 0.15, green: 0.15, blue: 0.15)).frame(width: diameter, height: diameter)
            Circle().fill(OrchardColor.sun).frame(width: diameter * 0.45, height: diameter * 0.45)
            Circle().stroke(OrchardColor.woodDark, lineWidth: 3).frame(width: diameter * 0.72, height: diameter * 0.72)
        }
    }
}

struct GreenhouseArt: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoofShape()
                .fill(Color.white.opacity(0.55))
                .frame(width: 150, height: 54)
                .overlay(RoofShape().stroke(OrchardColor.wood, lineWidth: 4))
                .offset(y: -48)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.38))
                .frame(width: 132, height: 70)
                .overlay(
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle().fill(OrchardColor.wood.opacity(0.8)).frame(width: 3, height: 70)
                        }
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(OrchardColor.wood, lineWidth: 4))
            Text("LAB")
                .font(OrchardFont.title(11))
                .foregroundStyle(OrchardColor.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(OrchardColor.sun, in: Capsule())
                .offset(y: 8)
        }
        .frame(width: 170, height: 150)
        .accessibilityLabel("Lab greenhouse")
    }
}

struct HouseSign: View {
    var progress: HouseProgress

    var body: some View {
        VStack(spacing: 3) {
            Text(progress.tier.title)
                .font(OrchardFont.title(13))
            Text(progress.subtitle)
                .font(OrchardFont.caption(10))
                .multilineTextAlignment(.center)
            ProgressView(value: progress.fraction)
                .tint(OrchardColor.sun)
                .frame(width: 128)
        }
        .foregroundStyle(OrchardColor.cream)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrchardColor.wood, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(OrchardColor.woodDark, lineWidth: 3)
        )
        .frame(width: 168)
    }
}

struct PlantMarker: View {
    var variety: Variety
    var health: PlantHealth

    var body: some View {
        VStack(spacing: 4) {
            plant
                .frame(width: 108, height: 108)
                .scaleEffect(health.scale, anchor: .bottom)
                .rotationEffect(.degrees(Double(health.wilt) * 10), anchor: .bottom)
            label
        }
        .frame(width: 130)
    }

    @ViewBuilder
    private var plant: some View {
        if let image = VarietyArt.plantImage(id: variety.slug) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            procedural
        }
    }

    @ViewBuilder
    private var procedural: some View {
        switch variety.form {
        case .apple, .pear, .mango:
            TreePlant(form: variety.form, skin: variety.fruitSkin, health: health, id: variety.slug)
        case .carrot:
            CarrotPatch(skin: variety.fruitSkin, health: health, id: variety.slug)
        case .grape:
            TrellisPlant(form: .grape, skin: variety.fruitSkin, health: health, id: variety.slug)
        case .tomato:
            TrellisPlant(form: .tomato, skin: variety.fruitSkin, health: health, id: variety.slug)
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            badge
            Text(variety.name)
                .font(OrchardFont.caption(11))
                .foregroundStyle(OrchardColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(OrchardColor.cream, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(stroke, lineWidth: 2)
        )
    }

    private var stroke: Color {
        switch health.badge {
        case .loved: OrchardColor.good
        case .mixed: OrchardColor.mid
        case .disliked: OrchardColor.bad
        }
    }

    private var badge: some View {
        ZStack {
            Circle().fill(stroke)
            Image(systemName: icon)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 14, height: 14)
    }

    private var icon: String {
        switch health.badge {
        case .loved: "checkmark"
        case .mixed: "exclamationmark"
        case .disliked: "xmark"
        }
    }
}

private struct TreePlant: View {
    var form: PlantForm
    var skin: FruitSkin
    var health: PlantHealth
    var id: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(OrchardColor.woodDark)
                .frame(width: 14, height: 36)
                .offset(y: 34)
            canopy(offset: CGSize(width: -18, height: 8), diameter: 48)
            canopy(offset: CGSize(width: 18, height: 10), diameter: 46)
            canopy(offset: CGSize(width: 0, height: -16), diameter: 58)
            fruit.offset(x: -16, y: -6)
            if health.condition != .wilted {
                fruit.offset(x: 14, y: 2)
            }
            if health.condition == .lush {
                fruit.offset(x: 0, y: 16)
            }
        }
    }

    private func canopy(offset: CGSize, diameter: CGFloat) -> some View {
        Circle()
            .fill(leaf)
            .frame(width: diameter, height: diameter * (health.condition == .wilted ? 0.82 : 1))
            .overlay(Circle().stroke(leaf.mixed(with: .black, amount: 0.25), lineWidth: 2))
            .offset(offset)
    }

    private var leaf: Color {
        OrchardColor.leaf.mixed(with: Color(red: 0.45, green: 0.32, blue: 0.12), amount: health.leafDull)
    }

    private var fruit: some View {
        FruitGlyph(id: id, form: form, skin: skin)
            .frame(width: 22, height: 22)
            .opacity(health.condition == .wilted ? 0.75 : 1)
    }
}

private struct CarrotPatch: View {
    var skin: FruitSkin
    var health: PlantHealth
    var id: String

    var body: some View {
        ZStack {
            Ellipse()
                .fill(OrchardColor.soil)
                .frame(width: 96, height: 36)
                .offset(y: 28)
            carrot.offset(x: -24)
            carrot.offset(x: 0, y: 6)
            if health.condition != .wilted {
                carrot.offset(x: 24)
            }
        }
        .opacity(health.condition == .wilted ? 0.8 : 1)
    }

    private var carrot: some View {
        FruitGlyph(id: id, form: .carrot, skin: skin)
            .frame(width: 36, height: 64)
            .saturation(1 - Double(health.leafDull) * 0.6)
    }
}

private struct TrellisPlant: View {
    var form: PlantForm
    var skin: FruitSkin
    var health: PlantHealth
    var id: String

    var body: some View {
        ZStack {
            HStack(spacing: 70) {
                post
                post
            }
            VStack(spacing: 16) {
                wire
                wire
                wire
            }
            .frame(width: 78)
            fruitCluster.offset(x: -18, y: -4)
            if health.condition != .wilted {
                fruitCluster.offset(x: 20, y: 10)
            }
        }
    }

    private var post: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(OrchardColor.wood)
            .frame(width: 8, height: 96)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(OrchardColor.woodDark, lineWidth: 1))
    }

    private var wire: some View {
        Rectangle().fill(OrchardColor.woodDark.opacity(0.7)).frame(height: 2)
    }

    private var fruitCluster: some View {
        FruitGlyph(id: id, form: form, skin: skin)
            .frame(width: form == .tomato ? 28 : 36, height: form == .tomato ? 28 : 40)
            .saturation(1 - Double(health.leafDull) * 0.7)
            .opacity(health.condition == .wilted ? 0.7 : 1)
    }
}
