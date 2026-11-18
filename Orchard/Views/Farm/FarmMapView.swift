import SwiftUI

struct FarmPlantInfo {
    var id: String
    var name: String
    var zone: String
    var category: String
    var form: PlantForm
    var skin: FruitSkin
    var rating: Double?
}

struct FarmMapView: View {
    var records: [FarmRecord]
    var plants: [String: FarmPlantInfo]
    var tastedCount: Int
    var hover: FarmTile?
    var hoverValid: Bool
    var dragging: UUID?
    var showsNames: Bool
    /// Sprites wait until the grass frame has committed and the images are decoded.
    var detailed: Bool
    var camera: FarmCamera
    var canvasSize: CGSize

    private var zones: [String: String] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.key, $0.value.zone) })
    }

    private var yardPlan: YardPlan {
        FarmExpansion.plan(records: records, zones: zones)
    }

    var body: some View {
        let plan = yardPlan
        ZStack {
            FarmColor.freshGrass
            grass
            Canvas { context, _ in
                for plot in FarmExpansion.lockedPlots(tastedCount: tastedCount, plan: plan) {
                    context.stroke(
                        plotOutline(plot),
                        with: .color(Color.white.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                    )
                }
            }
            .allowsHitTesting(false)
            if detailed {
                ForEach(drawables(plan: plan)) { item in
                    drawableView(item)
                        .position(
                            x: item.point.x,
                            y: item.anchorsBase ? item.point.y - item.foot / 2 : item.point.y
                        )
                        .zIndex(item.depth)
                }
            }
            if let hover {
                IsoDiamond()
                    .fill((hoverValid ? Color.green : Color.red).opacity(0.35))
                    .frame(width: IsoMap.tileWidth * camera.scale, height: IsoMap.tileHeight * camera.scale)
                    .position(camera.screenPoint(IsoMap.center(hover), in: canvasSize))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    /// One repeating grass fill, phased to the world so panning never reveals an edge.
    /// Tiles overlap by a couple of points so the sampler cannot open a seam.
    private var grass: some View {
        Canvas { context, size in
            let pitch = max(IsoMap.tileWidth * 3.5 * camera.scale, 1)
            let origin = camera.screenPoint(.zero, in: size)
            let bleed: CGFloat = 2
            let resolved = context.resolve(Image(FarmSprite.grass))
            let firstColumn = Int(floor((0 - origin.x) / pitch)) - 1
            let lastColumn = Int(ceil((size.width - origin.x) / pitch)) + 1
            let firstRow = Int(floor((0 - origin.y) / pitch)) - 1
            let lastRow = Int(ceil((size.height - origin.y) / pitch)) + 1
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let rect = CGRect(
                        x: origin.x + CGFloat(column) * pitch - bleed,
                        y: origin.y + CGFloat(row) * pitch - bleed,
                        width: pitch + bleed * 2,
                        height: pitch + bleed * 2
                    )
                    context.draw(resolved, in: rect)
                }
            }
            let fresh = GraphicsContext.Shading.color(FarmColor.freshGrass)
            context.drawLayer { layer in
                layer.blendMode = .color
                layer.opacity = 0.82
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: fresh)
            }
            context.drawLayer { layer in
                layer.blendMode = .softLight
                layer.opacity = 0.4
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.78, green: 0.93, blue: 0.45)))
            }
            let shade = Color(red: 0.22, green: 0.42, blue: 0.08)
            for tile in [FarmTile(column: -6, row: 6), FarmTile(column: 10, row: 16), FarmTile(column: 18, row: 2)] {
                let center = camera.screenPoint(IsoMap.center(tile), in: size)
                let radius = IsoMap.tileWidth * 8 * camera.scale
                let gradient = Gradient(stops: [
                    .init(color: shade.opacity(0.22), location: 0),
                    .init(color: shade.opacity(0.08), location: 0.4),
                    .init(color: shade.opacity(0), location: 1)
                ])
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func plotOutline(_ plot: FarmPlotSpec) -> Path {
        let corners = [
            FarmTile(column: plot.columns.lowerBound, row: plot.rows.lowerBound),
            FarmTile(column: plot.columns.upperBound, row: plot.rows.lowerBound),
            FarmTile(column: plot.columns.upperBound, row: plot.rows.upperBound),
            FarmTile(column: plot.columns.lowerBound, row: plot.rows.upperBound)
        ]
        var path = Path()
        for (index, tile) in corners.enumerated() {
            let point = camera.screenPoint(IsoMap.center(tile), in: canvasSize)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawables(plan: YardPlan) -> [MapDrawable] {
        var items: [MapDrawable] = []
        let occupied = Set(records.map(\.tile))
        for tile in plan.treeSpots {
            items.append(makeDrawable(id: "soil-tree-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.05, visual: .soilTree))
            if !occupied.contains(tile) {
                items.append(makeDrawable(id: "sapling-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.4, visual: .sapling))
            }
        }
        for tile in plan.bedSpots where !occupied.contains(tile) {
            items.append(makeDrawable(id: "soil-bed-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.05, visual: .soilBed))
        }
        for record in records {
            let tile = record.id == dragging ? (hover ?? record.tile) : record.tile
            if record.kind == .plant, let id = record.varietyID, let info = plants[id], FarmExpansion.spotKind(zone: info.zone) == .vine {
                items.append(makeDrawable(id: "soil-vine-\(record.id.uuidString)", tile: tile, depth: depth(tile) + 0.05, visual: .soilVine))
            }
            let visual = visual(for: record)
            items.append(makeDrawable(id: record.id.uuidString, tile: tile, depth: depth(tile) + record.kind.depthBias, visual: visual))
        }
        return items.sorted { $0.depth < $1.depth }
    }

    /// Painter's order: smaller column+row is farther up the screen and draws first.
    private func depth(_ tile: FarmTile) -> Double {
        Double(tile.column + tile.row)
    }

    private func visual(for record: FarmRecord) -> MapVisual {
        switch record.kind {
        case .house:
            return .house(HouseRules.progress(for: tastedCount).tier)
        case .tractor:
            return .tractor
        case .fence:
            return .fence(alongColumn: record.varietyID == FarmSprite.fenceSide)
        case .path:
            return .path
        case .bush:
            return .bush
        case .rock:
            return .rock
        case .plant:
            guard let id = record.varietyID, let info = plants[id] else { return .sapling }
            return .plant(info)
        }
    }

    private func makeDrawable(id: String, tile: FarmTile, depth: Double, visual: MapVisual) -> MapDrawable {
        let width = worldWidth(visual) * camera.scale
        let foot = footHeight(visual, width: width)
        return MapDrawable(
            id: id,
            depth: depth,
            point: camera.screenPoint(IsoMap.center(tile), in: canvasSize),
            visual: visual,
            width: width,
            foot: foot,
            anchorsBase: visual.anchorsBase
        )
    }

    /// Sprite widths in world points, before the camera zoom. One tile is `IsoMap.tileWidth`.
    private func worldWidth(_ visual: MapVisual) -> CGFloat {
        let tile = IsoMap.tileWidth
        switch visual {
        case .house: tile * 2
        case .tractor: tile
        case .fence: fenceWidth
        case .path: tile * 1.04
        case .bush: tile * 0.55
        case .rock: tile * 0.48
        case .sapling: tile * 0.43
        case .soilTree: tile * 1.2
        case .soilVine, .soilBed: tile
        case .emptyVine: 0
        case .plant(let info):
            switch FarmExpansion.spotKind(zone: info.zone) {
            case .tree, .bed, .vine: tile
            }
        }
    }

    /// Long enough that neighbouring pickets overlap into one run.
    private var fenceWidth: CGFloat {
        let step = hypot(IsoMap.tileWidth / 2, IsoMap.tileHeight / 2)
        let artDiagonal = hypot(600.0, 561.0) / 600.0
        return step * 1.7 / artDiagonal
    }

    private func footHeight(_ visual: MapVisual, width: CGFloat) -> CGFloat {
        if let name = spriteName(visual), let aspect = FarmSprite.aspect(named: name) {
            return width * aspect
        }
        return switch visual {
        case .house: IsoMap.tileWidth * 1.4
        case .tractor: IsoMap.tileWidth * 0.9
        case .fence: 36
        case .path: IsoMap.tileHeight
        case .bush: 32
        case .rock: 28
        case .sapling: 48
        case .soilTree, .soilVine, .soilBed: IsoMap.tileHeight
        case .emptyVine: 0
        case .plant: IsoMap.tileWidth
        }
    }

    private func spriteName(_ visual: MapVisual) -> String? {
        switch visual {
        case .house(let tier): FarmSprite.house(tier)
        case .tractor: FarmSprite.tractor
        case .fence: FarmSprite.fence
        case .path: FarmSprite.stonePath
        case .bush: FarmSprite.bush
        case .rock: FarmSprite.rock
        case .sapling: FarmSprite.sapling
        case .soilTree: FarmSprite.soilTree
        case .soilVine: FarmSprite.soilVine
        case .soilBed: FarmSprite.emptyBed
        case .plant(let info):
            FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating)
        case .emptyVine:
            nil
        }
    }

    @ViewBuilder
    private func drawableView(_ item: MapDrawable) -> some View {
        let width = item.width
        switch item.visual {
        case .house(let tier):
            sprite(FarmSprite.house(tier), width: width, fallbackHeight: item.foot) {
                FarmhouseArt(tier: tier)
            }
        case .tractor:
            sprite(FarmSprite.tractor, width: width, fallbackHeight: item.foot) {
                TractorArt()
            }
        case .fence(let alongColumn):
            sprite(FarmSprite.fence, width: width, fallbackHeight: item.foot) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(white: 0.75), lineWidth: 1))
            }
            .scaleEffect(x: alongColumn ? -1 : 1, y: 1)
            .rotationEffect(.radians(fenceAngle(alongColumn: alongColumn)))
        case .path:
            sprite(FarmSprite.stonePath, width: width, fallbackHeight: item.foot) {
                IsoDiamond().fill(Color(red: 0.76, green: 0.73, blue: 0.64))
            }
        case .bush:
            sprite(FarmSprite.bush, width: width, fallbackHeight: item.foot) {
                Ellipse().fill(OrchardColor.grassDark)
            }
        case .rock:
            sprite(FarmSprite.rock, width: width, fallbackHeight: item.foot) {
                Ellipse().fill(Color(white: 0.75))
            }
        case .sapling:
            sprite(FarmSprite.sapling, width: width, fallbackHeight: item.foot) {
                Capsule().fill(OrchardColor.leaf)
            }
        case .soilTree:
            sprite(FarmSprite.soilTree, width: width, fallbackHeight: item.foot) {
                Ellipse().fill(OrchardColor.soil)
            }
        case .soilVine:
            sprite(FarmSprite.soilVine, width: width, fallbackHeight: item.foot) {
                Ellipse().fill(OrchardColor.soil)
            }
        case .soilBed:
            sprite(FarmSprite.emptyBed, width: width, fallbackHeight: item.foot) {
                IsoDiamond().fill(OrchardColor.soil)
            }
        case .emptyVine:
            EmptyView()
        case .plant(let info):
            plantView(info, width: width, foot: item.foot)
        }
    }

    /// The picket art runs steeper than an iso edge. Rotate it onto the grid, and mirror it for the other side.
    private func fenceAngle(alongColumn: Bool) -> Double {
        let grid = atan2(Double(IsoMap.tileHeight), Double(IsoMap.tileWidth))
        let artwork = atan2(561.0, 600.0)
        let alongRow = grid - artwork
        return alongColumn ? -alongRow : alongRow
    }

    private func plantView(_ info: FarmPlantInfo, width: CGFloat, foot: CGFloat) -> some View {
        let name = FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating)
        let scale = FarmSprite.scale(for: info.rating)
        let grounded = FarmExpansion.spotKind(zone: info.zone) == .bed
        return sprite(name, width: width, fallbackHeight: foot) {
            fallbackPlant(info)
        }
        .scaleEffect(scale, anchor: grounded ? .center : .bottom)
        .overlay(alignment: .bottom) {
            if showsNames {
                Text(info.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OrchardColor.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .fixedSize()
                    .offset(y: 16)
            }
        }
    }

    @ViewBuilder
    private func fallbackPlant(_ info: FarmPlantInfo) -> some View {
        VStack(spacing: 0) {
            FruitGlyph(id: info.id, form: info.form, skin: info.skin)
                .frame(width: 36, height: 36)
            Ellipse()
                .fill(info.zone == "bed" ? OrchardColor.soil : OrchardColor.grassDark)
                .frame(width: 54, height: 22)
        }
        .opacity(FarmSprite.usesWiltingTree(zone: info.zone, rating: info.rating) ? 0.75 : 1)
    }

    @ViewBuilder
    private func sprite<Fallback: View>(_ name: String, width: CGFloat, fallbackHeight: CGFloat, @ViewBuilder fallback: () -> Fallback) -> some View {
        if let image = FarmSprite.image(named: name), image.size.width > 0 {
            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .frame(width: width, height: width * image.size.height / image.size.width)
        } else {
            fallback()
                .frame(width: width, height: fallbackHeight, alignment: .bottom)
        }
    }
}

private struct MapDrawable: Identifiable {
    var id: String
    var depth: Double
    var point: CGPoint
    var visual: MapVisual
    /// On-screen width. Already multiplied by the camera zoom, same as `point`.
    var width: CGFloat
    /// Height of the sprite whose base sits on the tile centre.
    var foot: CGFloat
    var anchorsBase: Bool
}

private enum MapVisual {
    case house(HouseTier)
    case tractor
    case fence(alongColumn: Bool)
    case path
    case bush
    case rock
    case sapling
    case soilTree
    case soilVine
    case soilBed
    case emptyVine
    case plant(FarmPlantInfo)

    var anchorsBase: Bool {
        switch self {
        case .path, .soilTree, .soilVine, .soilBed, .fence:
            return false
        case .plant(let info):
            return FarmExpansion.spotKind(zone: info.zone) != .bed
        default:
            return true
        }
    }
}

private extension FarmItemKind {
    var depthBias: Double {
        switch self {
        case .path: 0.1
        case .fence: 0.2
        case .bush, .rock: 0.3
        case .plant: 0.4
        case .tractor: 0.5
        case .house: 0.6
        }
    }
}

/// World point kept under the middle of the screen, plus a finger-pan in screen points.
struct FarmCamera: Equatable {
    var scale: CGFloat = 1
    var center: CGPoint = .zero
    var pan: CGSize = .zero

    func screenPoint(_ world: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + pan.width + (world.x - center.x) * scale,
            y: size.height / 2 + pan.height + (world.y - center.y) * scale
        )
    }

    func worldPoint(_ screen: CGPoint, in size: CGSize) -> CGPoint {
        let safe = max(scale, 0.05)
        return CGPoint(
            x: center.x + (screen.x - size.width / 2 - pan.width) / safe,
            y: center.y + (screen.y - size.height / 2 - pan.height) / safe
        )
    }
}

enum FarmColor {
    /// Fresh lawn green, close to #7BC043.
    static let freshGrass = Color(red: 0.482, green: 0.753, blue: 0.263)
}

struct IsoDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
