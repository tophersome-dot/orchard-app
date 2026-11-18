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
    /// Sprites wait until the first frame has committed. The grass itself draws immediately.
    var detailed: Bool

    private var zones: [String: String] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.key, $0.value.zone) })
    }

    private var yardPlan: YardPlan {
        FarmExpansion.plan(records: records, zones: zones)
    }

    private var viewport: FarmViewport {
        FarmViewport.covering(FarmExpansion.boundsTiles(records: records, tastedCount: tastedCount, plan: yardPlan))
    }

    var body: some View {
        let frame = viewport
        let plan = yardPlan
        ZStack {
            Color(red: 0.51, green: 0.63, blue: 0.10)
            grass(in: frame)
            Canvas { context, _ in
                for plot in FarmExpansion.lockedPlots(tastedCount: tastedCount, plan: plan) {
                    context.stroke(
                        plotOutline(plot, viewport: frame),
                        with: .color(Color.white.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                    )
                }
            }
            .allowsHitTesting(false)
            if detailed {
                ForEach(drawables(viewport: frame, plan: plan)) { item in
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
                    .frame(width: IsoMap.tileWidth, height: IsoMap.tileHeight)
                    .position(frame.viewPoint(hover))
            }
        }
        .frame(width: frame.size.width, height: frame.size.height)
    }

    /// Seamless grass, with a few large darker patches. One grass image is about 3.5 tiles across.
    private func grass(in frame: FarmViewport) -> some View {
        Canvas { context, size in
            let pitch = IsoMap.tileWidth * 3.5
            let columns = Int(ceil(size.width / pitch)) + 1
            let rows = Int(ceil(size.height / pitch)) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: pitch, height: pitch)
                    context.draw(Image(FarmSprite.grass), in: rect)
                }
            }
            let patch = pitch * 2
            for tile in [FarmTile(column: -2, row: 3), FarmTile(column: 6, row: 14), FarmTile(column: 12, row: 9)] {
                let center = frame.viewPoint(tile)
                let rect = CGRect(x: center.x - patch / 2, y: center.y - patch / 2, width: patch, height: patch)
                context.drawLayer { layer in
                    layer.opacity = 0.42
                    layer.blendMode = .multiply
                    layer.draw(Image(FarmSprite.grassDark), in: rect)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func plotOutline(_ plot: FarmPlotSpec, viewport: FarmViewport) -> Path {
        let corners = [
            FarmTile(column: plot.columns.lowerBound, row: plot.rows.lowerBound),
            FarmTile(column: plot.columns.upperBound, row: plot.rows.lowerBound),
            FarmTile(column: plot.columns.upperBound, row: plot.rows.upperBound),
            FarmTile(column: plot.columns.lowerBound, row: plot.rows.upperBound)
        ]
        var path = Path()
        for (index, tile) in corners.enumerated() {
            let point = viewport.viewPoint(tile)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawables(viewport: FarmViewport, plan: YardPlan) -> [MapDrawable] {
        var items: [MapDrawable] = []
        let occupied = Set(records.map(\.tile))
        for tile in plan.treeSpots {
            items.append(makeDrawable(id: "soil-tree-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.05, viewport: viewport, visual: .soilTree))
            if !occupied.contains(tile) {
                items.append(makeDrawable(id: "sapling-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.4, viewport: viewport, visual: .sapling))
            }
        }
        for tile in plan.bedSpots where !occupied.contains(tile) {
            items.append(makeDrawable(id: "soil-bed-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile) + 0.05, viewport: viewport, visual: .soilBed))
        }
        for record in records {
            let tile = record.id == dragging ? (hover ?? record.tile) : record.tile
            if record.kind == .plant, let id = record.varietyID, let info = plants[id], FarmExpansion.spotKind(zone: info.zone) == .vine {
                items.append(makeDrawable(id: "soil-vine-\(record.id.uuidString)", tile: tile, depth: depth(tile) + 0.05, viewport: viewport, visual: .soilVine))
            }
            let visual = visual(for: record)
            items.append(makeDrawable(id: record.id.uuidString, tile: tile, depth: depth(tile) + record.kind.depthBias, viewport: viewport, visual: visual))
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

    private func makeDrawable(id: String, tile: FarmTile, depth: Double, viewport: FarmViewport, visual: MapVisual) -> MapDrawable {
        let width = displayWidth(visual)
        let foot = footHeight(visual, width: width)
        return MapDrawable(
            id: id,
            depth: depth,
            point: viewport.viewPoint(tile),
            visual: visual,
            foot: foot,
            anchorsBase: visual.anchorsBase
        )
    }

    /// Trees stand on one tile. Ground decals overlap their tile a little so the pieces read as continuous.
    private func displayWidth(_ visual: MapVisual) -> CGFloat {
        switch visual {
        case .house: IsoMap.tileWidth * 2
        case .tractor: IsoMap.tileWidth * 1.15
        case .fence: fenceWidth
        case .path: IsoMap.tileWidth * 1.12
        case .bush: 46
        case .rock: 40
        case .sapling: 36
        case .soilTree: IsoMap.tileWidth * 1.2
        case .soilVine, .soilBed: IsoMap.tileWidth * 1.08
        case .emptyVine: 0
        case .plant(let info):
            switch FarmExpansion.spotKind(zone: info.zone) {
            case .tree: IsoMap.tileWidth
            case .bed: IsoMap.tileWidth * 1.05
            case .vine: IsoMap.tileWidth * 0.92
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
        let width = displayWidth(item.visual)
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

struct FarmViewport: Equatable {
    var content: CGRect
    var pad: CGFloat = 200

    var size: CGSize {
        CGSize(width: max(content.width, 1) + pad * 2, height: max(content.height, 1) + pad * 2)
    }

    func viewPoint(_ tile: FarmTile) -> CGPoint {
        let center = IsoMap.center(tile)
        return CGPoint(x: center.x - content.minX + pad, y: center.y - content.minY + pad)
    }

    func tile(at viewPoint: CGPoint) -> FarmTile {
        let iso = CGPoint(x: viewPoint.x - pad + content.minX, y: viewPoint.y - pad + content.minY)
        return IsoMap.tile(at: iso)
    }

    static func covering(_ tiles: [FarmTile]) -> FarmViewport {
        let points = tiles.map(IsoMap.center)
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return FarmViewport(content: CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        return FarmViewport(content: CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1)))
    }
}

extension FarmExpansion {
    static func boundsTiles(records: [FarmRecord], tastedCount: Int, plan: YardPlan) -> [FarmTile] {
        var tiles = records.map(\.tile)
        tiles.append(contentsOf: plan.treeSpots + plan.bedSpots + plan.vineSpots)
        tiles.append(contentsOf: plan.fences.map(\.tile))
        for plot in plots(for: plan) {
            tiles.append(FarmTile(column: plot.columns.lowerBound, row: plot.rows.lowerBound))
            tiles.append(FarmTile(column: plot.columns.upperBound, row: plot.rows.lowerBound))
            tiles.append(FarmTile(column: plot.columns.upperBound, row: plot.rows.upperBound))
            tiles.append(FarmTile(column: plot.columns.lowerBound, row: plot.rows.upperBound))
            if tastedCount >= plot.unlockAt {
                tiles.append(contentsOf: plot.treeSpots + plot.bedSpots + plot.vineSpots)
            }
        }
        return tiles
    }
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
