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
    /// 0 hides variety names. Values in between fade them in.
    var labelOpacity: Double = 1
    /// Sprites wait until the grass frame has committed and the images are decoded.
    var detailed: Bool
    var camera: FarmCamera
    var canvasSize: CGSize
    /// Painted cells. Grass is every dry cell that is absent.
    var terrain: [FarmTile: FarmItemKind]
    var hoverTiles: [FarmTile]
    var decor: [DecorRecord] = []
    var chart: IslandChart = .placeholder
    var shoreSeed: UInt64 = 1
    @State private var terrainCache = TerrainDrawCache()
    @State private var shoreCache = ShoreLoopCache()

    private var zones: [String: String] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.key, $0.value.zone) })
    }

    private var yardPlan: YardPlan {
        FarmExpansion.plan(records: records, zones: zones)
    }

    var body: some View {
        let plan = yardPlan
        ZStack {
            FarmColor.ocean
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                Canvas { context, size in
                    let drift = shoreDrift(at: timeline.date)
                    drawWater(in: &context, size: size, drift: drift)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(false)
            }
            grass
            Canvas { context, size in
                drawTerrains(in: context, size: size)
                drawBanks(in: context, size: size)
            }
            .allowsHitTesting(false)
            Canvas { context, size in
                drawSmoothedShore(in: context, size: size)
            }
            .allowsHitTesting(false)
            if detailed {
                Canvas { context, size in
                    drawSprites(drawables(plan: plan), in: context, size: size)
                }
                .allowsHitTesting(false)
                let labels = visibleLabels(in: drawables(plan: plan), canvas: canvasSize)
                ForEach(labels) { item in
                    plantLabel(item)
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
            let ground = groundPath(in: size)
            guard !ground.isEmpty else { return }
            let pitch = max(IsoMap.tileWidth * 3.5 * camera.scale, 1)
            let origin = camera.screenPoint(.zero, in: size)
            let resolved = context.resolve(Image(FarmSprite.grass))
            context.drawLayer { layer in
                layer.clip(to: ground, style: FillStyle(eoFill: false))
                let bleed: CGFloat = 2
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
                        layer.draw(resolved, in: rect)
                    }
                }
                layer.drawLayer { tint in
                    tint.blendMode = .color
                    tint.opacity = 0.82
                    tint.fill(Path(CGRect(origin: .zero, size: size)), with: .color(FarmColor.freshGrass))
                }
                layer.drawLayer { tint in
                    tint.blendMode = .softLight
                    tint.opacity = 0.4
                    tint.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.78, green: 0.93, blue: 0.45)))
                }
                let shade = Color(red: 0.22, green: 0.42, blue: 0.08)
                for tile in [FarmTile(column: -6, row: 6), FarmTile(column: 10, row: 16), FarmTile(column: 18, row: 2)] where chart.ground.contains(tile) {
                    let center = camera.screenPoint(IsoMap.center(tile), in: size)
                    let radius = IsoMap.tileWidth * 8 * camera.scale
                    let gradient = Gradient(stops: [
                        .init(color: shade.opacity(0.22), location: 0),
                        .init(color: shade.opacity(0.08), location: 0.4),
                        .init(color: shade.opacity(0), location: 1)
                    ])
                    layer.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                    )
                }
                for tintSpot in chart.tints where visibleTileBounds(in: size, margin: 4).contains(tintSpot.tile) {
                    let center = camera.screenPoint(IsoMap.center(tintSpot.tile), in: size)
                    let radius = IsoMap.tileWidth * tintSpot.radius * camera.scale
                    let color = tintSpot.light
                        ? Color(red: 0.78, green: 0.92, blue: 0.46)
                        : Color(red: 0.20, green: 0.38, blue: 0.08)
                    let gradient = Gradient(stops: [
                        .init(color: color.opacity(tintSpot.light ? 0.28 : 0.22), location: 0),
                        .init(color: color.opacity(0.08), location: 0.55),
                        .init(color: color.opacity(0), location: 1)
                    ])
                    layer.drawLayer { tint in
                        tint.blendMode = tintSpot.light ? .softLight : .multiply
                        tint.fill(
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.55, width: radius * 2, height: radius * 1.1)),
                            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
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
            if record.kind.isTerrain || record.kind == .fence || record.kind == .cleared { continue }
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
        let bounds = visibleTileBounds(in: canvasSize, margin: 6)
        for record in decor where bounds.contains(record.tile) && decorBelongsOnIsland(record.tile) {
            guard let sprite = Woodland.sprite(record.sprite) else { continue }
            let dragged = record.id == dragging ? (hover ?? record.tile) : record.tile
            items.append(makeDecor(record, sprite: sprite, tile: dragged))
        }
        let paths = Set(records.filter { $0.kind == .path }.map(\.tile))
        for tile in chart.creek where bounds.contains(tile) {
            guard let span = Woodland.bridge(at: tile, creek: chart.creek, paths: paths) else { continue }
            items.append(makeBridge(tile: tile, span: span))
        }
        fadeTreesCoveringTheFarm(&items)
        return items.sorted { $0.depth < $1.depth }
    }

    private func visibleTileBounds(in size: CGSize, margin: Int) -> TileBounds {
        let corners = [
            CGPoint.zero,
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ].map { IsoMap.tile(at: camera.worldPoint($0, in: size)) }
        let columns = corners.map(\.column)
        let rows = corners.map(\.row)
        return TileBounds(
            columns: ((columns.min() ?? 0) - margin)...((columns.max() ?? 0) + margin),
            rows: ((rows.min() ?? 0) - margin)...((rows.max() ?? 0) + margin)
        )
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
        case .fence, .path, .dirt, .sand, .longgrass, .tilled, .forest, .lake, .creek, .cleared:
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
        case .decor: 0
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
        case .decor: 0
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
        case .decor(let sprite):
            sprite.name
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
        case .decor:
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

    private func makeDecor(_ record: DecorRecord, sprite: DecorSprite, tile: FarmTile) -> MapDrawable {
        let tilesWide = max(sprite.isTall ? 1 : 0, sprite.size.width / ShoreStamp.artTile)
        let width = tilesWide * IsoMap.tileWidth * camera.scale * CGFloat(record.scale)
        let height = sprite.size.width > 0 ? width * sprite.size.height / sprite.size.width : width
        let display = CGSize(width: width, height: height)
        let anchorScale = sprite.size.width > 0 ? width / sprite.size.width : 1
        let anchor = CGPoint(x: sprite.anchor.x * anchorScale, y: sprite.anchor.y * anchorScale)
        let ground = camera.screenPoint(IsoMap.center(tile), in: canvasSize)
        let center = CGPoint(x: ground.x - anchor.x + display.width / 2, y: ground.y - anchor.y + display.height / 2)
        return MapDrawable(
            id: record.id.uuidString,
            depth: IsoMap.center(tile).y + 0.42,
            point: center,
            visual: .decor(sprite),
            width: display.width,
            foot: display.height,
            anchorsBase: false,
            rotation: record.rotation,
            flipped: record.flipped,
            opacity: 1,
            pivot: ground,
            tall: sprite.isTall,
            tile: tile
        )
    }

    private func makeBridge(tile: FarmTile, span: BridgeSpan) -> MapDrawable {
        let stamp = span == .northSouth ? ShoreStamp.bridgeNE : ShoreStamp.bridgeNW
        let corners = IsoMap.corners(tile)
        let ground: CGPoint
        if span == .northSouth {
            ground = CGPoint(x: (corners[2].x + corners[3].x) / 2, y: (corners[2].y + corners[3].y) / 2)
        } else {
            ground = CGPoint(x: (corners[1].x + corners[2].x) / 2, y: (corners[1].y + corners[2].y) / 2)
        }
        let scale = ShoreStamp.pixelScale(camera.scale)
        let display = CGSize(width: stamp.size.width * scale, height: stamp.size.height * scale)
        let anchor = CGPoint(x: stamp.anchor.x * scale, y: stamp.anchor.y * scale)
        let screen = camera.screenPoint(ground, in: canvasSize)
        let center = CGPoint(x: screen.x - anchor.x + display.width / 2, y: screen.y - anchor.y + display.height / 2)
        return MapDrawable(
            id: "bridge-\(tile.column)-\(tile.row)",
            depth: IsoMap.center(tile).y + 0.25,
            point: center,
            visual: .decor(stamp),
            width: display.width,
            foot: display.height,
            anchorsBase: false,
            pivot: screen
        )
    }

    private func fadeTreesCoveringTheFarm(_ items: inout [MapDrawable]) {
        let farm = records.compactMap { record -> FarmTile? in
            switch record.kind {
            case .plant, .house, .tractor, .fence: record.tile
            default: nil
            }
        }
        for index in items.indices where items[index].tall {
            guard let tree = items[index].tile else { continue }
            let inFront = farm.contains { plot in
                let span = max(abs(tree.column - plot.column), abs(tree.row - plot.row))
                let south = tree.column + tree.row > plot.column + plot.row
                return span <= 1 && south
            }
            items[index].opacity = inFront ? 0.35 : 1
        }
    }

    private func spriteRect(_ item: MapDrawable) -> CGRect {
        let originY = item.anchorsBase ? item.point.y - item.foot : item.point.y - item.foot / 2
        return CGRect(x: item.point.x - item.width / 2, y: originY, width: item.width, height: item.foot)
    }

    private func drawSprites(_ items: [MapDrawable], in context: GraphicsContext, size: CGSize) {
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -12, dy: -12)
        var resolved: [String: GraphicsContext.ResolvedImage] = [:]
        for item in items {
            let rect = spriteRect(item)
            guard rect.intersects(view) else { continue }
            guard let name = spriteName(item.visual) else { continue }
            if resolved[name] == nil, let image = FarmSprite.image(named: name) {
                resolved[name] = context.resolve(Image(uiImage: image))
            }
            guard let image = resolved[name] else { continue }
            let pivot = item.pivot ?? item.point
            context.drawLayer { layer in
                layer.opacity = item.opacity
                if item.rotation != 0 || item.flipped {
                    layer.translateBy(x: pivot.x, y: pivot.y)
                    if item.rotation != 0 {
                        layer.rotate(by: .radians(item.rotation))
                    }
                    if item.flipped {
                        layer.scaleBy(x: -1, y: 1)
                    }
                    layer.translateBy(x: -pivot.x, y: -pivot.y)
                }
                layer.draw(image, in: rect)
            }
        }
    }

    @ViewBuilder
    private func plantLabel(_ item: MapDrawable) -> some View {
        if showsNames, case .plant(let info) = item.visual {
            Text(info.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OrchardColor.ink)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .fixedSize()
                .opacity(labelOpacity)
                .position(x: item.point.x, y: (item.anchorsBase ? item.point.y : item.point.y + item.foot / 2) + 16)
        }
    }

    private func shoreDrift(at date: Date) -> CGSize {
        let time = date.timeIntervalSinceReferenceDate
        return CGSize(width: CGFloat(time * 1.6), height: CGFloat(time * 1.2))
    }

    private func drawWater(in context: inout GraphicsContext, size: CGSize, drift: CGSize) {
        let ocean = context.resolve(Image(FarmSprite.waterOcean))
        drawScreenTiles(ocean, in: &context, size: size, drift: drift)
        let bounds = visibleTileBounds(in: size, margin: 2)
        let lakes = chart.lakes.union(chart.creek).filter { bounds.contains($0) }
        guard !lakes.isEmpty else { return }
        let lake = context.resolve(Image(FarmSprite.waterLake))
        let loops = smoothedWaterLoops()
        let clip = screenPath(loops, in: size)
        guard !clip.isEmpty else { return }
        context.drawLayer { layer in
            layer.clip(to: clip, style: FillStyle(eoFill: true))
            drawScreenTiles(lake, in: &layer, size: size, drift: drift)
            for loop in loops {
                shadeWaterDepth(loop, in: &layer, size: size)
            }
        }
        let grassBank = context.resolve(Image(FarmSprite.edgeBankGrass))
        let sandBank = context.resolve(Image(FarmSprite.edgeBankSand))
        let band = IsoMap.tileWidth * 0.28 * camera.scale
        for (index, loop) in loops.enumerated() {
            let screen = loop.map { camera.screenPoint($0, in: size) }
            let image = index.isMultiple(of: 3) ? sandBank : grassBank
            drawTexturedBand(image, along: screen, width: band, in: context, canvas: size, fade: true, towardCenter: true)
        }
    }

    private func smoothedWaterLoops() -> [[CGPoint]] {
        let key = "water-\(chart.lakes.count)-\(chart.creek.count)"
        if shoreCache.waterKey == key { return shoreCache.water }
        let loops = boundaryLoops(of: chart.lakes.union(chart.creek)).map { roundOutline($0) }
        shoreCache.waterKey = key
        shoreCache.water = loops
        return loops
    }

    private func shadeWaterDepth(_ loop: [CGPoint], in layer: inout GraphicsContext, size: CGSize) {
        let screen = loop.map { camera.screenPoint($0, in: size) }
        guard !screen.isEmpty else { return }
        let count = CGFloat(screen.count)
        let centroid = screen.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let middle = CGPoint(x: centroid.x / count, y: centroid.y / count)
        let radius = screen.map { hypot($0.x - middle.x, $0.y - middle.y) }.max() ?? 0
        guard radius > 2 else { return }
        let gradient = Gradient(stops: [
            .init(color: Color(red: 0.05, green: 0.28, blue: 0.42).opacity(0.38), location: 0),
            .init(color: Color(red: 0.05, green: 0.28, blue: 0.42).opacity(0.08), location: 0.62),
            .init(color: Color.white.opacity(0.16), location: 1)
        ])
        layer.fill(
            Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius * 0.62, width: radius * 2, height: radius * 1.24)),
            with: .radialGradient(gradient, center: middle, startRadius: 0, endRadius: radius)
        )
    }

    /// Square screen tiles, so the water ripples are not sheared into diagonal streaks.
    private func drawScreenTiles(_ image: GraphicsContext.ResolvedImage, in context: inout GraphicsContext, size: CGSize, drift: CGSize) {
        let pitch = max(IsoMap.tileWidth * 3.2 * camera.scale, 1)
        let originX = drift.width.truncatingRemainder(dividingBy: pitch)
        let originY = drift.height.truncatingRemainder(dividingBy: pitch)
        let bleed: CGFloat = 2
        var column = Int(floor(-originX / pitch)) - 1
        let lastColumn = Int(ceil((size.width - originX) / pitch)) + 1
        let firstRow = Int(floor(-originY / pitch)) - 1
        let lastRow = Int(ceil((size.height - originY) / pitch)) + 1
        while column <= lastColumn {
            var row = firstRow
            while row <= lastRow {
                let rect = CGRect(
                    x: originX + CGFloat(column) * pitch - bleed,
                    y: originY + CGFloat(row) * pitch - bleed,
                    width: pitch + bleed * 2,
                    height: pitch + bleed * 2
                )
                context.draw(image, in: rect)
                row += 1
            }
            column += 1
        }
    }

    private func drawSmoothedShore(in context: GraphicsContext, size: CGSize) {
        let loops = smoothedCoastLoops()
        guard !loops.isEmpty else { return }
        let cliff = context.resolve(Image("cliff_face_sw"))
        let foam = context.resolve(Image(FarmSprite.edgeFoam))
        let cliffWidth = IsoMap.tileWidth * 0.42 * camera.scale
        let foamWidth = IsoMap.tileWidth * 0.25 * camera.scale
        for loop in loops {
            let screen = loop.map { camera.screenPoint($0, in: size) }
            drawTexturedBand(cliff, along: screen, width: cliffWidth, in: context, canvas: size)
            drawTexturedBand(foam, along: screen, width: foamWidth, in: context, canvas: size)
        }
    }

    /// A soft strip centered on the outline, hanging toward the water.
    private func drawTexturedBand(
        _ image: GraphicsContext.ResolvedImage,
        along points: [CGPoint],
        width: CGFloat,
        in context: GraphicsContext,
        canvas size: CGSize,
        fade: Bool = false,
        towardCenter: Bool = false
    ) {
        guard points.count >= 2, width > 0.5 else { return }
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -width - 8, dy: -width - 8)
        let center = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(points.count)
        let middle = CGPoint(x: center.x / count, y: center.y / count)
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            guard view.contains(mid) else { continue }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.001)
            let along = CGPoint(x: dx / length, y: dy / length)
            var outward = CGPoint(x: dy / length, y: -dx / length)
            let inward = CGPoint(x: middle.x - mid.x, y: middle.y - mid.y)
            let pointsInward = outward.x * inward.x + outward.y * inward.y > 0
            if pointsInward != towardCenter {
                outward = CGPoint(x: -outward.x, y: -outward.y)
            }
            let origin = CGPoint(x: start.x + outward.x * width, y: start.y + outward.y * width)
            let transform = CGAffineTransform(a: along.x, b: along.y, c: -outward.x, d: -outward.y, tx: origin.x, ty: origin.y)
            context.drawLayer { layer in
                layer.concatenate(transform)
                layer.draw(image, in: CGRect(x: 0, y: 0, width: length, height: width))
                if fade {
                    layer.blendMode = .destinationIn
                    let fade = Gradient(stops: [
                        .init(color: Color.white.opacity(0.05), location: 0),
                        .init(color: Color.white.opacity(0.55), location: 0.45),
                        .init(color: Color.white, location: 1)
                    ])
                    layer.fill(
                        Path(CGRect(x: 0, y: 0, width: length, height: width)),
                        with: .linearGradient(fade, startPoint: CGPoint(x: length / 2, y: 0), endPoint: CGPoint(x: length / 2, y: width))
                    )
                }
            }
        }
    }

    private func drawCliffs(in context: GraphicsContext, size: CGSize) {
        let bounds = visibleTileBounds(in: size, margin: 3)
        for tile in chart.ground where bounds.contains(tile) {
            let south = FarmTile(column: tile.column, row: tile.row + 1)
            let east = FarmTile(column: tile.column + 1, row: tile.row)
            let facesSouth = isOcean(south)
            let facesEast = isOcean(east)
            let corners = IsoMap.corners(tile)
            if facesSouth {
                drawStamp(ShoreStamp.faceSW, at: corners[3], in: context, size: size)
            }
            if facesEast {
                drawStamp(ShoreStamp.faceSE, at: corners[2], in: context, size: size)
            }
            if facesSouth && facesEast {
                drawStamp(ShoreStamp.cornerS, at: corners[2], in: context, size: size)
            }
        }
    }

    private func drawFoam(in context: GraphicsContext, size: CGSize) {
        let resolved = context.resolve(Image(FarmSprite.edgeFoam))
        let drop = ShoreStamp.waterDrop(camera: camera.scale)
        let bounds = visibleTileBounds(in: size, margin: 2)
        for tile in chart.ground where bounds.contains(tile) {
            for neighbor in Woodland.orthogonal(tile) where isOcean(neighbor) {
                guard let edge = gridEdge(from: tile, toward: neighbor) else { continue }
                drawEdgeStrip(resolved, edge: edge, owner: tile, kind: .path, in: context, size: size, drop: drop, fades: false, fraction: 0.25)
            }
        }
    }

    private func drawBanks(in context: GraphicsContext, size: CGSize) {
        let grassImage = context.resolve(Image(FarmSprite.edgeBankGrass))
        let sandImage = context.resolve(Image(FarmSprite.edgeBankSand))
        let bounds = visibleTileBounds(in: size, margin: 2)
        let water = chart.water
        for tile in chart.ground where bounds.contains(tile) {
            for neighbor in Woodland.orthogonal(tile) where water.contains(neighbor) {
                guard let edge = gridEdge(from: tile, toward: neighbor) else { continue }
                let image = Woodland.bankIsSand(seed: shoreSeed, edge: edge) ? sandImage : grassImage
                drawEdgeStrip(image, edge: edge, owner: tile, kind: .path, in: context, size: size, fades: false, fraction: 0.22)
            }
        }
    }

    private func drawStamp(_ stamp: DecorSprite, at world: CGPoint, in context: GraphicsContext, size: CGSize) {
        let scale = ShoreStamp.pixelScale(camera.scale)
        let display = CGSize(width: stamp.size.width * scale, height: stamp.size.height * scale)
        let anchor = CGPoint(x: stamp.anchor.x * scale, y: stamp.anchor.y * scale)
        let screen = camera.screenPoint(world, in: size)
        let rect = CGRect(x: screen.x - anchor.x, y: screen.y - anchor.y, width: display.width, height: display.height)
        context.draw(context.resolve(Image(stamp.name)), in: rect)
    }

    private func decorBelongsOnIsland(_ tile: FarmTile) -> Bool {
        if chart.ground.contains(tile) || chart.water.contains(tile) { return true }
        return Woodland.orthogonal(tile).contains { chart.ground.contains($0) }
    }

    private func isOcean(_ tile: FarmTile) -> Bool {
        !chart.ground.contains(tile) && !chart.water.contains(tile)
    }

    private func gridEdge(from tile: FarmTile, toward neighbor: FarmTile) -> FarmGridEdge? {
        let corners = IsoMap.corners(tile)
        if neighbor.column == tile.column + 1 && neighbor.row == tile.row {
            return FarmGridEdge(anchor: corners[2], end: corners[1], runsNorthEast: true)
        }
        if neighbor.column == tile.column - 1 && neighbor.row == tile.row {
            return FarmGridEdge(anchor: corners[3], end: corners[0], runsNorthEast: true)
        }
        if neighbor.row == tile.row + 1 && neighbor.column == tile.column {
            return FarmGridEdge(anchor: corners[2], end: corners[3], runsNorthEast: false)
        }
        if neighbor.row == tile.row - 1 && neighbor.column == tile.column {
            return FarmGridEdge(anchor: corners[1], end: corners[0], runsNorthEast: false)
        }
        return nil
    }

    private func groundPath(in size: CGSize) -> Path {
        screenPath(smoothedLandLoops(), in: size)
    }

    private func smoothedLandLoops() -> [[CGPoint]] {
        let key = "land-\(chart.ground.count)-\(chart.lakes.count)-\(chart.creek.count)"
        if shoreCache.landKey == key { return shoreCache.land }
        let loops = boundaryLoops(of: chart.ground).map { roundOutline($0) }
        shoreCache.landKey = key
        shoreCache.land = loops
        return loops
    }

    private func smoothedCoastLoops() -> [[CGPoint]] {
        let key = "coast-\(chart.ground.count)-\(chart.lakes.count)-\(chart.creek.count)"
        if shoreCache.coastKey == key { return shoreCache.coast }
        let mass = chart.ground.union(chart.water)
        let loops = boundaryLoops(of: mass).map { roundOutline($0) }
        shoreCache.coastKey = key
        shoreCache.coast = loops
        return loops
    }

    private func drawTerrains(in context: GraphicsContext, size: CGSize) {
        let prepared = preparedTerrain()
        let bounds = visibleTileBounds(in: size, margin: 2)
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -32, dy: -32)
        let natural: Set<FarmItemKind> = [.forest, .longgrass, .dirt]
        for (kind, tiles) in prepared.fills {
            guard let name = FarmSprite.terrainFill(kind) else { continue }
            let union: Path
            if natural.contains(kind), let loops = prepared.smooth[kind] {
                union = screenPath(loops, in: size)
            } else {
                let visible = tiles.filter { bounds.contains($0) }
                guard !visible.isEmpty else { continue }
                union = diamondUnion(visible, in: size)
            }
            guard !union.isEmpty else { continue }
            let resolved = context.resolve(Image(name))
            context.drawLayer { layer in
                layer.clip(to: union, style: FillStyle(eoFill: true))
                let pixelsPerCell: CGFloat = kind == .tilled ? 128 : 256
                drawWarped(resolved, layer: &layer, size: size, pixelsPerCell: pixelsPerCell)
                if kind == .forest {
                    layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.15)))
                }
            }
        }
        for (kind, edges) in prepared.edges where !natural.contains(kind) {
            guard let name = FarmSprite.terrainEdge(kind) else { continue }
            let resolved = context.resolve(Image(name))
            let feather: CGFloat? = (kind == .forest || kind == .longgrass || kind == .dirt) ? 0.22 : nil
            for boundary in edges {
                let middle = CGPoint(
                    x: (boundary.edge.anchor.x + boundary.edge.end.x) / 2,
                    y: (boundary.edge.anchor.y + boundary.edge.end.y) / 2
                )
                guard view.contains(camera.screenPoint(middle, in: size)) else { continue }
                drawEdgeStrip(
                    resolved,
                    edge: boundary.edge,
                    owner: boundary.owner,
                    kind: kind,
                    in: context,
                    size: size,
                    fraction: feather
                )
            }
        }
    }

    /// Tile sets and outer edges, rebuilt only when the painted terrain or the island changes.
    private func preparedTerrain() -> TerrainDrawCache {
        var hasher = Hasher()
        hasher.combine(chart.ground.count)
        hasher.combine(chart.lakes.count)
        hasher.combine(chart.creek.count)
        hasher.combine(terrain.count)
        for (tile, kind) in terrain {
            hasher.combine(tile.column)
            hasher.combine(tile.row)
            hasher.combine(kind.rawValue)
        }
        let key = hasher.finalize()
        if terrainCache.key == key {
            return terrainCache
        }
        let order: [FarmItemKind] = [.forest, .longgrass, .dirt, .sand, .path, .tilled]
        let onIsland = chart.ground.union(chart.water)
        let natural: Set<FarmItemKind> = [.forest, .longgrass, .dirt]
        var fills: [(FarmItemKind, Set<FarmTile>)] = []
        var edges: [(FarmItemKind, [(edge: FarmGridEdge, owner: FarmTile)])] = []
        var smooth: [FarmItemKind: [[CGPoint]]] = [:]
        for kind in order {
            let tiles = Set(terrain.compactMap { (tile, painted) -> FarmTile? in
                guard painted == kind else { return nil }
                if kind == .forest || kind == .longgrass || kind == .dirt, !onIsland.contains(tile) {
                    return nil
                }
                return tile
            })
            guard !tiles.isEmpty else { continue }
            fills.append((kind, tiles))
            if natural.contains(kind) {
                smooth[kind] = boundaryLoops(of: tiles).map { roundOutline($0) }
            } else {
                let boundary = FarmSurface.boundaryEdges(of: tiles).map { (edge: $0.edge, owner: $0.outwardFrom) }
                edges.append((kind, boundary))
            }
        }
        terrainCache.key = key
        terrainCache.fills = fills
        terrainCache.edges = edges
        terrainCache.smooth = smooth
        return terrainCache
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

    private func screenPath(_ loops: [[CGPoint]], in size: CGSize) -> Path {
        var path = Path()
        for loop in loops where loop.count >= 3 {
            path.move(to: camera.screenPoint(loop[0], in: size))
            for point in loop.dropFirst() {
                path.addLine(to: camera.screenPoint(point, in: size))
            }
            path.closeSubpath()
        }
        return path
    }

    /// Clockwise tile edges that face outside the set, walked into closed loops and ready to smooth.
    private func boundaryLoops(of tiles: Set<FarmTile>) -> [[CGPoint]] {
        struct Vertex: Hashable {
            var x: Int
            var y: Int
        }
        func quantize(_ point: CGPoint) -> Vertex {
            Vertex(x: Int((point.x * 2).rounded()), y: Int((point.y * 2).rounded()))
        }
        func restore(_ vertex: Vertex) -> CGPoint {
            CGPoint(x: CGFloat(vertex.x) / 2, y: CGFloat(vertex.y) / 2)
        }
        var outgoing: [Vertex: [Vertex]] = [:]
        let sides: [(Int, Int, Int, Int)] = [
            (0, 1, 0, -1),
            (1, 2, 1, 0),
            (2, 3, 0, 1),
            (3, 0, -1, 0)
        ]
        for tile in tiles {
            let corners = IsoMap.corners(tile)
            for (startIndex, endIndex, columnStep, rowStep) in sides {
                let neighbor = FarmTile(column: tile.column + columnStep, row: tile.row + rowStep)
                if tiles.contains(neighbor) { continue }
                let start = quantize(corners[startIndex])
                let end = quantize(corners[endIndex])
                outgoing[start, default: []].append(end)
            }
        }
        var loops: [[CGPoint]] = []
        var guardSteps = 0
        let limit = outgoing.values.reduce(0) { $0 + $1.count } + 2
        while let start = outgoing.first(where: { !$0.value.isEmpty })?.key {
            var loop: [CGPoint] = []
            var current = start
            while guardSteps < limit {
                guard var choices = outgoing[current], !choices.isEmpty else { break }
                let next = choices.removeLast()
                if choices.isEmpty {
                    outgoing.removeValue(forKey: current)
                } else {
                    outgoing[current] = choices
                }
                loop.append(restore(current))
                guardSteps += 1
                if next == start {
                    break
                }
                current = next
            }
            if loop.count >= 3 {
                loops.append(loop)
            }
        }
        return loops
    }

    /// Cuts each corner by about half a tile, then eases the chamfer into a curve.
    private func roundOutline(_ points: [CGPoint]) -> [CGPoint] {
        let chamfered = chaikin(points, passes: 2, weight: 0.5)
        return chaikin(chamfered, passes: 1, weight: 0.25)
    }

    private func chaikin(_ points: [CGPoint], passes: Int, weight: CGFloat = 0.25) -> [CGPoint] {
        var pts = points
        let keep = min(max(weight, 0.05), 0.5)
        let take = 1 - keep
        for _ in 0..<passes {
            guard pts.count >= 3 else { return pts }
            var next: [CGPoint] = []
            next.reserveCapacity(pts.count * 2)
            for index in pts.indices {
                let current = pts[index]
                let following = pts[(index + 1) % pts.count]
                next.append(CGPoint(x: current.x * take + following.x * keep, y: current.y * take + following.y * keep))
                next.append(CGPoint(x: current.x * keep + following.x * take, y: current.y * keep + following.y * take))
            }
            pts = next
        }
        return pts
    }

    /// One name per nearby cluster, then drop any label whose pill would cover one already kept.
    private func visibleLabels(in items: [MapDrawable], canvas size: CGSize) -> [MapDrawable] {
        guard labelOpacity > 0.04 else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let plants = items.compactMap { item -> (MapDrawable, Double, CGFloat)? in
            guard case .plant(let info) = item.visual else { return nil }
            let ground = item.pivot ?? item.point
            let distance = hypot(ground.x - center.x, ground.y - center.y)
            return (item, info.rating ?? 0, distance)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }
        let cluster = IsoMap.tileWidth * camera.scale * 1.7
        var anchors: [CGPoint] = []
        var placed: [CGRect] = []
        var kept: [MapDrawable] = []
        for (item, _, _) in plants {
            let anchor = item.pivot ?? item.point
            if anchors.contains(where: { hypot($0.x - anchor.x, $0.y - anchor.y) < cluster }) { continue }
            let pill = CGRect(x: item.point.x - 54, y: item.point.y - 14, width: 108, height: 28)
            if placed.contains(where: { $0.intersects(pill) }) { continue }
            anchors.append(anchor)
            placed.append(pill)
            kept.append(item)
        }
        return kept
    }

    /// One texture covers several cells, in world space, so its wrap does not sit on every cell edge.
    /// Tilled soil is 128 app pixels per cell (four furrows). The other grounds are 256.
    private func drawWarped(
        _ image: GraphicsContext.ResolvedImage,
        layer: inout GraphicsContext,
        size: CGSize,
        pixelsPerCell: CGFloat,
        drift: CGSize = .zero
    ) {
        let tile = IsoMap.tileWidth
        let zoom = camera.scale
        let span: CGFloat = 512
        let a = zoom * (tile / 2) / pixelsPerCell
        let b = zoom * (tile / 4) / pixelsPerCell
        let transform = CGAffineTransform(
            a: a, b: b,
            c: -a, d: b,
            tx: size.width / 2 + camera.pan.width - camera.center.x * zoom + drift.width,
            ty: size.height / 2 + camera.pan.height - camera.center.y * zoom + drift.height
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
        size: CGSize,
        drop: CGFloat = 0,
        fades: Bool = true,
        fraction: CGFloat? = nil
    ) {
        var start = camera.screenPoint(edge.anchor, in: size)
        var finish = camera.screenPoint(edge.end, in: size)
        start.y += drop
        finish.y += drop
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
        let strip = fraction ?? (kind == .longgrass ? 0.18 : 0.12)
        let height = IsoMap.tileWidth * strip * camera.scale
        let origin = CGPoint(x: start.x + outward.x * height, y: start.y + outward.y * height)
        let transform = CGAffineTransform(
            a: along.x, b: along.y,
            c: -outward.x, d: -outward.y,
            tx: origin.x, ty: origin.y
        )
        context.drawLayer { layer in
            layer.concatenate(transform)
            layer.draw(image, in: CGRect(x: 0, y: 0, width: length, height: height))
            if fades {
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
    var rotation: Double = 0
    var flipped: Bool = false
    var opacity: Double = 1
    var pivot: CGPoint? = nil
    var tall: Bool = false
    var tile: FarmTile? = nil
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
    case decor(DecorSprite)

    var anchorsBase: Bool {
        switch self {
        case .soilTree, .soilVine, .soilBed, .rail, .post:
            return false
        case .decor:
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
        case .path, .dirt, .sand, .longgrass, .tilled, .forest, .lake, .creek: 0.1
        case .fence: 0.2
        case .bush, .rock, .cleared: 0.3
        case .plant: 0.4
        case .tractor: 0.5
        case .house: 0.6
        }
    }
}

private final class TerrainDrawCache {
    var key: Int?
    var fills: [(FarmItemKind, Set<FarmTile>)] = []
    var edges: [(FarmItemKind, [(edge: FarmGridEdge, owner: FarmTile)])] = []
    var smooth: [FarmItemKind: [[CGPoint]]] = [:]
}

private final class ShoreLoopCache {
    var landKey = ""
    var land: [[CGPoint]] = []
    var coastKey = ""
    var coast: [[CGPoint]] = []
    var waterKey = ""
    var water: [[CGPoint]] = []
}

private struct TileBounds {
    var columns: ClosedRange<Int>
    var rows: ClosedRange<Int>

    func contains(_ tile: FarmTile) -> Bool {
        columns.contains(tile.column) && rows.contains(tile.row)
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
    /// Ocean flat colour, close to #3FA7D6, used when the texture has not decoded.
    static let ocean = Color(red: 0.247, green: 0.655, blue: 0.839)
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
