import SwiftData
import SwiftUI

private enum FarmTool: String, CaseIterable {
    case move = "Move"
    case fence = "Fence"
    case path = "Path"
}

private enum MapGesture {
    case undecided
    case pan
    case moveItem
    case place
}

struct FarmScreen: View {
    @Query private var placements: [FarmPlacement]
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @Environment(\.modelContext) private var context
    @State private var previewStarter = FarmExpansion.starterRecords()
    @State private var editing = false
    @State private var tool: FarmTool = .move
    @State private var undo: [[FarmRecord]] = []
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var worldCenter: CGPoint = .zero
    @State private var framed = false
    @State private var userMoved = false
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
            ZStack {
                FarmColor.freshGrass
                FarmMapView(
                    records: displayRecords,
                    plants: plants,
                    tastedCount: tastedCount,
                    hover: hover,
                    hoverValid: hoverValid,
                    dragging: dragging,
                    showsNames: scale >= 1.25,
                    detailed: scenery,
                    camera: resolvedCamera(in: geo.size),
                    canvasSize: geo.size
                )
            }
            .contentShape(Rectangle())
            .gesture(drag(in: geo.size))
            .simultaneousGesture(pinch)
            .onAppear { frameHouse(in: geo.size) }
            .onChange(of: frameRequest) { _, _ in frameHouse(in: geo.size) }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { editBar }
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
            HStack(spacing: 8) {
                ForEach(FarmTool.allCases, id: \.self) { item in
                    Button(item.rawValue) { tool = item }
                        .font(.system(size: 14, weight: tool == item ? .semibold : .regular))
                        .foregroundStyle(tool == item ? OrchardColor.grassDeep : OrchardColor.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                Button("Undo") { undoLast() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(undo.isEmpty ? Color.secondary : OrchardColor.ink)
                    .disabled(undo.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
    }

    private func drag(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = hypot(value.translation.width, value.translation.height)
                if gesture == .undecided {
                    if editing, tool == .move, let hit = item(at: value.startLocation, in: viewSize) {
                        gesture = .moveItem
                        dragging = hit.id
                    } else if travel > 8 {
                        gesture = .pan
                        userMoved = true
                    }
                }
                switch gesture {
                case .pan:
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                case .moveItem:
                    let tile = tile(at: value.location, in: viewSize)
                    hover = tile
                    hoverValid = placementValid(tile)
                case .place, .undecided:
                    break
                }
            }
            .onEnded { value in
                let travel = hypot(value.translation.width, value.translation.height)
                switch gesture {
                case .pan:
                    lastOffset = offset
                case .moveItem:
                    if hoverValid, let hover, let dragging, records.first(where: { $0.id == dragging })?.tile != hover {
                        commit { records in
                            guard let index = records.firstIndex(where: { $0.id == dragging }) else { return }
                            records[index].tile = hover
                        }
                    }
                case .undecided, .place:
                    if travel < 14 {
                        if editing, tool != .move {
                            placeTool(at: tile(at: value.location, in: viewSize))
                        } else if !editing, let slug = plantSlug(at: value.startLocation, in: viewSize) {
                            selected = VarietyLink(id: slug)
                        }
                    }
                }
                clearGesture()
            }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                userMoved = true
                scale = min(1.7, max(0.32, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }
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
            FarmSprite.grass, FarmSprite.fence, FarmSprite.tractor, FarmSprite.bush, FarmSprite.rock,
            FarmSprite.sapling, FarmSprite.soilTree, FarmSprite.soilVine, FarmSprite.emptyBed, FarmSprite.stonePath,
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
        var occupied = Set(records.map(\.tile))
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

    private func placeTool(at tile: FarmTile) {
        let kind: FarmItemKind = tool == .fence ? .fence : .path
        let occupied = Set(records.map(\.tile))
        let reserved = FarmExpansion.reservedTiles(in: records)
        guard FarmExpansion.canPlace(kind: kind, spot: nil, on: tile, tastedCount: tastedCount, occupied: occupied, reserved: reserved) else { return }
        commit { records in
            records.append(FarmRecord(id: UUID(), kind: kind, varietyID: nil, tile: tile))
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

    private func fittedCamera(in viewSize: CGSize) -> FarmCamera {
        let focus = FarmExpansion.openingFocusTiles(for: yardPlan).map { IsoMap.center($0) }
        guard viewSize.width > 1,
              let minX = focus.map(\.x).min(),
              let maxX = focus.map(\.x).max(),
              let minY = focus.map(\.y).min(),
              let maxY = focus.map(\.y).max() else {
            return FarmCamera(scale: 1, center: .zero, pan: .zero)
        }
        let span = max(maxX - minX, 1)
        let padded = span + IsoMap.tileWidth * 2.2
        let fitted = DebugLaunch.farmZoom ?? min(1.6, (viewSize.width * 0.90) / padded)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2 - IsoMap.tileHeight * 0.6)
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
