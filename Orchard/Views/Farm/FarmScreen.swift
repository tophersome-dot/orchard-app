import SwiftData
import SwiftUI
import UIKit

private struct FarmEditSnapshot {
    var records: [FarmRecord]
    var decor: [DecorRecord]
    var stored: [StoredRecord]
    var skipped: [String]
}

private enum FarmTool: Hashable {
    case move
    case paint(FarmItemKind?)
    case clear
    case decor(String)

    static let palette: [FarmTool] = [
        .move,
        .paint(.path),
        .paint(.dirt),
        .paint(.sand),
        .paint(.longgrass),
        .paint(.tilled),
        .paint(nil),
        .clear
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
        case .clear, .decor:
            nil
        }
    }
}

private enum MapGesture {
    case undecided
    case pan
    case moveItem
    case place
}

/// Pinch limits are multiples of the geometric fit. `-farmZoom` is an absolute scale and is not multiplied by it.
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
    @Query private var decorItems: [FarmDecor]
    @Query private var storedItems: [FarmStoredItem]
    @Query private var skippedPlants: [FarmSkippedPlant]
    @Query private var worlds: [FarmWorld]
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @Environment(\.modelContext) private var context
    @State private var previewStarter = FarmExpansion.starterRecords()
    @State private var editing = DebugLaunch.editSelection || DebugLaunch.axeClear || DebugLaunch.showStorage || DebugLaunch.demoTerrain
    @State private var tool: FarmTool = DebugLaunch.axeClear ? .clear : .move
    @State private var paintStroke: [FarmTile: FarmItemKind?] = [:]
    @State private var decorStroke: [FarmTile: String] = [:]
    @State private var clearTiles: Set<FarmTile> = []
    @State private var undo: [FarmEditSnapshot] = []
    @State private var chart = IslandChart.placeholder
    @State private var chartKey = ""
    @State private var selectedDecor: UUID?
    @State private var selectedRecord: UUID?
    @State private var draggingDecor = false
    @State private var honorLaunchZoom: Bool
    @State private var storageOpen = DebugLaunch.showStorage
    @State private var armedStorage: UUID?
    @State private var armedMove = false
    @State private var brushTile: FarmTile?
    @State private var sparks: [FarmSpark] = []
    @State private var falling: [FallingTree] = []
    @State private var bounces: [String: Date] = [:]
    @State private var sprouts: [String: Date] = [:]
    @State private var knownPlants: Set<UUID>?
    @State private var sawChart = false
    @State private var playedLevel: Int?
    @State private var allowGrowthBanner = false
    @State private var bannerText: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var minimapHidden = false
    @State private var soundOn = true
    @State private var deletePlant: FarmRecord?
    @State private var suppressTap = false
    @State private var seededStorage = false
    @State private var forcedHint = 0
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
        let saved = DebugLaunch.farmZoom == nil ? FarmViewMemory.load() : nil
        _scale = State(initialValue: saved?.scale ?? DebugLaunch.farmZoom ?? 1)
        _lastScale = State(initialValue: saved?.scale ?? DebugLaunch.farmZoom ?? 1)
        _offset = State(initialValue: saved?.pan ?? .zero)
        _lastOffset = State(initialValue: saved?.pan ?? .zero)
        _worldCenter = State(initialValue: saved?.center ?? .zero)
        _framed = State(initialValue: saved != nil)
        _userMoved = State(initialValue: saved != nil)
        _honorLaunchZoom = State(initialValue: DebugLaunch.farmZoom != nil)
        _minimapHidden = State(initialValue: UserDefaults.standard.bool(forKey: "orchard.minimap.hidden"))
        _soundOn = State(initialValue: FarmAudio.enabled)
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

    private var decorRecords: [DecorRecord] {
        launch.noWoods ? [] : decorItems.map(\.record)
    }

    private var openTiles: [FarmTile] {
        records.filter { $0.kind == .cleared }.map(\.tile)
    }

    private var yardPlan: YardPlan {
        var zones: [String: String] = [:]
        for variety in varieties {
            zones[variety.slug] = variety.zoneRaw
        }
        return FarmExpansion.plan(records: records, zones: zones, openTiles: Set(openTiles))
    }

    private var camera: FarmCamera {
        FarmCamera(scale: scale, center: worldCenter, pan: offset)
    }

    private func resolvedCamera(in viewSize: CGSize) -> FarmCamera {
        let base = framed ? camera : fittedCamera(in: viewSize)
        if !userMoved, let zoom = launch.farmZoom, zoom > 0 {
            var shown = base
            shown.scale = CGFloat(zoom)
            return shown
        }
        return base
    }

    var body: some View {
        GeometryReader { geo in
            let shown = resolvedCamera(in: geo.size)
            let fit = fitScale(in: geo.size)
            let labelOpacity = min(1, max(0, (shown.scale - fit * 0.8) / (fit * 0.35)))
            ZStack {
                FarmColor.freshGrass
                FarmMapView(
                    records: displayRecords,
                    plants: plants,
                    tastedCount: tastedCount,
                    hover: hover,
                    hoverValid: hoverValid,
                    dragging: dragging,
                    showsNames: labelOpacity > 0.04,
                    labelOpacity: labelOpacity,
                    detailed: scenery,
                    camera: shown,
                    canvasSize: geo.size,
                    terrain: displayTerrain,
                    hoverTiles: hoverFootprint,
                    decor: displayDecor,
                    chart: chart,
                    shoreSeed: UInt64(bitPattern: Int64(worlds.first?.seed ?? 1)),
                    motion: FarmMotionState(
                        liftedID: dragging?.uuidString,
                        bounces: bounces,
                        sprouts: sprouts,
                        reduceMotion: UIAccessibility.isReduceMotionEnabled
                    ),
                    ghost: brushGhost,
                    showsGrid: showsEditing
                )
                .offset(x: shakeOffset)
                FarmJuiceOverlay(
                    sparks: sparks,
                    falling: falling,
                    brush: brushPoint(in: geo.size, camera: shown),
                    banner: bannerText,
                    selected: selectionTile,
                    camera: shown,
                    canvasSize: geo.size,
                    reduceMotion: UIAccessibility.isReduceMotionEnabled
                )
                MapGestureOverlay(
                    brush: (showsClearTool || isPaintTool) && showsEditing,
                    onPinch: { magnification, point, state in
                        handlePinch(magnification, at: point, state: state, in: geo.size)
                    },
                    onTwoPan: { translation, state in
                        handleTwoPan(translation, state: state)
                    },
                    onOnePan: { start, current, translation, state in
                        handleOnePan(start: start, current: current, translation: translation, state: state, in: geo.size)
                    },
                    onLongPress: { point, state in
                        handleLongPress(point, state: state, in: geo.size)
                    },
                    onDoubleTap: { point in
                        toggleZoom(at: point, in: geo.size)
                    },
                    onSingleTap: { point in
                        handleSingleTap(point, in: geo.size)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                mapSize = geo.size
                launch.refresh()
                OrchardTiming.log("launch args \(ProcessInfo.processInfo.arguments.joined(separator: " | ")) ring \(launch.resolvedLevel(tastedCount: tastedCount)) edit \(launch.editSelection) zoom \(String(describing: launch.farmZoom))")
                updateChart()
                if DebugLaunch.farmZoom != nil {
                    applyFarmZoom(in: geo.size)
                } else {
                    frameHouse(in: geo.size)
                }
                if DebugLaunch.demoTerrain { editing = true }
                applyDebugChrome()
            }
            .onDisappear { saveCamera() }
            .onChange(of: geo.size) { _, newSize in mapSize = newSize }
            .onChange(of: frameRequest) { _, _ in frameHouse(in: geo.size) }
            .onChange(of: worlds.first?.seed) { _, _ in updateChart() }
            .onChange(of: tastedCount) { _, _ in updateChart() }
            .onChange(of: plantKey) { _, key in
                noteNewPlants(key)
            }
            .task { trackLaunchFlags() }
        }
        .coordinateSpace(name: "farm")
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) {
            if let step = activeHint, step != .edit, !showsEditing {
                FarmHintChip(step: step, onDismiss: advanceHint)
                    .padding(.bottom, step == .pinch ? 12 : 64)
            }
        }
        .overlay(alignment: .topTrailing) {
            if activeHint == .edit, !showsEditing {
                FarmHintChip(step: .edit, onDismiss: advanceHint)
                    .padding(.trailing, 16)
                    .padding(.top, 62)
            }
        }
        .overlay(alignment: .topTrailing) {
            minimapOverlay
                .padding(.trailing, 12)
                .padding(.top, 64)
        }
        .overlay(alignment: .bottom) { bottomChrome }
        .overlay(alignment: .bottomTrailing) {
            if !showsStorage { zoomButtons }
        }
        .overlay(alignment: .center) { selectionChrome }
        .sheet(item: $selected) { link in
            VarietyDetailView(slug: link.id)
        }
        .confirmationDialog(
            "Remove this plant from the farm?",
            isPresented: Binding(
                get: { deletePlant != nil },
                set: { if !$0 { deletePlant = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletePlant { performDelete(deletePlant) }
                deletePlant = nil
            }
            Button("Cancel", role: .cancel) { deletePlant = nil }
        } message: {
            Text("This takes it off the map only. The tasting stays in your collection.")
        }
        .task(id: triedSignature) {
            // The grass frame commits before any PNG decode or store rewrite.
            await Task.yield()
            OrchardTiming.log("farm first frame")
            await FarmSprite.warm(spritesToWarm())
            if !scenery {
                scenery = true
            }
            if DebugLaunch.farmZoom == nil, !userMoved {
                framed = false
                frameRequest += 1
            }
            await Task.yield()
            guard !varieties.isEmpty else { return }
            let tried = varieties.filter(\.isTried).map { (id: $0.slug, zone: $0.zoneRaw) }
            try? await FarmLayout.sync(context: context, tried: tried)
            updateChart()
            applyDebugChrome()
            if DebugLaunch.farmZoom == nil, !userMoved {
                framed = false
                frameRequest += 1
            }
        }
    }

    private var displayTerrain: [FarmTile: FarmItemKind] {
        var map: [FarmTile: FarmItemKind] = [:]
        for record in displayRecords where record.kind.isTerrain {
            if launch.noWoods && record.kind == .forest { continue }
            if chart.water.contains(record.tile) && record.kind != .lake && record.kind != .creek { continue }
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

    private var displayDecor: [DecorRecord] {
        guard draggingDecor, let dragging, let hover else { return decorRecords }
        return decorRecords.map { record in
            guard record.id == dragging else { return record }
            var moved = record
            moved.tile = hover
            return moved
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

    /// Same object the chart log prints. Reading it here is what refreshes the ring.
    private var launch: LaunchOverrides { LaunchOverrides.shared }

    /// The island level. `-islandLevel` wins over the collection count, including in the ring.
    private var islandLevel: Int {
        launch.resolvedLevel(tastedCount: tastedCount)
    }

    /// Edit chrome follows the shared flags even if this view's `@State` was created earlier.
    private var showsEditing: Bool {
        editing || launch.editSelection || launch.showStorage || launch.axeClear || launch.demoTerrain
    }

    private var showsStorage: Bool {
        storageOpen || launch.showStorage
    }

    private var showsClearTool: Bool {
        tool == .clear || (launch.axeClear && tool == .move)
    }

    private var topBar: some View {
        let clearing = FarmExpansion.clearingTiles(for: yardPlan)
        let radius = Woodland.radius(level: islandLevel, around: clearing)
        let next = radius >= Woodland.radiusCap ? "Island is full" : "Next shore +\(Int(Woodland.radiusGrowth)) tiles"
        return FarmLevelHeader(
            level: islandLevel,
            progress: radius / Woodland.radiusCap,
            detail: "Level \(islandLevel) · \(tastedCount) collected · \(next)",
            soundOn: soundOn,
            editing: showsEditing,
            onSound: {
                soundOn.toggle()
                FarmAudio.enabled = soundOn
                FarmAudio.tick()
            },
            onEdit: toggleEditing
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if showsStorage {
                FarmStorageTray(
                    stacks: storageStacks,
                    onClose: { storageOpen = false },
                    onTap: { id in
                        armedStorage = id
                        storageOpen = false
                        FarmAudio.tick()
                    },
                    onDrag: { id, point, ended in
                        armedStorage = id
                        let tile = self.tile(at: point, in: mapSize)
                        brushTile = tile
                        hover = tile
                        hoverValid = storageValid(id, on: tile)
                        if ended {
                            placeStored(id, on: tile)
                        }
                    }
                )
                .padding(.horizontal, 12)
            }
            if showsEditing {
                if isPaintTool && !showsClearTool {
                    paletteRow
                } else if showsClearTool {
                    Text("Tap trees or rocks to clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OrchardColor.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                FarmEditToolbar(
                    moveOn: tool == .move && !showsClearTool,
                    paintOn: isPaintTool && !showsClearTool,
                    axeOn: showsClearTool,
                    storageOn: showsStorage,
                    canUndo: !undo.isEmpty,
                    onMove: { selectTool(.move) },
                    onPaint: { selectTool(.paint(.path)) },
                    onAxe: { selectTool(.clear) },
                    onStorage: {
                        storageOpen.toggle()
                        FarmAudio.tick()
                    },
                    onUndo: { undoLast() },
                    onDone: toggleEditing
                )
                .padding(.horizontal, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
        .animation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: showsEditing)
    }

    private var isPaintTool: Bool {
        if case .paint = tool { return true }
        if case .decor = tool { return true }
        return false
    }

    private var paletteRow: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FarmTool.palette, id: \.self) { item in
                        if item != .move && item != .clear {
                            Button {
                                selectTool(item)
                            } label: {
                                toolLabel(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DecorSprite.Category.allCases.filter { $0 != .water }, id: \.self) { category in
                        Text(category.rawValue.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Woodland.palette(in: category)) { sprite in
                            Button {
                                selectTool(.decor(sprite.name))
                            } label: {
                                decorLabel(sprite)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var selectionChrome: some View {
        if let tile = selectionTile, showsEditing || armedMove {
            let point = resolvedCamera(in: mapSize).screenPoint(IsoMap.center(tile), in: mapSize)
            FarmSelectionButtons(
                canFlip: selectedDecor != nil,
                canStore: canStoreSelection,
                onMove: {
                    armedMove = true
                    tool = .move
                    FarmAudio.tick()
                },
                onFlip: flipSelected,
                onRotate: rotateSelected,
                onStore: storeSelection,
                onDelete: deleteSelection
            )
            .fixedSize()
            .offset(x: point.x - mapSize.width / 2, y: max(108, point.y - 50) - mapSize.height / 2)
        }
    }

    private var activeHint: FarmHintStep? {
        guard !showsEditing else { return nil }
        let index = DebugLaunch.showHints ? forcedHint : UserDefaults.standard.integer(forKey: "orchard.hint.step")
        return FarmHintStep(rawValue: index)
    }

    private func advanceHint() {
        if DebugLaunch.showHints {
            forcedHint += 1
        } else {
            let next = UserDefaults.standard.integer(forKey: "orchard.hint.step") + 1
            UserDefaults.standard.set(next, forKey: "orchard.hint.step")
        }
        FarmAudio.tick()
    }

    @ViewBuilder
    private var minimapOverlay: some View {
        let shown = resolvedCamera(in: mapSize)
        let fit = fitScale(in: mapSize)
        let wide = islandScreenSpan(at: fit) > mapSize.width * 1.5
        if wide, mapSize.width > 1 {
            if minimapHidden {
                FarmMinimapRestore {
                    minimapHidden = false
                    UserDefaults.standard.set(false, forKey: "orchard.minimap.hidden")
                }
            } else {
                FarmMinimap(
                    ground: chart.ground,
                    water: chart.water,
                    woods: chart.groves,
                    farm: FarmExpansion.clearingTiles(for: yardPlan),
                    camera: shown,
                    mapSize: mapSize,
                    onJump: { world in
                        honorLaunchZoom = false
                        userMoved = true
                        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.4, dampingFraction: 0.86)) {
                            worldCenter = world
                            offset = .zero
                            lastOffset = .zero
                        }
                        saveCamera()
                    },
                    onHide: {
                        minimapHidden = true
                        UserDefaults.standard.set(true, forKey: "orchard.minimap.hidden")
                    }
                )
            }
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
            } else if item == .clear {
                Label("Clear", systemImage: "axe.fill")
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

    private func decorLabel(_ sprite: DecorSprite) -> some View {
        let selected = tool == .decor(sprite.name)
        return Image(sprite.name)
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
            .frame(width: 36, height: 36)
            .padding(2)
            .background(selected ? Color.white.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func handleOnePan(start: CGPoint, current: CGPoint, translation: CGSize, state: UIGestureRecognizer.State, in viewSize: CGSize) {
        let travel = hypot(translation.width, translation.height)
        if gesture != .moveItem, state == .began || gesture == .undecided {
            if showsEditing, showsClearTool || isPaintTool {
                gesture = .place
            } else if let found = pickedUp(at: start, in: viewSize) {
                beginMove(found)
            } else if armedMove, let id = selectedDecor ?? selectedRecord {
                gesture = .moveItem
                dragging = id
                draggingDecor = selectedDecor != nil
                armedMove = false
            } else if travel > 6 {
                gesture = .pan
                userMoved = true
                honorLaunchZoom = false
            }
        }
        switch gesture {
        case .pan:
            userMoved = true
            honorLaunchZoom = false
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
            brushTile = tile(at: current, in: viewSize)
            let origin = oneFingerPoint ?? start
            paint(from: origin, to: current, in: viewSize)
            oneFingerPoint = current
        case .undecided:
            break
        }
        if state == .ended || state == .cancelled || state == .failed {
            finishGesture()
        }
    }

    private func pickedUp(at start: CGPoint, in viewSize: CGSize) -> FarmHit? {
        let editingMove = showsEditing && tool == .move && !showsClearTool
        let direct = !showsEditing && gesture == .undecided && false
        guard editingMove || direct else { return nil }
        return hit(at: start, in: viewSize)
    }

    private func beginMove(_ found: FarmHit) {
        gesture = .moveItem
        switch found {
        case .record(let record):
            dragging = record.id
            draggingDecor = false
            selectedRecord = record.id
            selectedDecor = nil
        case .decor(let decor):
            dragging = decor.id
            draggingDecor = true
            selectedDecor = decor.id
            selectedRecord = nil
        }
    }

    private func handleLongPress(_ point: CGPoint, state: UIGestureRecognizer.State, in viewSize: CGSize) {
        switch state {
        case .began:
            guard let found = hit(at: point, in: viewSize) else { return }
            switch found {
            case .record(let record):
                guard !record.kind.isTerrain, record.kind != .fence, record.kind != .cleared else {
                    reject()
                    return
                }
            case .decor:
                break
            }
            beginMove(found)
            suppressTap = true
            hover = tile(at: point, in: viewSize)
            if let hover { hoverValid = placementValid(hover) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            guard gesture == .moveItem else { return }
            let next = tile(at: point, in: viewSize)
            hover = next
            hoverValid = placementValid(next)
        case .ended:
            finishGesture()
        case .cancelled, .failed:
            if gesture == .moveItem {
                finishGesture()
            }
        default:
            break
        }
    }

    private func finishGesture() {
        let finished = gesture
        oneFingerPoint = nil
        if finished == .pan {
            lastOffset = offset
            saveCamera()
        } else if finished == .moveItem, draggingDecor {
            if hoverValid, let hover, let dragging, let moving = decorRecords.first(where: { $0.id == dragging }), moving.tile != hover {
                var next = decorRecords
                if let index = next.firstIndex(where: { $0.id == dragging }) {
                    next[index].tile = hover
                    next[index].origin = "placed"
                    commitDecor(next)
                    placed(dragging, on: hover)
                }
            } else if hover != nil, hoverValid == false {
                reject()
            }
        } else if finished == .moveItem {
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
                placed(dragging, on: hover)
            } else if let hover, let dragging, let moving = records.first(where: { $0.id == dragging }), moving.tile != hover, !hoverValid {
                reject()
            }
        } else if finished == .place {
            let painted = !paintStroke.isEmpty || !decorStroke.isEmpty || !clearTiles.isEmpty
            if case .decor = tool {
                commitDecorStroke()
            } else if showsClearTool {
                commitClear()
            } else {
                commitPaint()
            }
            brushTile = nil
            if !painted { reject() }
        }
        if finished != .undecided {
            clearGesture()
        }
    }

    private func handleTwoPan(_ translation: CGSize, state: UIGestureRecognizer.State) {
        userMoved = true
        honorLaunchZoom = false
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
            honorLaunchZoom = false
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
        let island = islandCamera(in: viewSize).scale
        let farm = fittedCamera(in: viewSize).scale
        return (min(island, farm), max(farm, island) * FarmZoom.maximum)
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
        honorLaunchZoom = false
        _ = point
        let farm = fittedCamera(in: viewSize)
        let island = islandCamera(in: viewSize)
        let atFarm = abs(scale - farm.scale) < max(0.04, farm.scale * 0.12)
        let next = atFarm ? island : farm
        withAnimation(.easeInOut(duration: 0.28)) {
            scale = next.scale
            worldCenter = next.center
            offset = .zero
            lastScale = next.scale
            lastOffset = .zero
            framed = true
        }
        saveCamera(scale: next.scale, center: next.center, pan: .zero)
    }

    private func nudgeZoom(_ factor: CGFloat) {
        guard mapSize.width > 1 else { return }
        userMoved = true
        honorLaunchZoom = false
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
            zoomButton("location") { recentre() }
            zoomButton("plus") { nudgeZoom(1.25) }
            zoomButton("minus") { nudgeZoom(1 / 1.25) }
        }
        .padding(.trailing, 12)
        .padding(.bottom, showsEditing ? 168 : 12)
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
        draggingDecor = false
        hover = nil
        hoverValid = false
        if armedStorage == nil {
            brushTile = nil
        }
    }

    private func trackLaunchFlags() async {
        var seen = ""
        for _ in 0..<40 {
            launch.refresh()
            let stamp = "\(launch.islandLevel ?? -1)|\(launch.editSelection)|\(launch.showStorage)|\(launch.axeClear)|\(launch.farmZoom ?? -1)"
            if stamp != seen {
                seen = stamp
                applyDebugChrome()
                updateChart()
                if launch.farmZoom != nil, !userMoved {
                    honorLaunchZoom = true
                    applyFarmZoom(in: mapSize)
                }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func updateChart() {
        launch.refresh()
        let level = launch.resolvedLevel(tastedCount: tastedCount)
        let seed = worlds.first?.seed ?? 1
        let clearing = FarmExpansion.clearingTiles(for: yardPlan)
        let blocked = Woodland.blockedTiles(records: records, plan: yardPlan)
        let woods = !launch.noWoods
        let key = IslandChartCache.cacheKey(seed: seed, level: level, clearing: clearing, blocked: blocked, woods: woods)
        if key == chartKey, !chart.ground.isEmpty { return }
        chartKey = key
        OrchardTiming.log("chart request level \(level) radius \(String(format: "%.1f", Woodland.radius(level: level, around: clearing))) seed \(seed) ring \(launch.resolvedLevel(tastedCount: tastedCount))")
        Task {
            let next = await IslandChartCache.chart(key: key) {
                Woodland.make(
                    seed: UInt64(bitPattern: Int64(seed)),
                    level: level,
                    clearing: clearing,
                    blocked: blocked,
                    woods: woods
                )
            }
            guard chartKey == key else { return }
            let previousLevel = playedLevel
            if playedLevel == nil {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    allowGrowthBanner = true
                }
            }
            playedLevel = level
            chart = next
            sawChart = true
            let shownScale = resolvedCamera(in: mapSize).scale
            let ring = launch.resolvedLevel(tastedCount: tastedCount)
            OrchardTiming.log(String(format: "chart apply level %d radius %.1f ground %d shown %.3f ring %d", level, Woodland.radius(level: level, around: clearing), next.ground.count, Double(shownScale), ring))
            if honorLaunchZoom, DebugLaunch.farmZoom != nil {
                applyFarmZoom(in: mapSize)
            } else if !userMoved {
                framed = false
                frameHouse(in: mapSize)
            }
            applyDebugChrome()
            if allowGrowthBanner, let previousLevel, level > previousLevel, launch.islandLevel == nil {
                celebrateGrowth()
            }
        }
    }

    /// `-farmZoom` wins over the saved camera and the fit-to-farm scale.
    private func applyFarmZoom(in viewSize: CGSize) {
        launch.refresh()
        guard let zoom = launch.farmZoom, zoom > 0, viewSize.width > 1, viewSize.height > 1 else { return }
        let focus = cameraFitting(farmWorldPoints(), in: viewSize, margin: 0, fill: 0.90)
        scale = CGFloat(zoom)
        lastScale = CGFloat(zoom)
        worldCenter = focus.center
        offset = .zero
        lastOffset = .zero
        framed = true
        let shown = resolvedCamera(in: viewSize).scale
        OrchardTiming.log(String(format: "farmZoom %.3f shown %.3f ring %d", zoom, Double(shown), launch.resolvedLevel(tastedCount: tastedCount)))
    }

    private func tile(at location: CGPoint, in viewSize: CGSize) -> FarmTile {
        IsoMap.tile(at: resolvedCamera(in: viewSize).worldPoint(location, in: viewSize))
    }

    private enum FarmHit {
        case record(FarmRecord)
        case decor(DecorRecord)
    }

    private func hit(at location: CGPoint, in viewSize: CGSize) -> FarmHit? {
        let view = resolvedCamera(in: viewSize)
        let movable = records.filter { record in
            !record.kind.isTerrain && record.kind != .fence && record.kind != .cleared
        }
        let recordHit = movable.min { lhs, rhs in
            distance(view.screenPoint(IsoMap.center(lhs.tile), in: viewSize), location)
                < distance(view.screenPoint(IsoMap.center(rhs.tile), in: viewSize), location)
        }
        let decorHit = decorRecords.min { lhs, rhs in
            distance(view.screenPoint(IsoMap.center(lhs.tile), in: viewSize), location)
                < distance(view.screenPoint(IsoMap.center(rhs.tile), in: viewSize), location)
        }
        let recordDistance = recordHit.map { distance(view.screenPoint(IsoMap.center($0.tile), in: viewSize), location) }
        let decorDistance = decorHit.map { distance(view.screenPoint(IsoMap.center($0.tile), in: viewSize), location) }
        if let decorHit, let decorDistance, decorDistance < 48, decorDistance <= (recordDistance ?? 1000) {
            return .decor(decorHit)
        }
        if let recordHit, let recordDistance, recordDistance < 44 {
            return .record(recordHit)
        }
        return nil
    }

    private func item(at location: CGPoint, in viewSize: CGSize) -> FarmRecord? {
        if case .record(let record) = hit(at: location, in: viewSize) { return record }
        return nil
    }

    private func spritesToWarm() -> [String] {
        var names = [
            FarmSprite.grass, FarmSprite.tractor, FarmSprite.bush, FarmSprite.rock,
            FarmSprite.sapling, FarmSprite.soilTree, FarmSprite.soilVine, FarmSprite.emptyBed,
            FarmSprite.pathTexture, FarmSprite.pathEdge, FarmSprite.terrainDirt, FarmSprite.terrainSand,
            FarmSprite.terrainLonggrass, FarmSprite.terrainTilled, FarmSprite.edgeDirt, FarmSprite.edgeSand,
            FarmSprite.edgeLonggrass, FarmSprite.edgeBed, FarmSprite.terrainForest, FarmSprite.edgeForest,
            FarmSprite.waterOcean, FarmSprite.waterLake, FarmSprite.edgeFoam, FarmSprite.edgeBankGrass, FarmSprite.edgeBankSand,
            "cliff_face_sw", "cliff_face_se", "cliff_corner_s", "wooden_bridge_ne", "wooden_bridge_nw",
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
        names.append(contentsOf: Woodland.catalog.map(\.name))
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
        guard let dragging else { return false }
        if draggingDecor {
            let house = records.first { $0.kind == .house }.map { FarmExpansion.footprint(kind: .house, anchor: $0.tile) } ?? []
            return chart.ground.contains(tile)
                && !chart.water.contains(tile)
                && !house.contains(tile)
                && !decorRecords.contains { $0.id != dragging && $0.tile == tile }
        }
        guard let record = records.first(where: { $0.id == dragging }) else { return false }
        if record.kind.isTerrain {
            if chart.water.contains(tile) { return record.kind == .path && chart.creek.contains(tile) }
            return !records.contains { $0.id != record.id && $0.kind.isTerrain && $0.tile == tile }
        }
        var occupied = Set(records.filter { !$0.kind.isTerrain && $0.kind != .cleared }.map(\.tile))
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
            plan: yardPlan,
            water: chart.water,
            creek: chart.creek,
            openTiles: Set(openTiles)
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
                if case .paint(let kind) = tool, canPaint(kind, on: painted) {
                    paintStroke[painted] = kind
                } else if case .decor(let name) = tool, chart.ground.contains(painted), !chart.water.contains(painted) {
                    decorStroke[painted] = name
                } else if showsClearTool, canClear(painted) {
                    clearTiles.insert(painted)
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
        let now = Date()
        for tile in stroke.keys {
            sparks.append(FarmSpark(kind: .ripple, tile: tile, born: now))
        }
        FarmAudio.swish()
        pruneSparks()
    }

    private func canPaint(_ kind: FarmItemKind?, on tile: FarmTile) -> Bool {
        if chart.lakes.contains(tile) || (!chart.ground.contains(tile) && !chart.creek.contains(tile)) { return false }
        if chart.creek.contains(tile) {
            return kind == .path
        }
        return true
    }

    private func canClear(_ tile: FarmTile) -> Bool {
        if chart.water.contains(tile) || !chart.ground.contains(tile) { return false }
        return records.contains { $0.kind == .forest && $0.tile == tile } || decorRecords.contains { $0.tile == tile }
    }

    private func commitClear() {
        guard !clearTiles.isEmpty else { return }
        let tiles = clearTiles
        clearTiles = []
        let nextDecor = decorRecords.filter { !tiles.contains($0.tile) }
        commit(nextDecor: nextDecor) { records in
            for tile in tiles {
                let hadForest = records.contains { $0.kind == .forest && $0.tile == tile }
                records.removeAll { $0.tile == tile && ($0.kind == .forest || $0.kind == .cleared) }
                if hadForest {
                    records.append(FarmRecord(id: UUID(), kind: .cleared, varietyID: nil, tile: tile))
                }
            }
        }
        let now = Date()
        let sprites = decorRecords.filter { tiles.contains($0.tile) }
        for item in sprites where Woodland.sprite(item.sprite)?.isTall == true {
            falling.append(FallingTree(tile: item.tile, sprite: item.sprite, born: now))
        }
        for tile in tiles {
            sparks.append(FarmSpark(kind: .leaf, tile: tile, born: now))
            sparks.append(FarmSpark(kind: .chip, tile: tile, born: now))
            sparks.append(FarmSpark(kind: .floater, tile: tile, born: now, text: "+1 cleared"))
        }
        FarmAudio.chop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pruneSparks()
    }

    private func commitDecorStroke() {
        guard !decorStroke.isEmpty else { return }
        let stroke = decorStroke
        decorStroke = [:]
        var next = decorRecords
        for (tile, name) in stroke {
            next.removeAll { $0.tile == tile }
            let roll = Double((tile.column * 17 &+ tile.row * 31) % 100) / 100
            next.append(DecorRecord(
                id: UUID(),
                sprite: name,
                tile: tile,
                scale: 0.85 + roll * 0.30,
                flipped: tile.column & 1 == 0,
                rotation: (roll - 0.5) * 0.35,
                origin: "placed"
            ))
        }
        commitDecor(next)
        let now = Date()
        for (tile, _) in stroke {
            sparks.append(FarmSpark(kind: .dust, tile: tile, born: now))
        }
        FarmAudio.pop()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        pruneSparks()
    }

    private func deleteSelectedDecor() {
        guard let selectedDecor else { return }
        commitDecor(decorRecords.filter { $0.id != selectedDecor })
        self.selectedDecor = nil
    }

    private func currentSnapshot() -> FarmEditSnapshot {
        FarmEditSnapshot(
            records: records,
            decor: decorRecords,
            stored: storedItems.map(\.record),
            skipped: skippedPlants.map(\.varietySlug)
        )
    }

    private func commitDecor(_ next: [DecorRecord]) {
        undo.append(currentSnapshot())
        try? FarmLayout.writeDecor(next, in: context)
    }

    private func commit(_ change: (inout [FarmRecord]) -> Void) {
        commit(nextDecor: nil, change)
    }

    private func commit(nextDecor: [DecorRecord]?, _ change: (inout [FarmRecord]) -> Void) {
        var next = records
        undo.append(currentSnapshot())
        change(&next)
        try? FarmLayout.write(next, in: context)
        if let nextDecor {
            try? FarmLayout.writeDecor(nextDecor, in: context)
        }
    }

    private func undoLast() {
        guard let previous = undo.popLast() else { return }
        try? FarmLayout.write(previous.records, in: context)
        try? FarmLayout.writeDecor(previous.decor, in: context)
        try? FarmLayout.writeStored(previous.stored, in: context)
        try? FarmLayout.writeSkipped(previous.skipped, in: context)
        FarmAudio.tick()
    }

    private var plantKey: String {
        records.filter { $0.kind == .plant }.map(\.id.uuidString).sorted().joined(separator: "|")
    }

    private var selectionTile: FarmTile? {
        if let selectedDecor, let decor = decorRecords.first(where: { $0.id == selectedDecor }) {
            return dragging == decor.id ? (hover ?? decor.tile) : decor.tile
        }
        if let selectedRecord, let record = records.first(where: { $0.id == selectedRecord }) {
            return dragging == record.id ? (hover ?? record.tile) : record.tile
        }
        return nil
    }

    private var canStoreSelection: Bool {
        if selectedDecor != nil { return true }
        guard let selectedRecord, let record = records.first(where: { $0.id == selectedRecord }) else { return false }
        return record.kind == .plant || record.kind == .bush || record.kind == .rock
    }

    private var brushGhost: FarmGhost? {
        if let armedStorage, let item = storedItems.first(where: { $0.id == armedStorage }), let tile = brushTile ?? hover {
            return FarmGhost(tile: tile, sprite: item.sprite, valid: storageValid(armedStorage, on: tile))
        }
        guard showsEditing, isPaintTool || showsClearTool, let brushTile else { return nil }
        let sprite: String?
        if case .decor(let name) = tool { sprite = name } else { sprite = nil }
        let valid: Bool
        if case .paint(let kind) = tool {
            valid = canPaint(kind, on: brushTile)
        } else if tool == .clear {
            valid = canClear(brushTile)
        } else {
            valid = chart.ground.contains(brushTile) && !chart.water.contains(brushTile)
        }
        return FarmGhost(tile: brushTile, sprite: sprite, valid: valid)
    }

    private func brushPoint(in viewSize: CGSize, camera: FarmCamera) -> CGPoint? {
        guard let tile = brushGhost?.tile else { return nil }
        return camera.screenPoint(IsoMap.center(tile), in: viewSize)
    }

    private var storageStacks: [StorageStack] {
        var grouped: [String: [FarmStoredItem]] = [:]
        for item in storedItems {
            let key = "\(item.kindRaw)|\(item.varietySlug ?? "")|\(item.sprite ?? "")"
            grouped[key, default: []].append(item)
        }
        return grouped.map { key, items in
            let sample = items[0]
            let title = sample.varietySlug?.replacingOccurrences(of: "-", with: " ")
                ?? sample.sprite?.replacingOccurrences(of: "_", with: " ")
                ?? sample.kindRaw
            let symbol = sample.kindRaw == "plant" ? "leaf" : "archivebox"
            return StorageStack(
                id: key,
                title: title.capitalized,
                systemImage: symbol,
                sprite: sample.sprite,
                count: items.count,
                sampleID: sample.id
            )
        }
        .sorted { $0.title < $1.title }
    }

    private func islandScreenSpan(at scale: CGFloat) -> CGFloat {
        let focus = focusWorldPoints()
        guard let minX = focus.map(\.x).min(), let maxX = focus.map(\.x).max() else { return 0 }
        return (maxX - minX) * scale
    }

    private func toggleEditing() {
        editing.toggle()
        FarmAudio.tick()
        if !editing {
            tool = .move
            storageOpen = false
            clearGesture()
            selectedDecor = nil
            selectedRecord = nil
        }
    }

    private func selectTool(_ next: FarmTool) {
        tool = next
        selectedDecor = nil
        selectedRecord = nil
        clearGesture()
        FarmAudio.tick()
    }

    private func handleSingleTap(_ point: CGPoint, in viewSize: CGSize) {
        if suppressTap {
            suppressTap = false
            return
        }
        if let armedStorage {
            placeStored(armedStorage, on: tile(at: point, in: viewSize))
            return
        }
        if showsEditing {
            if let found = hit(at: point, in: viewSize) {
                beginMove(found)
                dragging = nil
                gesture = .undecided
            } else {
                selectedDecor = nil
                selectedRecord = nil
            }
            return
        }
        guard let slug = plantSlug(at: point, in: viewSize) else { return }
        if let record = records.first(where: { $0.kind == .plant && $0.varietyID == slug }) {
            bounces[record.id.uuidString] = Date()
        }
        FarmAudio.pop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selected = VarietyLink(id: slug)
    }

    private func placed(_ id: UUID, on tile: FarmTile) {
        bounces[id.uuidString] = Date()
        sparks.append(FarmSpark(kind: .dust, tile: tile, born: Date()))
        FarmAudio.pop()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        pruneSparks()
    }

    private func reject() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        withAnimation(.linear(duration: 0.05)) { shakeOffset = 8 }
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.linear(duration: 0.05)) { shakeOffset = -7 }
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { shakeOffset = 0 }
        }
    }

    private func pruneSparks() {
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            let now = Date()
            sparks.removeAll { now.timeIntervalSince($0.born) > 1.15 }
            falling.removeAll { !$0.held && now.timeIntervalSince($0.born) > 0.8 }
        }
    }

    private func noteNewPlants(_ key: String) {
        let ids = Set(key.split(separator: "|").map { UUID(uuidString: String($0)) }.compactMap { $0 })
        defer { knownPlants = ids }
        guard let knownPlants else { return }
        let fresh = ids.subtracting(knownPlants)
        let now = Date()
        for id in fresh {
            sprouts[id.uuidString] = now
            if let tile = records.first(where: { $0.id == id })?.tile {
                sparks.append(FarmSpark(kind: .sparkle, tile: tile, born: now))
            }
        }
        if !fresh.isEmpty {
            FarmAudio.pop()
            pruneSparks()
        }
    }

    private func celebrateGrowth() {
        bannerText = "The island grew"
        FarmAudio.chime()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            bannerText = nil
        }
    }

    private func recentre() {
        guard mapSize.width > 1 else { return }
        honorLaunchZoom = false
        userMoved = true
        let fitted = fittedCamera(in: mapSize)
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.45, dampingFraction: 0.86)) {
            scale = fitted.scale
            lastScale = fitted.scale
            worldCenter = fitted.center
            offset = .zero
            lastOffset = .zero
            framed = true
        }
        saveCamera(scale: fitted.scale, center: fitted.center, pan: .zero)
        FarmAudio.tick()
    }

    private func flipSelected() {
        guard let selectedDecor else { return }
        var next = decorRecords
        guard let index = next.firstIndex(where: { $0.id == selectedDecor }) else { return }
        next[index].flipped.toggle()
        commitDecor(next)
        FarmAudio.tick()
    }

    private func rotateSelected() {
        guard let selectedDecor else { return }
        var next = decorRecords
        guard let index = next.firstIndex(where: { $0.id == selectedDecor }) else { return }
        next[index].rotation += .pi / 12
        commitDecor(next)
        FarmAudio.tick()
    }

    private func storeSelection() {
        if let selectedDecor, let decor = decorRecords.first(where: { $0.id == selectedDecor }) {
            var stored = storedItems.map(\.record)
            stored.append(StoredRecord(
                id: UUID(),
                kind: .bush,
                varietyID: nil,
                sprite: decor.sprite,
                scale: decor.scale,
                flipped: decor.flipped,
                rotation: decor.rotation
            ))
            undo.append(currentSnapshot())
            try? FarmLayout.writeDecor(decorRecords.filter { $0.id != decor.id }, in: context)
            try? FarmLayout.writeStored(stored, in: context)
            self.selectedDecor = nil
            FarmAudio.pop()
            return
        }
        guard let selectedRecord, let record = records.first(where: { $0.id == selectedRecord }) else { return }
        guard record.kind == .plant || record.kind == .bush || record.kind == .rock else {
            reject()
            return
        }
        var stored = storedItems.map(\.record)
        stored.append(StoredRecord(
            id: UUID(),
            kind: record.kind,
            varietyID: record.varietyID,
            sprite: nil,
            scale: 1,
            flipped: false,
            rotation: 0
        ))
        undo.append(currentSnapshot())
        var next = records
        next.removeAll { $0.id == record.id }
        try? FarmLayout.write(next, in: context)
        try? FarmLayout.writeStored(stored, in: context)
        self.selectedRecord = nil
        FarmAudio.pop()
    }

    private func deleteSelection() {
        if let selectedDecor, let decor = decorRecords.first(where: { $0.id == selectedDecor }) {
            commitDecor(decorRecords.filter { $0.id != decor.id })
            self.selectedDecor = nil
            FarmAudio.tick()
            return
        }
        guard let selectedRecord, let record = records.first(where: { $0.id == selectedRecord }) else { return }
        if record.kind == .plant {
            deletePlant = record
            return
        }
        performDelete(record)
    }

    private func performDelete(_ record: FarmRecord) {
        var next = records
        next.removeAll { $0.id == record.id }
        var skipped = skippedPlants.map(\.varietySlug)
        if record.kind == .plant, let slug = record.varietyID, !skipped.contains(slug) {
            skipped.append(slug)
        }
        undo.append(currentSnapshot())
        try? FarmLayout.write(next, in: context)
        try? FarmLayout.writeSkipped(skipped, in: context)
        if selectedRecord == record.id { selectedRecord = nil }
        FarmAudio.tick()
    }

    private func storageValid(_ id: UUID, on tile: FarmTile) -> Bool {
        guard let item = storedItems.first(where: { $0.id == id }) else { return false }
        if let sprite = item.sprite, item.varietySlug == nil {
            let house = records.first { $0.kind == .house }.map { FarmExpansion.footprint(kind: .house, anchor: $0.tile) } ?? []
            return chart.ground.contains(tile) && !chart.water.contains(tile) && !house.contains(tile)
                && !decorRecords.contains { $0.tile == tile }
        }
        var occupied = Set(records.filter { !$0.kind.isTerrain && $0.kind != .cleared }.map(\.tile))
        let spot = item.varietySlug.flatMap { plants[$0] }.map { FarmExpansion.spotKind(zone: $0.zone) }
        return FarmExpansion.canPlace(
            kind: item.record.kind,
            spot: spot,
            on: tile,
            tastedCount: tastedCount,
            occupied: occupied,
            reserved: FarmExpansion.reservedTiles(in: records),
            plan: yardPlan,
            water: chart.water,
            creek: chart.creek,
            openTiles: Set(openTiles)
        )
    }

    private func placeStored(_ id: UUID, on tile: FarmTile) {
        guard storageValid(id, on: tile), let item = storedItems.first(where: { $0.id == id }) else {
            reject()
            return
        }
        undo.append(currentSnapshot())
        var stored = storedItems.map(\.record)
        stored.removeAll { $0.id == id }
        try? FarmLayout.writeStored(stored, in: context)
        if let sprite = item.sprite, item.varietySlug == nil {
            var next = decorRecords
            let placedDecor = DecorRecord(
                id: UUID(),
                sprite: sprite,
                tile: tile,
                scale: item.scale,
                flipped: item.flipped,
                rotation: item.rotation,
                origin: "placed"
            )
            next.append(placedDecor)
            try? FarmLayout.writeDecor(next, in: context)
            bounces[placedDecor.id.uuidString] = Date()
        } else {
            let record = FarmRecord(id: UUID(), kind: item.record.kind, varietyID: item.varietySlug, tile: tile)
            var next = records
            next.append(record)
            if record.kind == .plant, let slug = record.varietyID {
                var skipped = skippedPlants.map(\.varietySlug)
                skipped.removeAll { $0 == slug }
                try? FarmLayout.writeSkipped(skipped, in: context)
            }
            try? FarmLayout.write(next, in: context)
            bounces[record.id.uuidString] = Date()
        }
        sparks.append(FarmSpark(kind: .dust, tile: tile, born: Date()))
        armedStorage = nil
        brushTile = nil
        FarmAudio.pop()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        pruneSparks()
    }

    private func applyDebugChrome() {
        launch.refresh()
        OrchardTiming.log("debug chrome edit \(launch.editSelection) storage \(launch.showStorage) axe \(launch.axeClear) hints \(launch.showHints) ring \(launch.resolvedLevel(tastedCount: tastedCount))")
        if launch.editSelection || launch.axeClear || launch.showStorage || launch.demoTerrain {
            editing = true
        }
        if launch.axeClear {
            tool = .clear
            if falling.isEmpty, let tree = decorRecords.first(where: { Woodland.sprite($0.sprite)?.isTall == true }) {
                falling.append(FallingTree(tile: tree.tile, sprite: tree.sprite, born: Date().addingTimeInterval(-0.32), held: true))
                sparks.append(FarmSpark(kind: .chip, tile: tree.tile, born: Date().addingTimeInterval(-0.2)))
                sparks.append(FarmSpark(kind: .floater, tile: tree.tile, born: Date().addingTimeInterval(-0.2), text: "+1 cleared"))
            }
        }
        if launch.showStorage {
            storageOpen = true
            seedDebugStorageIfNeeded()
        }
        if launch.editSelection, selectedRecord == nil, selectedDecor == nil {
            if let plant = records.first(where: { $0.kind == .plant }) {
                selectedRecord = plant.id
            } else if let decor = decorRecords.first {
                selectedDecor = decor.id
            }
        }
    }

    private func seedDebugStorageIfNeeded() {
        guard !seededStorage else { return }
        seededStorage = true
        guard storedItems.isEmpty else { return }
        let samples = [
            StoredRecord(id: UUID(), kind: .bush, varietyID: nil, sprite: "bush_a", scale: 1, flipped: false, rotation: 0),
            StoredRecord(id: UUID(), kind: .rock, varietyID: nil, sprite: "rock_medium_a", scale: 1, flipped: false, rotation: 0)
        ]
        try? FarmLayout.writeStored(samples, in: context)
    }

    /// House, plants, tractor and fences, padded by about two tiles. Not the whole island.
    private func farmWorldPoints() -> [CGPoint] {
        var tiles: [FarmTile] = records.compactMap { record in
            switch record.kind {
            case .house, .plant, .tractor, .fence: return record.tile
            default: return nil
            }
        }
        if let house = records.first(where: { $0.kind == .house }) {
            tiles.append(contentsOf: FarmExpansion.footprint(kind: .house, anchor: house.tile))
        }
        if tiles.isEmpty {
            tiles = Array(FarmExpansion.clearingTiles(for: yardPlan))
        }
        let centers = tiles.map { IsoMap.center($0) }
        guard let minX = centers.map(\.x).min(), let maxX = centers.map(\.x).max(),
              let minY = centers.map(\.y).min(), let maxY = centers.map(\.y).max() else {
            return occupiedWorldPoints()
        }
        let padX = IsoMap.tileWidth
        let padY = IsoMap.tileHeight
        return [
            CGPoint(x: minX - padX, y: minY - padY),
            CGPoint(x: maxX + padX, y: minY - padY),
            CGPoint(x: maxX + padX, y: maxY + padY),
            CGPoint(x: minX - padX, y: maxY + padY)
        ]
    }

    /// World bounds of the land itself. The square of min/max column and row is much wider than the island.
    private func focusWorldPoints() -> [CGPoint] {
        let clearingCount = FarmExpansion.clearingTiles(for: yardPlan).count
        let centers = chart.ground.map { IsoMap.center($0) }
        guard chart.ground.count > clearingCount + 20,
              let minX = centers.map(\.x).min(),
              let maxX = centers.map(\.x).max(),
              let minY = centers.map(\.y).min(),
              let maxY = centers.map(\.y).max() else {
            return occupiedWorldPoints()
        }
        let padX = IsoMap.halfWidth
        let padY = IsoMap.halfHeight
        return [
            CGPoint(x: minX - padX, y: minY - padY),
            CGPoint(x: maxX + padX, y: minY - padY),
            CGPoint(x: maxX + padX, y: maxY + padY),
            CGPoint(x: minX - padX, y: maxY + padY)
        ]
    }

    /// Placed sprites and painted cells, the yard that should fill the opening view.
    private func occupiedWorldPoints() -> [CGPoint] {
        let clearing = FarmExpansion.clearingTiles(for: yardPlan)
        var tiles = records.compactMap { record -> FarmTile? in
            switch record.kind {
            case .forest, .lake, .creek, .cleared:
                return nil
            case .dirt, .sand, .longgrass:
                return clearing.contains(record.tile) ? record.tile : nil
            default:
                return record.tile
            }
        }
        if let house = records.first(where: { $0.kind == .house }) {
            tiles.append(contentsOf: FarmExpansion.footprint(kind: .house, anchor: house.tile))
        }
        tiles.append(contentsOf: displayTerrain.keys.filter { clearing.contains($0) })
        tiles.append(contentsOf: levelOneFrameTiles(around: clearing))
        if tiles.isEmpty {
            tiles = FarmExpansion.openingFocusTiles(for: yardPlan)
        }
        return tiles.map { IsoMap.center($0) }
    }

    /// Corners of a radius-12 island around the yard, so the opening view includes the coast.
    private func levelOneFrameTiles(around clearing: Set<FarmTile>) -> [FarmTile] {
        guard !clearing.isEmpty else { return [] }
        let column = clearing.reduce(0) { $0 + $1.column } / clearing.count
        let row = clearing.reduce(0) { $0 + $1.row } / clearing.count
        let radius = Int(Woodland.levelOneFloor.rounded()) + 2
        let diagonal = Int((Double(radius) / 2.squareRoot()).rounded(.down))
        var tiles = [
            FarmTile(column: column + radius, row: row),
            FarmTile(column: column - radius, row: row),
            FarmTile(column: column, row: row + radius),
            FarmTile(column: column, row: row - radius),
            FarmTile(column: column + diagonal, row: row + diagonal),
            FarmTile(column: column - diagonal, row: row + diagonal),
            FarmTile(column: column + diagonal, row: row - diagonal),
            FarmTile(column: column - diagonal, row: row - diagonal)
        ]
        if Woodland.level(tastedCount: tastedCount) <= 1 {
            let columns = chart.ground.map(\.column)
            let rows = chart.ground.map(\.row)
            if let minColumn = columns.min(), let maxColumn = columns.max(), let minRow = rows.min(), let maxRow = rows.max() {
                tiles.append(contentsOf: [
                    FarmTile(column: minColumn, row: minRow),
                    FarmTile(column: maxColumn, row: maxRow),
                    FarmTile(column: minColumn, row: maxRow),
                    FarmTile(column: maxColumn, row: minRow)
                ])
            }
        }
        return tiles
    }

    private func landWorldPoints() -> [CGPoint] {
        let columns = chart.ground.map(\.column)
        let rows = chart.ground.map(\.row)
        if let minColumn = columns.min(), let maxColumn = columns.max(), let minRow = rows.min(), let maxRow = rows.max() {
            return [
                FarmTile(column: minColumn, row: minRow),
                FarmTile(column: maxColumn, row: minRow),
                FarmTile(column: maxColumn, row: maxRow),
                FarmTile(column: minColumn, row: maxRow)
            ].map { IsoMap.center($0) }
        }
        return FarmExpansion.plots(for: yardPlan).flatMap { plot in
            [
                FarmTile(column: plot.columns.lowerBound, row: plot.rows.lowerBound),
                FarmTile(column: plot.columns.upperBound, row: plot.rows.lowerBound),
                FarmTile(column: plot.columns.upperBound, row: plot.rows.upperBound),
                FarmTile(column: plot.columns.lowerBound, row: plot.rows.upperBound)
            ].map { IsoMap.center($0) }
        }
    }

    /// The opening view: farm items, plus about two tiles, across about 90% of the width.
    private func fittedCamera(in viewSize: CGSize) -> FarmCamera {
        cameraFitting(farmWorldPoints(), in: viewSize, margin: 0, fill: 0.90)
    }

    /// Far enough out to see the whole island.
    private func islandCamera(in viewSize: CGSize) -> FarmCamera {
        cameraFitting(focusWorldPoints(), in: viewSize, margin: 0, fill: 0.92)
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

    private func cameraFitting(_ focus: [CGPoint], in viewSize: CGSize, margin: CGFloat, fill: CGFloat = 0.92) -> FarmCamera {
        guard viewSize.width > 1,
              let minX = focus.map(\.x).min(),
              let maxX = focus.map(\.x).max(),
              let minY = focus.map(\.y).min(),
              let maxY = focus.map(\.y).max() else {
            return FarmCamera(scale: 1, center: .zero, pan: .zero)
        }
        let spanX = max(maxX - minX, 1) + margin * 2
        let spanY = max(maxY - minY, 1) + margin
        let height = max(viewSize.height - 120, 1)
        let widthFit = (viewSize.width * fill) / spanX
        let heightFit = (height * fill) / spanY
        let fitted = min(FarmZoom.maximum, min(widthFit, heightFit))
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return FarmCamera(scale: fitted, center: center, pan: .zero)
    }

    private func frameHouse(in viewSize: CGSize) {
        if DebugLaunch.farmZoom != nil {
            applyFarmZoom(in: viewSize)
            return
        }
        guard !framed, viewSize.width > 1, viewSize.height > 1 else { return }
        let fitted = fittedCamera(in: viewSize)
        framed = true
        scale = fitted.scale
        lastScale = fitted.scale
        worldCenter = fitted.center
        offset = .zero
        lastOffset = .zero
        OrchardTiming.log(String(format: "farm scale %.3f tile %.0fpt level %d ground %d", Double(fitted.scale), Double(fitted.scale * IsoMap.tileWidth), islandLevel, chart.ground.count))
    }
}

private struct MapGestureOverlay: UIViewRepresentable {
    var brush: Bool
    var onPinch: (CGFloat, CGPoint, UIGestureRecognizer.State) -> Void
    var onTwoPan: (CGSize, UIGestureRecognizer.State) -> Void
    var onOnePan: (CGPoint, CGPoint, CGSize, UIGestureRecognizer.State) -> Void
    var onLongPress: (CGPoint, UIGestureRecognizer.State) -> Void
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
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.4
        hold.allowableMovement = 18
        hold.delegate = context.coordinator
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
        view.addGestureRecognizer(hold)
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

        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            parent.onLongPress(gesture.location(in: gesture.view), gesture.state)
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
