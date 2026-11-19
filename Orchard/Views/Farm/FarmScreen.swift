import SwiftData
import SwiftUI
import UIKit

private enum FarmTool: Hashable {
    case move
    case paint(FarmItemKind?)

    static let palette: [FarmTool] = [
        .move,
        .paint(.path),
        .paint(.dirt),
        .paint(.sand),
        .paint(.longgrass),
        .paint(.tilled),
        .paint(nil)
    ]

    var isBrush: Bool {
        if case .move = self { return false }
        return true
    }

    var iconName: String? {
        switch self {
        case .move: nil
        case .paint(.dirt): "icon_terrain_dirt"
        case .paint(.sand): "icon_terrain_sand"
        case .paint(.longgrass): "icon_terrain_longgrass"
        case .paint(.tilled): "terrain_tilled"
        case .paint(.path): "icon_terrain_path"
        case .paint(nil): "icon_terrain_grass"
        case .paint(_): "icon_terrain_grass"
        }
    }
}

private enum MapGesture {
    case undecided
    case pan
    case moveItem
    case place
}

/// Zoom factors are multiples of the fit-to-farm scale.
private enum FarmZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 2.5
    static let close: CGFloat = 1.6
    static let labels: CGFloat = 1.25
}

private enum FarmViewMemory {
    private static let key = "orchard.farm.camera"

    struct Stored: Codable {
        var scale: CGFloat
        var centerX: CGFloat
        var centerY: CGFloat
        var panW: CGFloat
        var panH: CGFloat
    }

