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

    private var viewport: FarmViewport {
        FarmViewport.covering(FarmExpansion.boundsTiles(records: records, tastedCount: tastedCount))
    }

    var body: some View {
        let frame = viewport
        ZStack {
            Color(red: 0.55, green: 0.78, blue: 0.34)
            Canvas { context, _ in
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
                    .position(item.point)
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
                items.append(MapDrawable(id: "sapling-\(tile.column)-\(tile.row)", depth: depth(tile), point: viewport.viewPoint(tile), visual: .sapling))
            }
            for tile in plot.bedSpots where !occupied.contains(tile) {
                items.append(MapDrawable(id: "bed-\(tile.column)-\(tile.row)", depth: depth(tile), point: viewport.viewPoint(tile), visual: .emptyBed))
            }
            for tile in plot.vineSpots where !occupied.contains(tile) {
                items.append(MapDrawable(id: "vine-\(tile.column)-\(tile.row)", depth: depth(tile) - 0.1, point: viewport.viewPoint(tile), visual: .emptyVine))
            }
        }
        for record in records {
            let tile = record.id == dragging ? (hover ?? record.tile) : record.tile
            let point = viewport.viewPoint(tile)
            items.append(MapDrawable(id: record.id.uuidString, depth: depth(tile) + record.kind.depthBias, point: point, visual: visual(for: record)))
        }
        return items.sorted { $0.depth < $1.depth }
    }

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

    @ViewBuilder
    private func drawableView(_ item: MapDrawable) -> some View {
        switch item.visual {
        case .house(let tier):
            sprite(FarmSprite.house(tier), width: 150, height: 130) {
                FarmhouseArt(tier: tier).frame(width: 120, height: 100)
            }
        case .tractor:
            sprite(FarmSprite.tractor, width: 120, height: 84) {
                TractorArt().frame(width: 100, height: 70)
            }
        case .fence:
            sprite(FarmSprite.fence, width: 78, height: 58) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 46, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(white: 0.75), lineWidth: 1))
            }
        case .path:
            IsoDiamond()
                .fill(OrchardColor.path)
                .overlay(IsoDiamond().stroke(OrchardColor.pathEdge, lineWidth: 1))
                .frame(width: IsoMap.tileWidth * 0.92, height: IsoMap.tileHeight * 0.92)
        case .bush:
            sprite(FarmSprite.bush, width: 64, height: 52) {
                Ellipse().fill(OrchardColor.grassDark).frame(width: 46, height: 28)
            }
        case .rock:
            sprite(FarmSprite.rock, width: 48, height: 36) {
                Ellipse().fill(Color(white: 0.75)).frame(width: 34, height: 22)
            }
        case .sapling:
            sprite(FarmSprite.sapling, width: 54, height: 64) {
                Capsule().fill(OrchardColor.leaf).frame(width: 16, height: 28)
            }
        case .emptyBed:
            sprite(FarmSprite.emptyBed, width: 86, height: 58) {
                IsoDiamond()
                    .fill(OrchardColor.soil)
                    .frame(width: 70, height: 36)
            }
        case .emptyVine:
            RoundedRectangle(cornerRadius: 2)
                .fill(OrchardColor.wood)
                .frame(width: 8, height: 36)
        case .plant(let info):
            plantView(info)
        }
    }

    private func plantView(_ info: FarmPlantInfo) -> some View {
        let name = FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating)
        let scale = FarmSprite.scale(for: info.rating)
        return VStack(spacing: 2) {
            sprite(name, width: 96, height: 110) {
                fallbackPlant(info)
            }
            .scaleEffect(scale, anchor: .bottom)
            Text(info.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OrchardColor.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
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

    private func sprite<Fallback: View>(_ name: String, width: CGFloat, height: CGFloat, @ViewBuilder fallback: () -> Fallback) -> some View {
        Group {
            if let image = FarmSprite.image(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback()
            }
        }
        .frame(width: width, height: height)
    }
}

private struct MapDrawable: Identifiable {
    var id: String
    var depth: Double
    var point: CGPoint
    var visual: MapVisual
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
