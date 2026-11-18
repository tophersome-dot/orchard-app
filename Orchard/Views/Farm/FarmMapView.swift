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

    private var viewport: FarmViewport {
        FarmViewport.covering(FarmExpansion.boundsTiles(records: records, tastedCount: tastedCount))
    }

    var body: some View {
        let frame = viewport
        ZStack {
            Color(red: 0.55, green: 0.78, blue: 0.34)
            Canvas { context, _ in
                let shade = Color(red: 0.42, green: 0.66, blue: 0.24).opacity(0.45)
                for column in -1...22 {
                    for row in -1...20 where (column + row).isMultiple(of: 2) {
                        context.fill(diamond(at: frame.viewPoint(FarmTile(column: column, row: row))), with: .color(shade))
                    }
                }
                for plot in FarmExpansion.lockedPlots(tastedCount: tastedCount) {
                    context.stroke(
                        plotOutline(plot, viewport: frame),
                        with: .color(Color.white.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                    )
                }
            }
            .allowsHitTesting(false)
            ForEach(drawables(viewport: frame)) { item in
                drawableView(item)
                    .position(
                        x: item.point.x,
                        y: item.anchorsBase ? item.point.y - item.foot / 2 : item.point.y
                    )
                    .zIndex(item.depth)
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

    private func diamond(at point: CGPoint) -> Path {
        let halfWidth = IsoMap.tileWidth / 2
        let halfHeight = IsoMap.tileHeight / 2
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - halfHeight))
        path.addLine(to: CGPoint(x: point.x + halfWidth, y: point.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y + halfHeight))
        path.addLine(to: CGPoint(x: point.x - halfWidth, y: point.y))
        path.closeSubpath()
        return path
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

    private func drawables(viewport: FarmViewport) -> [MapDrawable] {
        var items: [MapDrawable] = []
        let occupied = Set(records.map(\.tile))
        for plot in FarmExpansion.unlockedPlots(tastedCount: tastedCount) {
            for tile in plot.treeSpots where !occupied.contains(tile) {
                items.append(makeDrawable(id: "sapling-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile), viewport: viewport, visual: .sapling))
            }
            for tile in plot.bedSpots where !occupied.contains(tile) {
                items.append(makeDrawable(id: "bed-\(tile.column)-\(tile.row)", tile: tile, depth: depth(tile), viewport: viewport, visual: .emptyBed))
            }
        }
        for record in records {
            let tile = record.id == dragging ? (hover ?? record.tile) : record.tile
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
            return .fence
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

    /// One tree, bed, or vine matches one tile. The house footprint is two tiles across.
    private func displayWidth(_ visual: MapVisual) -> CGFloat {
        switch visual {
        case .house: IsoMap.tileWidth * 2
        case .tractor: IsoMap.tileWidth
        case .fence: 52
        case .path: IsoMap.tileWidth * 0.96
        case .bush: 46
        case .rock: 40
        case .sapling: 32
        case .emptyBed: IsoMap.tileWidth
        case .emptyVine: 0
        case .plant(let info):
            switch FarmExpansion.spotKind(zone: info.zone) {
            case .tree: IsoMap.tileWidth
            case .bed: IsoMap.tileWidth
            case .vine: IsoMap.tileWidth * 0.92
            }
        }
    }

    private func footHeight(_ visual: MapVisual, width: CGFloat) -> CGFloat {
        if let name = spriteName(visual), let image = FarmSprite.image(named: name), image.size.width > 0 {
            return width * image.size.height / image.size.width
        }
        return switch visual {
        case .house: IsoMap.tileWidth * 1.4
        case .tractor: IsoMap.tileWidth * 0.9
        case .fence: 36
        case .path: IsoMap.tileHeight * 0.96
        case .bush: 32
        case .rock: 28
        case .sapling: 48
        case .emptyBed: IsoMap.tileHeight
        case .emptyVine: 0
        case .plant: IsoMap.tileWidth
        }
    }

    private func spriteName(_ visual: MapVisual) -> String? {
        switch visual {
        case .house(let tier): FarmSprite.house(tier)
        case .tractor: FarmSprite.tractor
        case .fence: FarmSprite.fence
        case .bush: FarmSprite.bush
        case .rock: FarmSprite.rock
        case .sapling: FarmSprite.sapling
        case .emptyBed: FarmSprite.emptyBed
        case .plant(let info):
            FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating)
        case .path, .emptyVine:
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
        case .fence:
            sprite(FarmSprite.fence, width: width, fallbackHeight: item.foot) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(white: 0.75), lineWidth: 1))
            }
        case .path:
            IsoDiamond()
                .fill(Color(red: 0.76, green: 0.73, blue: 0.64))
                .overlay(IsoDiamond().stroke(Color(red: 0.62, green: 0.58, blue: 0.50), lineWidth: 1))
                .frame(width: width, height: item.foot)
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
        case .emptyBed:
            sprite(FarmSprite.emptyBed, width: width, fallbackHeight: item.foot) {
                IsoDiamond().fill(OrchardColor.soil)
            }
        case .emptyVine:
            EmptyView()
        case .plant(let info):
            plantView(info, width: width, foot: item.foot)
        }
    }

    private func plantView(_ info: FarmPlantInfo, width: CGFloat, foot: CGFloat) -> some View {
        let name = FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating)
        let scale = FarmSprite.scale(for: info.rating)
        return sprite(name, width: width, fallbackHeight: foot) {
            fallbackPlant(info)
        }
        .scaleEffect(scale, anchor: .bottom)
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
                .interpolation(.high)
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
    case fence
    case path
    case bush
    case rock
    case sapling
    case emptyBed
    case emptyVine
    case plant(FarmPlantInfo)

    var anchorsBase: Bool {
        if case .path = self { return false }
        return true
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
    var pad: CGFloat = 160

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
    static func boundsTiles(records: [FarmRecord], tastedCount: Int) -> [FarmTile] {
        var tiles = records.map(\.tile)
        for plot in plots {
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