    static func load() -> (scale: CGFloat, center: CGPoint, pan: CGSize)? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.scale > 0 else { return nil }
        return (
            stored.scale,
            CGPoint(x: stored.centerX, y: stored.centerY),
            CGSize(width: stored.panW, height: stored.panH)
        )
    }

    static func save(scale: CGFloat, center: CGPoint, pan: CGSize) {
        let stored = Stored(scale: scale, centerX: center.x, centerY: center.y, panW: pan.width, panH: pan.height)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct FarmScreen: View {
    @Query private var placements: [FarmPlacement]
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @Environment(\.modelContext) private var context
    @State private var previewStarter = FarmExpansion.starterRecords()
    @State private var editing = false
    @State private var tool: FarmTool = .move
    @State private var paintStroke: [FarmTile: FarmItemKind?] = [:]
    @State private var undo: [[FarmRecord]] = []
    @State private var scale: CGFloat
    @State private var lastScale: CGFloat
    @State private var offset: CGSize
    @State private var lastOffset: CGSize
    @State private var worldCenter: CGPoint
    @State private var framed: Bool
    @State private var userMoved: Bool
    @State private var mapSize: CGSize = .zero
    @State private var pinchStartScale: CGFloat = 1
    @State private var pinchWorld: CGPoint = .zero
    @State private var oneFingerPoint: CGPoint?

    init() {
        let saved = FarmViewMemory.load()
        _scale = State(initialValue: saved?.scale ?? 1)
        _lastScale = State(initialValue: saved?.scale ?? 1)
        _offset = State(initialValue: saved?.pan ?? .zero)
        _lastOffset = State(initialValue: saved?.pan ?? .zero)
        _worldCenter = State(initialValue: saved?.center ?? .zero)
        _framed = State(initialValue: saved != nil)
        _userMoved = State(initialValue: saved != nil)
    }
    @State private var scenery = false
    @State private var frameRequest = 0
    @State private var selected: VarietyLink?
    @State private var gesture = MapGesture.undecided
    @State private var dragging: UUID?
    @State private var hover: FarmTile?
    @State private var hoverValid = false

    private var storedRecords: [FarmRecord] {
        placements.map(\.record)
    }

    private var records: [FarmRecord] {
        storedRecords.isEmpty ? previewStarter : storedRecords
    }

    private var tastedCount: Int {
        varieties.filter(\.isTried).count
    }

    private var triedSignature: String {
        varieties.filter(\.isTried).map(\.slug).sorted().joined(separator: "|")
    }

    private var plants: [String: FarmPlantInfo] {
        guard scenery else { return [:] }
        return Dictionary(uniqueKeysWithValues: varieties.map { variety in
            (variety.slug, FarmPlantInfo(
                id: variety.slug,
                name: variety.name,
                zone: variety.zoneRaw,
                category: variety.categoryRaw,
                form: variety.form,
                skin: variety.fruitSkin,
                rating: variety.latestTasting?.overall
            ))
        })
    }

    private var yardPlan: YardPlan {
        var zones: [String: String] = [:]
        for variety in varieties {
            zones[variety.slug] = variety.zoneRaw
        }
        return FarmExpansion.plan(records: records, zones: zones)
    }

    private var camera: FarmCamera {
        FarmCamera(scale: scale, center: worldCenter, pan: offset)
    }

    private func resolvedCamera(in viewSize: CGSize) -> FarmCamera {
        framed ? camera : fittedCamera(in: viewSize)
    }

    var body: some View {
        GeometryReader { geo in
            let shown = resolvedCamera(in: geo.size)
            let namesVisible = shown.scale >= fitScale(in: geo.size) * FarmZoom.labels
            ZStack {
                FarmColor.freshGrass
                FarmMapView(
                    records: displayRecords,
                    plants: plants,
                    tastedCount: tastedCount,
                    hover: hover,
                    hoverValid: hoverValid,
                    dragging: dragging,
                    showsNames: namesVisible,
                    detailed: scenery,
                    camera: shown,
                    canvasSize: geo.size,
                    terrain: displayTerrain,
                    hoverTiles: hoverFootprint
                )
                MapGestureOverlay(
                    brush: tool.isBrush && editing,
                    onPinch: { magnification, point, state in
                        handlePinch(magnification, at: point, state: state, in: geo.size)
                    },
                    onTwoPan: { translation, state in
                        handleTwoPan(translation, state: state)
                    },
                    onOnePan: { start, current, translation, state in
                        handleOnePan(start: start, current: current, translation: translation, state: state, in: geo.size)
                    },
                    onDoubleTap: { point in
                        toggleZoom(at: point, in: geo.size)
                    },
                    onSingleTap: { point in
                        guard !editing, let slug = plantSlug(at: point, in: geo.size) else { return }
                        selected = VarietyLink(id: slug)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                mapSize = geo.size
                frameHouse(in: geo.size)
                if DebugLaunch.demoTerrain { editing = true }
            }
            .onDisappear { saveCamera() }
            .onChange(of: geo.size) { _, newSize in mapSize = newSize }
            .onChange(of: frameRequest) { _, _ in frameHouse(in: geo.size) }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { editBar }
        .overlay(alignment: .bottomTrailing) { zoomButtons }
        .sheet(item: $selected) { link in
            VarietyDetailView(slug: link.id)
        }
        .task(id: triedSignature) {
            // The grass frame commits before any PNG decode or store rewrite.
            await Task.yield()
            await FarmSprite.warm(spritesToWarm())
            if !scenery {
                scenery = true
            }
            if !userMoved {
                framed = false
                frameRequest += 1
            }
            await Task.yield()
            guard !varieties.isEmpty else { return }
            let tried = varieties.filter(\.isTried).map { (id: $0.slug, zone: $0.zoneRaw) }
            try? FarmLayout.sync(context: context, tried: tried)
            if !userMoved {
                framed = false
                frameRequest += 1
            }
        }
    }

    private var displayTerrain: [FarmTile: FarmItemKind] {
        var map: [FarmTile: FarmItemKind] = [:]
        for record in displayRecords where record.kind.isTerrain {
            map[record.tile] = record.kind
        }
        if let dragging, let hover, let moving = records.first(where: { $0.id == dragging }), moving.kind == .plant,
           let variety = moving.varietyID, let info = plants[variety] {
            let spot = FarmExpansion.spotKind(zone: info.zone)
            if spot == .bed || spot == .vine, map[moving.tile] == .tilled {
                map[moving.tile] = nil
                map[hover] = .tilled
            }
        }
        for tile in yardPlan.bedSpots where map[tile] == nil && !paintStroke.keys.contains(tile) {
            map[tile] = .tilled
        }
        for (tile, painted) in paintStroke {
            if let painted {
                map[tile] = painted
            } else {
                map.removeValue(forKey: tile)
            }
        }
        return map
    }

    private var hoverFootprint: [FarmTile] {
        guard let hover else { return [] }
        guard let dragging, let record = records.first(where: { $0.id == dragging }) else { return [hover] }
        return FarmExpansion.footprint(kind: record.kind, anchor: hover)
    }

    private var displayRecords: [FarmRecord] {
        guard let dragging, let hover else { return records }
        return records.map { record in
            guard record.id == dragging else { return record }
            var moved = record
            moved.tile = hover
            return moved
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text("Chris's Orchard")
                    .font(.system(size: 18, weight: .semibold))
                Text("\(tastedCount) planted")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(OrchardColor.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer(minLength: 0)
            Button(editing ? "Done" : "Edit") {
                editing.toggle()
                if !editing {
                    tool = .move
                    clearGesture()
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OrchardColor.grassDeep)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var editBar: some View {
        if editing {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FarmTool.palette, id: \.self) { item in
                        Button {
                            tool = item
                            clearGesture()
                        } label: {
                            toolLabel(item)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Undo") { undoLast() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(undo.isEmpty ? Color.secondary : OrchardColor.ink)
                        .disabled(undo.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func toolLabel(_ item: FarmTool) -> some View {
        let selected = tool == item
        Group {
            if item == .move {
                Text("Move")
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? OrchardColor.grassDeep : OrchardColor.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else if let icon = item.iconName {
                Image(icon)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: 36, height: 36)
                    .padding(2)
            }
        }
        .background(selected ? Color.white.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func handleOnePan(start: CGPoint, current: CGPoint, translation: CGSize, state: UIGestureRecognizer.State, in viewSize: CGSize) {
        let travel = hypot(translation.width, translation.height)
        if state == .began || gesture == .undecided {
            if editing, tool.isBrush {
                gesture = .place
            } else if editing, tool == .move, let hit = item(at: start, in: viewSize) {
                gesture = .moveItem
                dragging = hit.id
            } else if travel > 6 {
                gesture = .pan
                userMoved = true
            }
        }
        switch gesture {
        case .pan:
            userMoved = true
            offset = CGSize(width: lastOffset.width + translation.width, height: lastOffset.height + translation.height)
        case .moveItem:
            let next = tile(at: current, in: viewSize)
            if next != hover {
                if hover != nil {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                hover = next
            }
            hoverValid = placementValid(next)
        case .place:
            let origin = oneFingerPoint ?? start
            paint(from: origin, to: current, in: viewSize)
            oneFingerPoint = current
        case .undecided:
            break
        }
        if state == .ended || state == .cancelled || state == .failed {
            oneFingerPoint = nil
            if gesture == .pan {
                lastOffset = offset
                saveCamera()
            } else if gesture == .moveItem {
                if hoverValid, let hover, let dragging, let moving = records.first(where: { $0.id == dragging }), moving.tile != hover {
                    let carried = moving.kind == .plant ? plants[moving.varietyID ?? ""] : nil
                    let spot = carried.map { FarmExpansion.spotKind(zone: $0.zone) }
                    commit { records in
                        guard let index = records.firstIndex(where: { $0.id == dragging }) else { return }
                        let origin = records[index].tile
                        records[index].tile = hover
                        guard spot == .bed || spot == .vine else { return }
                        let destinationHasSoil = records.contains { $0.kind == .tilled && $0.tile == hover }
                        if destinationHasSoil {
                            records.removeAll { $0.kind == .tilled && $0.tile == origin }
                        } else if let soil = records.firstIndex(where: { $0.kind == .tilled && $0.tile == origin }) {
                            records[soil].tile = hover
                        } else {
                            records.append(FarmRecord(id: UUID(), kind: .tilled, varietyID: nil, tile: hover))
                        }
                    }
                }
            } else if gesture == .place {
                commitPaint()
            }
            clearGesture()
        }
    }

    private func handleTwoPan(_ translation: CGSize, state: UIGestureRecognizer.State) {
        userMoved = true
        if state == .changed || state == .began {
            offset = CGSize(width: lastOffset.width + translation.width, height: lastOffset.height + translation.height)
        }
        if state == .ended || state == .cancelled || state == .failed {
            lastOffset = offset
            saveCamera()
        }
    }

    private func handlePinch(_ magnification: CGFloat, at point: CGPoint, state: UIGestureRecognizer.State, in viewSize: CGSize) {
        switch state {
        case .began:
            userMoved = true
            pinchStartScale = scale
            pinchWorld = resolvedCamera(in: viewSize).worldPoint(point, in: viewSize)
        case .changed:
            let range = zoomRange(in: viewSize)
            let next = rubber(pinchStartScale * magnification, min: range.min, max: range.max)
            scale = next
            offset = pan(keeping: pinchWorld, at: point, scale: next, in: viewSize)
        case .ended, .cancelled, .failed:
            settleZoom(keeping: pinchWorld, at: point, in: viewSize)
        default:
            break
        }
    }

    private func zoomRange(in viewSize: CGSize) -> (min: CGFloat, max: CGFloat) {
        let fit = fitScale(in: viewSize)
        let land = landScale(in: viewSize)
        return (min(land, fit), fit * FarmZoom.maximum)
    }

    private func fitScale(in viewSize: CGSize) -> CGFloat {
        max(fittedCamera(in: viewSize).scale, 0.05)
    }

    private func rubber(_ proposed: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        if proposed < minimum {
            return minimum - (minimum - proposed) * 0.28
        }
        if proposed > maximum {
            return maximum + (proposed - maximum) * 0.28
        }
        return proposed
    }

    private func pan(keeping world: CGPoint, at screen: CGPoint, scale newScale: CGFloat, in viewSize: CGSize) -> CGSize {
        CGSize(
            width: screen.x - viewSize.width / 2 - (world.x - worldCenter.x) * newScale,
            height: screen.y - viewSize.height / 2 - (world.y - worldCenter.y) * newScale
        )
    }

    private func settleZoom(keeping world: CGPoint, at screen: CGPoint, in viewSize: CGSize) {
        let range = zoomRange(in: viewSize)
        let clamped = min(range.max, max(range.min, scale))
        let settled = pan(keeping: world, at: screen, scale: clamped, in: viewSize)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            scale = clamped
            offset = settled
            lastScale = clamped
            lastOffset = settled
        }
        saveCamera(scale: clamped, pan: settled)
    }

    private func toggleZoom(at point: CGPoint, in viewSize: CGSize) {
        userMoved = true
        let fit = fittedCamera(in: viewSize)
        let close = fit.scale * FarmZoom.close
        let atClose = abs(scale - close) < fit.scale * 0.12
        let tapped = resolvedCamera(in: viewSize).worldPoint(point, in: viewSize)
        let nextScale = atClose ? fit.scale : close
        let nextCenter = atClose ? fit.center : tapped
        withAnimation(.easeInOut(duration: 0.28)) {
            scale = nextScale
            worldCenter = nextCenter
            offset = .zero
            lastScale = nextScale
            lastOffset = .zero
        }
        saveCamera(scale: nextScale, center: nextCenter, pan: .zero)
    }

    private func nudgeZoom(_ factor: CGFloat) {
        guard mapSize.width > 1 else { return }
        userMoved = true
        let range = zoomRange(in: mapSize)
        let next = min(range.max, max(range.min, scale * factor))
        let focus = CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
        let world = resolvedCamera(in: mapSize).worldPoint(focus, in: mapSize)
        let shifted = pan(keeping: world, at: focus, scale: next, in: mapSize)
        withAnimation(.easeOut(duration: 0.18)) {
            scale = next
            offset = shifted
            lastScale = next
            lastOffset = shifted
        }
        saveCamera(scale: next, pan: shifted)
    }

    private func saveCamera() {
        saveCamera(scale: scale, center: worldCenter, pan: offset)
    }

    private func saveCamera(scale: CGFloat, center: CGPoint? = nil, pan: CGSize) {
        FarmViewMemory.save(scale: scale, center: center ?? worldCenter, pan: pan)
    }

    private var zoomButtons: some View {
        VStack(spacing: 8) {
            zoomButton("plus") { nudgeZoom(1.25) }
            zoomButton("minus") { nudgeZoom(1 / 1.25) }
        }
        .padding(.trailing, 12)
        .padding(.bottom, editing ? 76 : 12)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OrchardColor.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func clearGesture() {
        gesture = .undecided
        dragging = nil
        hover = nil
        hoverValid = false
    }

    private func tile(at location: CGPoint, in viewSize: CGSize) -> FarmTile {
        IsoMap.tile(at: resolvedCamera(in: viewSize).worldPoint(location, in: viewSize))
    }

    private func item(at location: CGPoint, in viewSize: CGSize) -> FarmRecord? {
        let view = resolvedCamera(in: viewSize)
        let hit = records.min { lhs, rhs in
            distance(view.screenPoint(IsoMap.center(lhs.tile), in: viewSize), location)
                < distance(view.screenPoint(IsoMap.center(rhs.tile), in: viewSize), location)
        }
        guard let hit, distance(view.screenPoint(IsoMap.center(hit.tile), in: viewSize), location) < 44 else { return nil }
        return hit
    }

    private func spritesToWarm() -> [String] {
        var names = [
            FarmSprite.grass, FarmSprite.tractor, FarmSprite.bush, FarmSprite.rock,
            FarmSprite.sapling, FarmSprite.soilTree, FarmSprite.soilVine, FarmSprite.emptyBed,
            FarmSprite.pathTexture, FarmSprite.pathEdge, FarmSprite.terrainDirt, FarmSprite.terrainSand,
            FarmSprite.terrainLonggrass, FarmSprite.terrainTilled, FarmSprite.edgeDirt, FarmSprite.edgeSand,
            FarmSprite.edgeLonggrass, FarmSprite.edgeBed,
            FarmSprite.fencePost, FarmSprite.fenceRailNE, FarmSprite.fenceRailNW,
            FarmSprite.house(HouseRules.progress(for: tastedCount).tier)
        ]
        for variety in varieties where variety.isTried {
            names.append(FarmSprite.plantName(
                zone: variety.zoneRaw,
                category: variety.categoryRaw,
                varietyID: variety.slug,
                rating: variety.latestTasting?.overall
            ))
        }
        return names
    }

    private func plantSlug(at location: CGPoint, in viewSize: CGSize) -> String? {
        guard let hit = item(at: location, in: viewSize), hit.kind == .plant else { return nil }
        return hit.varietyID
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func placementValid(_ tile: FarmTile) -> Bool {
        guard let dragging, let record = records.first(where: { $0.id == dragging }) else { return false }
        if record.kind.isTerrain {
            return !records.contains { $0.id != record.id && $0.kind.isTerrain && $0.tile == tile }
        }
        var occupied = Set(records.filter { !$0.kind.isTerrain }.map(\.tile))
        occupied.remove(record.tile)
        let spot = record.varietyID.flatMap { plants[$0] }.map { FarmExpansion.spotKind(zone: $0.zone) }
        let reserved = FarmExpansion.reservedTiles(in: records, ignoring: record.id)
        return FarmExpansion.canPlace(
            kind: record.kind,
            spot: spot,
            on: tile,
            tastedCount: tastedCount,
            occupied: occupied,
            reserved: reserved,
            plan: yardPlan
        )
    }

    private func paint(from: CGPoint, to: CGPoint, in viewSize: CGSize) {
        let start = tile(at: from, in: viewSize)
        let end = tile(at: to, in: viewSize)
        let steps = max(abs(end.column - start.column), abs(end.row - start.row))
        var last: FarmTile?
        for index in 0...steps {
            let column = steps == 0 ? end.column : start.column + (end.column - start.column) * index / steps
            let row = steps == 0 ? end.row : start.row + (end.row - start.row) * index / steps
            let painted = FarmTile(column: column, row: row)
            if painted != last {
                if last != nil {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if case .paint(let kind) = tool {
                    paintStroke[painted] = kind
                }
                last = painted
            }
        }
    }

    private func commitPaint() {
        guard !paintStroke.isEmpty else { return }
        let stroke = paintStroke
        paintStroke = [:]
        commit { records in
            for (tile, kind) in stroke {
                records.removeAll { $0.kind.isTerrain && $0.tile == tile }
                if let kind {
                    records.append(FarmRecord(id: UUID(), kind: kind, varietyID: nil, tile: tile))
                }
            }
        }
    }

    private func commit(_ change: (inout [FarmRecord]) -> Void) {
        var next = records
        undo.append(next)
        change(&next)
        try? FarmLayout.write(next, in: context)
    }

    private func undoLast() {
        guard let previous = undo.popLast() else { return }
        try? FarmLayout.write(previous, in: context)
    }

    /// Placed sprites and painted cells, the yard that should fill the opening view.
    private func occupiedWorldPoints() -> [CGPoint] {
        var tiles = records.map(\.tile)
        if let house = records.first(where: { $0.kind == .house }) {
            tiles.append(contentsOf: FarmExpansion.footprint(kind: .house, anchor: house.tile))
        }
        tiles.append(contentsOf: displayTerrain.keys)
        if tiles.isEmpty {
            tiles = FarmExpansion.openingFocusTiles(for: yardPlan)
        }
        return tiles.map { IsoMap.center($0) }
    }

    private func landWorldPoints() -> [CGPoint] {
        FarmExpansion.plots(for: yardPlan).flatMap { plot in
            [
                FarmTile(column: plot.columns.lowerBound, row: plot.rows.lowerBound),
                FarmTile(column: plot.columns.upperBound, row: plot.rows.lowerBound),
                FarmTile(column: plot.columns.upperBound, row: plot.rows.upperBound),
                FarmTile(column: plot.columns.lowerBound, row: plot.rows.upperBound)
            ].map { IsoMap.center($0) }
        }
    }

    private func fittedCamera(in viewSize: CGSize) -> FarmCamera {
        cameraFitting(occupiedWorldPoints(), in: viewSize, margin: IsoMap.tileWidth)
    }

    /// Zoom at which every unlockable plot fits on screen.
    private func landScale(in viewSize: CGSize) -> CGFloat {
        let points = landWorldPoints()
        guard viewSize.width > 1,
              let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return fitScale(in: viewSize) * FarmZoom.minimum
        }
        let spanX = max(maxX - minX, 1) + IsoMap.tileWidth * 2
        let spanY = max(maxY - minY, 1) + IsoMap.tileHeight * 2
        let height = max(viewSize.height - 120, 1)
        return min(viewSize.width * 0.92 / spanX, height * 0.92 / spanY)
    }

    private func cameraFitting(_ focus: [CGPoint], in viewSize: CGSize, margin: CGFloat) -> FarmCamera {
        guard viewSize.width > 1,
              let minX = focus.map(\.x).min(),
              let maxX = focus.map(\.x).max(),
              let minY = focus.map(\.y).min(),
              let maxY = focus.map(\.y).max() else {
            return FarmCamera(scale: 1, center: .zero, pan: .zero)
        }
        let span = max(maxX - minX, 1) + margin * 2
        let fitted = DebugLaunch.farmZoom ?? min(FarmZoom.maximum, (viewSize.width * 0.90) / span)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return FarmCamera(scale: fitted, center: center, pan: .zero)
    }

    private func frameHouse(in viewSize: CGSize) {
        guard !framed, viewSize.width > 1, viewSize.height > 1 else { return }
        let fitted = fittedCamera(in: viewSize)
        framed = true
        scale = fitted.scale
        lastScale = fitted.scale
        worldCenter = fitted.center
        offset = .zero
        lastOffset = .zero
    }
}

private struct MapGestureOverlay: UIViewRepresentable {
    var brush: Bool
    var onPinch: (CGFloat, CGPoint, UIGestureRecognizer.State) -> Void
    var onTwoPan: (CGSize, UIGestureRecognizer.State) -> Void
    var onOnePan: (CGPoint, CGPoint, CGSize, UIGestureRecognizer.State) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onSingleTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let two = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.twoPan(_:)))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        let one = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onePan(_:)))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap(_:)))
        singleTap.require(toFail: doubleTap)
        one.require(toFail: doubleTap)
        pinch.delegate = context.coordinator
        two.delegate = context.coordinator
        context.coordinator.pinch = pinch
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(two)
        view.addGestureRecognizer(one)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestureOverlay
        var pinch: UIPinchGestureRecognizer?
        var oneStart: CGPoint?

        init(_ parent: MapGestureOverlay) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let pinchInvolved = gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
            let twoPan = (gestureRecognizer as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
                || (other as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
            return pinchInvolved && twoPan
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            parent.onPinch(gesture.scale, gesture.location(in: gesture.view), gesture.state)
        }

        @objc func twoPan(_ gesture: UIPanGestureRecognizer) {
            if let pinch, pinch.state == .began || pinch.state == .changed { return }
            let t = gesture.translation(in: gesture.view)
            parent.onTwoPan(CGSize(width: t.x, height: t.y), gesture.state)
        }

        @objc func onePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            if gesture.state == .began {
                oneStart = point
            }
            let start = oneStart ?? point
            let t = gesture.translation(in: gesture.view)
            parent.onOnePan(start, point, CGSize(width: t.x, height: t.y), gesture.state)
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                oneStart = nil
            }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap(gesture.location(in: gesture.view))
        }

        @objc func singleTap(_ gesture: UITapGestureRecognizer) {
            guard !parent.brush else { return }
            parent.onSingleTap(gesture.location(in: gesture.view))
        }
    }
}
