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
    /// Painted cells. Grass is every cell that is absent.
    var terrain: [FarmTile: FarmItemKind]
    var hoverTiles: [FarmTile]

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
            Canvas { context, size in
                drawTerrains(in: context, size: size)
            }
            .allowsHitTesting(false)
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
            if !hoverTiles.isEmpty {
                let tint = (hoverValid ? Color.green : Color.red).opacity(0.35)
                ForEach(Array(hoverTiles.enumerated()), id: \.offset) { _, tile in
                    IsoDiamond()
                        .fill(tint)
                        .frame(width: IsoMap.tileWidth * camera.scale, height: IsoMap.tileHeight * camera.scale)
                        .position(camera.screenPoint(IsoMap.center(tile), in: canvasSize))
                }
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
            items.append(makeDrawable(id: "soil-tree-\(tile.column)-\(tile.row)", tile: tile, depth: IsoMap.center(tile).y + 0.05, visual: .soilTree))
            if !occupied.contains(tile) {
                items.append(makeDrawable(id: "sapling-\(tile.column)-\(tile.row)", tile: tile, depth: IsoMap.center(tile).y + 0.4, visual: .sapling))
            }
        }
        for record in records {
            let tile = record.id == dragging ? (hover ?? record.tile) : record.tile
            if record.kind.isTerrain || record.kind == .fence { continue }
            if record.kind == .plant, let id = record.varietyID, let info = plants[id] {
                let spot = FarmExpansion.spotKind(zone: info.zone)
                if spot == .bed || spot == .vine {
                    items.append(makeCrop(info, tile: tile, id: record.id.uuidString))
                    continue
                }
            }
            let visual = visual(for: record)
            items.append(makeDrawable(id: record.id.uuidString, tile: tile, depth: IsoMap.center(tile).y + record.kind.depthBias, visual: visual))
        }
        let edges = FarmSurface.fenceEdges(in: draggedRecords)
        for (index, edge) in edges.enumerated() {
            items.append(makeRail(index: index, edge: edge))
        }
        for (index, post) in FarmSurface.fencePosts(on: edges).enumerated() {
            items.append(makePost(index: index, world: post))
        }
        return items.sorted { $0.depth < $1.depth }
    }

    /// Fence and path drags already live in `records` when the screen passes the preview.
    private var draggedRecords: [FarmRecord] {
        records.map { record in
            guard record.id == dragging, let hover else { return record }
            var moved = record
            moved.tile = hover
            return moved
        }
    }

    private func visual(for record: FarmRecord) -> MapVisual {
        switch record.kind {
        case .house:
            return .house(HouseRules.progress(for: tastedCount).tier)
        case .tractor:
            return .tractor
        case .bush:
            return .bush
        case .rock:
            return .rock
        case .plant:
            guard let id = record.varietyID, let info = plants[id] else { return .sapling }
            return .plant(info)
        case .fence, .path, .dirt, .sand, .longgrass, .tilled:
            return .bush
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
        return switch visual {
        case .house: tile * 2
        case .tractor: tile
        case .bush: tile * 0.55
        case .rock: tile * 0.48
        case .sapling: tile * 0.43
        case .soilTree: tile
        case .soilVine, .soilBed: tile
        case .rail, .post: tile
        case .emptyVine: 0
        case .plant(let info):
            switch FarmExpansion.spotKind(zone: info.zone) {
            case .tree, .bed, .vine: tile
            }
        }
    }

    private func footHeight(_ visual: MapVisual, width: CGFloat) -> CGFloat {
        if let name = spriteName(visual), let aspect = FarmSprite.aspect(named: name) {
            return width * aspect
        }
        return switch visual {
        case .house: IsoMap.tileWidth * 1.4
        case .tractor: IsoMap.tileWidth * 0.9
        case .bush: 32
        case .rock: 28
        case .sapling: 48
        case .soilTree, .soilVine, .soilBed: IsoMap.tileHeight
        case .rail, .post: width
        case .emptyVine: 0
        case .plant: IsoMap.tileWidth
        }
    }

    private func spriteName(_ visual: MapVisual) -> String? {
        switch visual {
        case .house(let tier): FarmSprite.house(tier)
        case .tractor: FarmSprite.tractor
        case .bush: FarmSprite.bush
        case .rock: FarmSprite.rock
        case .sapling: FarmSprite.sapling
        case .soilTree: FarmSprite.soilTree
        case .soilVine: FarmSprite.soilVine
        case .soilBed: FarmSprite.emptyBed
        case .rail(let northEast): northEast ? FarmSprite.fenceRailNE : FarmSprite.fenceRailNW
        case .post: FarmSprite.fencePost
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
        case .rail(let northEast):
            sprite(northEast ? FarmSprite.fenceRailNE : FarmSprite.fenceRailNW, width: width, fallbackHeight: item.foot) {
                Capsule().fill(Color.white)
            }
        case .post:
            sprite(FarmSprite.fencePost, width: width, fallbackHeight: item.foot) {
                Capsule().fill(Color.white)
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
            if FarmExpansion.spotKind(zone: info.zone) == .tree {
                plantView(info, width: width, foot: item.foot)
            } else {
                sprite(FarmSprite.plantName(zone: info.zone, category: info.category, varietyID: info.id, rating: info.rating), width: width, fallbackHeight: item.foot) {
                    fallbackPlant(info)
                }
            }
        }
    }

    /// App-size fence art is authored on a 128pt tile. Scale that to our 84pt tile, then by the camera.
    private var fencePixelScale: CGFloat {
        (IsoMap.tileWidth / 128) * camera.scale
    }

    private func makeCrop(_ info: FarmPlantInfo, tile: FarmTile, id: String) -> MapDrawable {
        let spot = FarmExpansion.spotKind(zone: info.zone)
        let stamp = spot == .vine ? FarmSprite.arborAnchor(varietyID: info.id) : FarmSprite.cropAnchor(varietyID: info.id)
        let tileWidth = IsoMap.tileWidth * (spot == .vine ? 1 : 0.85) * camera.scale
        let name = spot == .vine ? FarmSprite.arbor(varietyID: info.id) : FarmSprite.crop(varietyID: info.id)
        return makeAnchored(
            id: "crop-\(id)",
            name: name,
            imageSize: stamp.size,
            anchor: stamp.anchor,
            displayWidth: tileWidth,
            ground: IsoMap.center(tile),
            visual: .plant(info),
            depth: IsoMap.center(tile).y + 0.45
        )
    }

    private func makeAnchored(
        id: String,
        name: String,
        imageSize: CGSize,
        anchor: CGPoint,
        displayWidth: CGFloat,
        ground: CGPoint,
        visual: MapVisual,
        depth: Double
    ) -> MapDrawable {
        let scale = imageSize.width > 0 ? displayWidth / imageSize.width : 1
        let display = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let anchorPoint = CGPoint(x: anchor.x * scale, y: anchor.y * scale)
        let screen = camera.screenPoint(ground, in: canvasSize)
        let center = CGPoint(
            x: screen.x - anchorPoint.x + display.width / 2,
            y: screen.y - anchorPoint.y + display.height / 2
        )
        return MapDrawable(
            id: id,
            depth: depth,
            point: center,
            visual: visual,
            width: display.width,
            foot: display.height,
            anchorsBase: false
        )
    }

    private func makeRail(index: Int, edge: FarmGridEdge) -> MapDrawable {
        let art = edge.runsNorthEast ? FenceStamp.railNE : FenceStamp.railNW
        return stamp(
            id: "rail-\(index)",
            art: art,
            ground: edge.anchor,
            visual: .rail(northEast: edge.runsNorthEast),
            depth: edge.groundY + 0.2
        )
    }

    private func makePost(index: Int, world: CGPoint) -> MapDrawable {
        stamp(
            id: "post-\(index)",
            art: FenceStamp.post,
            ground: world,
            visual: .post,
            depth: world.y + 0.35
        )
    }

    private func stamp(id: String, art: FenceStamp, ground: CGPoint, visual: MapVisual, depth: Double) -> MapDrawable {
        let scale = fencePixelScale
        let display = CGSize(width: art.size.width * scale, height: art.size.height * scale)
        let anchor = CGPoint(x: art.anchor.x * scale, y: art.anchor.y * scale)
        let screen = camera.screenPoint(ground, in: canvasSize)
        let center = CGPoint(
            x: screen.x - anchor.x + display.width / 2,
            y: screen.y - anchor.y + display.height / 2
        )
        return MapDrawable(
            id: id,
            depth: depth,
            point: center,
            visual: visual,
            width: display.width,
            foot: display.height,
            anchorsBase: false
        )
    }

    private func drawTerrains(in context: GraphicsContext, size: CGSize) {
        let order: [FarmItemKind] = [.path, .dirt, .sand, .longgrass, .tilled]
        var fills: [(FarmItemKind, Set<FarmTile>)] = []
        for kind in order {
            let tiles = Set(terrain.compactMap { tile, painted in painted == kind ? tile : nil })
            if !tiles.isEmpty {
                fills.append((kind, tiles))
            }
        }
        for (kind, tiles) in fills {
            guard let name = FarmSprite.terrainFill(kind) else { continue }
            let union = diamondUnion(tiles, in: size)
            let resolved = context.resolve(Image(name))
            context.drawLayer { layer in
                layer.clip(to: union, style: FillStyle(eoFill: false))
                let pixelsPerCell: CGFloat = kind == .tilled ? 128 : 256
                drawWarped(resolved, layer: &layer, size: size, pixelsPerCell: pixelsPerCell)
            }
        }
        for (kind, tiles) in fills {
            guard let name = FarmSprite.terrainEdge(kind) else { continue }
            let resolved = context.resolve(Image(name))
            for boundary in FarmSurface.boundaryEdges(of: tiles) {
                drawEdgeStrip(resolved, edge: boundary.edge, owner: boundary.outwardFrom, kind: kind, in: context, size: size)
            }
        }
    }

    /// One path for the whole group. Each diamond is grown by half a point so the anti-aliased edges overlap and no seam shows between cells.
    private func diamondUnion(_ tiles: Set<FarmTile>, in size: CGSize) -> Path {
        var union = Path()
        let halfWidth = IsoMap.halfWidth * camera.scale + 0.5
        let halfHeight = IsoMap.halfHeight * camera.scale + 0.5
        for tile in tiles {
            let center = camera.screenPoint(IsoMap.center(tile), in: size)
            union.move(to: CGPoint(x: center.x, y: center.y - halfHeight))
            union.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
            union.addLine(to: CGPoint(x: center.x, y: center.y + halfHeight))
            union.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y))
            union.closeSubpath()
        }
        return union
    }

    /// One texture covers several cells, in world space, so its wrap does not sit on every cell edge.
    /// Tilled soil is 128 app pixels per cell (four furrows). The other grounds are 256.
    private func drawWarped(_ image: GraphicsContext.ResolvedImage, layer: inout GraphicsContext, size: CGSize, pixelsPerCell: CGFloat) {
        let tile = IsoMap.tileWidth
        let zoom = camera.scale
        let span: CGFloat = 512
        let a = zoom * (tile / 2) / pixelsPerCell
        let b = zoom * (tile / 4) / pixelsPerCell
        let transform = CGAffineTransform(
            a: a, b: b,
            c: -a, d: b,
            tx: size.width / 2 + camera.pan.width - camera.center.x * zoom,
            ty: size.height / 2 + camera.pan.height - camera.center.y * zoom
        )
        let inverse = transform.inverted()
        let corners = [
            CGPoint.zero,
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ].map { $0.applying(inverse) }
        let bleed: CGFloat = 2
        let minX = (corners.map(\.x).min() ?? 0) - span
        let maxX = (corners.map(\.x).max() ?? 0) + span
        let minY = (corners.map(\.y).min() ?? 0) - span
        let maxY = (corners.map(\.y).max() ?? 0) + span
        let firstColumn = Int(floor(minX / span))
        let lastColumn = Int(ceil(maxX / span))
        let firstRow = Int(floor(minY / span))
        let lastRow = Int(ceil(maxY / span))
        layer.concatenate(transform)
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                layer.draw(
                    image,
                    in: CGRect(
                        x: CGFloat(column) * span - bleed,
                        y: CGFloat(row) * span - bleed,
                        width: span + bleed * 2,
                        height: span + bleed * 2
                    )
                )
            }
        }
    }

    private func drawEdgeStrip(
        _ image: GraphicsContext.ResolvedImage,
        edge: FarmGridEdge,
        owner: FarmTile,
        kind: FarmItemKind,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let start = camera.screenPoint(edge.anchor, in: size)
        let finish = camera.screenPoint(edge.end, in: size)
        let dx = finish.x - start.x
        let dy = finish.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let along = CGPoint(x: dx / length, y: dy / length)
        var outward = CGPoint(x: -along.y, y: along.x)
        let middle = CGPoint(x: (start.x + finish.x) / 2, y: (start.y + finish.y) / 2)
        let center = camera.screenPoint(IsoMap.center(owner), in: size)
        let toward = CGPoint(x: center.x - middle.x, y: center.y - middle.y)
        if outward.x * toward.x + outward.y * toward.y > 0 {
            outward = CGPoint(x: -outward.x, y: -outward.y)
        }
        let fraction: CGFloat = kind == .longgrass ? 0.18 : 0.12
        let height = IsoMap.tileWidth * fraction * camera.scale
        let origin = CGPoint(x: start.x + outward.x * height, y: start.y + outward.y * height)
        let transform = CGAffineTransform(
            a: along.x, b: along.y,
            c: -outward.x, d: -outward.y,
            tx: origin.x, ty: origin.y
        )
        context.drawLayer { layer in
            layer.concatenate(transform)
            layer.draw(image, in: CGRect(x: 0, y: 0, width: length, height: height))
            layer.blendMode = .destinationIn
            let fade = Gradient(stops: [
                .init(color: Color.white.opacity(0.15), location: 0),
                .init(color: Color.white.opacity(0.85), location: 0.55),
                .init(color: Color.white, location: 1)
            ])
            layer.fill(
                Path(CGRect(x: 0, y: 0, width: length, height: height)),
                with: .linearGradient(fade, startPoint: CGPoint(x: length / 2, y: 0), endPoint: CGPoint(x: length / 2, y: height))
            )
        }
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
    case rail(northEast: Bool)
    case post
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
        case .soilTree, .soilVine, .soilBed, .rail, .post:
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
        case .path, .dirt, .sand, .longgrass, .tilled: 0.1
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

struct FenceStamp {
    var size: CGSize
    var anchor: CGPoint

    /// Half-size app art. Anchors are the post's ground point inside the PNG.
    static let post = FenceStamp(size: CGSize(width: 20, height: 44), anchor: CGPoint(x: 10, y: 41))
    static let railNE = FenceStamp(size: CGSize(width: 82, height: 75), anchor: CGPoint(x: 9, y: 72))
    static let railNW = FenceStamp(size: CGSize(width: 82, height: 75), anchor: CGPoint(x: 73, y: 72))
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
