import Foundation

enum FarmSpotKind: String, Equatable {
    case tree
    case bed
    case vine
}

enum FarmItemKind: String, Equatable, CaseIterable {
    case house
    case tractor
    case plant
    case fence
    case path
    case dirt
    case sand
    case longgrass
    case tilled
    case bush
    case rock
    case forest
    case lake
    case creek
    /// Remembers that Chris cleared this cell, so the woods do not grow back.
    case cleared

    var isTerrain: Bool {
        switch self {
        case .path, .dirt, .sand, .longgrass, .tilled, .forest, .lake, .creek: true
        case .house, .tractor, .plant, .fence, .bush, .rock, .cleared: false
        }
    }

    var isWater: Bool {
        self == .lake || self == .creek
    }
}

struct FarmRecord: Equatable, Identifiable {
    var id: UUID
    var kind: FarmItemKind
    var varietyID: String?
    var tile: FarmTile
}

struct FarmFenceSegment: Equatable {
    var tile: FarmTile
    /// True when the pickets follow a constant column (the left and right sides).
    var alongColumn: Bool
}

struct FarmPlotSpec: Equatable, Identifiable {
    var id: String
    /// Distinct tasted varieties required before this plot opens. The starter plot is 0.
    var unlockAt: Int
    var columns: ClosedRange<Int>
    var rows: ClosedRange<Int>
    var treeSpots: [FarmTile]
    var bedSpots: [FarmTile]
    var vineSpots: [FarmTile]

    func contains(_ tile: FarmTile) -> Bool {
        columns.contains(tile.column) && rows.contains(tile.row)
    }

    func spots(_ kind: FarmSpotKind) -> [FarmTile] {
        switch kind {
        case .tree: treeSpots
        case .bed: bedSpots
        case .vine: vineSpots
        }
    }
}

/// The generated yard: a fenced orchard, a bed block, a vine row, and the paths between them.
struct YardPlan: Equatable {
    var treeSpots: [FarmTile]
    var bedSpots: [FarmTile]
    var vineSpots: [FarmTile]
    var fences: [FarmFenceSegment]
    var paths: [FarmTile]
    var fenceBottom: Int

    func spots(_ kind: FarmSpotKind) -> [FarmTile] {
        switch kind {
        case .tree: treeSpots
        case .bed: bedSpots
        case .vine: vineSpots
        }
    }
}

/// How the map grows. The orchard and the beds add rows as more of that kind are tasted.
enum FarmExpansion {
    static let treeColumns = [2, 4, 6]
    static let bedColumns = [2, 3, 4, 5]
    static let vineColumns = [2, 4, 6, 8]
    /// Front tile of the house, in the yard beside the orchard.
    static let houseAnchor = FarmTile(column: 12, row: 4)
    /// In front of the house, on the yard side of the path.
    static let tractorTile = FarmTile(column: 14, row: 6)
    /// The scattered layout's house tile. Seeing it means the yard should be rebuilt.
    static let legacyHouseTile = FarmTile(column: 7, row: 2)
    /// Tractor tiles from earlier yards. A tractor the player has moved somewhere else is left alone.
    static let retiredTractorTiles: Set<FarmTile> = [
        FarmTile(column: 8, row: 3),
        FarmTile(column: 9, row: 0),
        FarmTile(column: 14, row: 2)
    ]

    /// Starter yard, used by tests and by anything that does not yet know how many plants exist.
    static var plots: [FarmPlotSpec] {
        plots(for: plan(treeCount: 0, bedCount: 0, vineCount: 0))
    }

    static func spotKind(zone: String) -> FarmSpotKind {
        switch zone {
        case "bed": .bed
        case "trellis", "greenhouse": .vine
        default: .tree
        }
    }

    static func plan(treeCount: Int, bedCount: Int, vineCount: Int) -> YardPlan {
        let treeRows = max(2, rowsNeeded(treeCount, perRow: treeColumns.count))
        let fenceBottom = treeRows * 2 + 2
        var trees: [FarmTile] = []
        for index in 0..<treeRows {
            let row = 2 + index * 2
            for column in treeColumns {
                trees.append(FarmTile(column: column, row: row))
            }
        }

        let bedRows = max(2, rowsNeeded(bedCount, perRow: bedColumns.count))
        let bedTop = fenceBottom + 2
        var beds: [FarmTile] = []
        for index in 0..<bedRows {
            let row = bedTop + index
            for column in bedColumns {
                beds.append(FarmTile(column: column, row: row))
            }
        }

        let vineRows = max(1, rowsNeeded(vineCount, perRow: vineColumns.count))
        let vineTop = bedTop + bedRows + 1
        var vines: [FarmTile] = []
        for index in 0..<vineRows {
            let row = vineTop + index * 2
            for column in vineColumns {
                vines.append(FarmTile(column: column, row: row))
            }
        }

        var fences: [FarmFenceSegment] = []
        let gate: Set<Int> = [4]
        for column in 0...8 {
            fences.append(FarmFenceSegment(tile: FarmTile(column: column, row: 0), alongColumn: false))
            if !gate.contains(column) {
                fences.append(FarmFenceSegment(tile: FarmTile(column: column, row: fenceBottom), alongColumn: false))
            }
        }
        for row in 0...fenceBottom {
            fences.append(FarmFenceSegment(tile: FarmTile(column: 0, row: row), alongColumn: true))
            fences.append(FarmFenceSegment(tile: FarmTile(column: 8, row: row), alongColumn: true))
        }

        var paths: [FarmTile] = []
        for column in gate {
            paths.append(FarmTile(column: column, row: fenceBottom))
        }
        for column in 1...10 {
            paths.append(FarmTile(column: column, row: fenceBottom + 1))
            paths.append(FarmTile(column: column, row: bedTop + bedRows))
        }
        for tile in [
            FarmTile(column: 10, row: 5), FarmTile(column: 11, row: 5),
            FarmTile(column: 12, row: 5), FarmTile(column: 13, row: 5),
            FarmTile(column: 13, row: 6), FarmTile(column: 14, row: 7)
        ] {
            paths.append(tile)
        }
        let blocked = Set(footprint(kind: .house, anchor: houseAnchor)).union([tractorTile])
        paths.removeAll { blocked.contains($0) }

        return YardPlan(
            treeSpots: trees,
            bedSpots: beds,
            vineSpots: vines,
            fences: fences,
            paths: paths,
            fenceBottom: fenceBottom
        )
    }

    static func plan(records: [FarmRecord], zones: [String: String], openTiles: Set<FarmTile> = []) -> YardPlan {
        var trees = 0
        var beds = 0
        var vines = 0
        for record in records where record.kind == .plant {
            if openTiles.contains(record.tile) { continue }
            guard let id = record.varietyID, let zone = zones[id] else { continue }
            switch spotKind(zone: zone) {
            case .tree: trees += 1
            case .bed: beds += 1
            case .vine: vines += 1
            }
        }
        return plan(treeCount: trees, bedCount: beds, vineCount: vines)
    }

    /// The farm yard that stays grass. Woods generate around it.
    static func clearingTiles(for plan: YardPlan) -> Set<FarmTile> {
        guard let home = plots(for: plan).first(where: { $0.id == "home" }) else { return [] }
        var tiles = Set<FarmTile>()
        for column in home.columns {
            for row in home.rows {
                tiles.insert(FarmTile(column: column, row: row))
            }
        }
        return tiles
    }

    static func plots(for plan: YardPlan) -> [FarmPlotSpec] {
        let vineRow = plan.vineSpots.map(\.row).max() ?? plan.fenceBottom + 5
        return [
            FarmPlotSpec(
                id: "home",
                unlockAt: 0,
                columns: 0...14,
                rows: 0...(vineRow + 1),
                treeSpots: plan.treeSpots,
                bedSpots: plan.bedSpots,
                vineSpots: plan.vineSpots
            ),
            FarmPlotSpec(
                id: "east",
                unlockAt: 4,
                columns: 16...21,
                rows: 0...max(6, plan.fenceBottom),
                treeSpots: [],
                bedSpots: [],
                vineSpots: []
            ),
            FarmPlotSpec(
                id: "south",
                unlockAt: 8,
                columns: 0...8,
                rows: (vineRow + 3)...(vineRow + 7),
                treeSpots: [],
                bedSpots: [],
                vineSpots: []
            ),
            FarmPlotSpec(
                id: "corner",
                unlockAt: 12,
                columns: 16...21,
                rows: (plan.bedSpots.first?.row ?? 8)...vineRow,
                treeSpots: [],
                bedSpots: [],
                vineSpots: []
            )
        ]
    }

    static func unlockedPlots(tastedCount: Int) -> [FarmPlotSpec] {
        let count = max(0, tastedCount)
        return plots.filter { count >= $0.unlockAt }
    }

    static func lockedPlots(tastedCount: Int) -> [FarmPlotSpec] {
        let count = max(0, tastedCount)
        return plots.filter { count < $0.unlockAt }
    }

    static func lockedPlots(tastedCount: Int, plan: YardPlan) -> [FarmPlotSpec] {
        let count = max(0, tastedCount)
        return plots(for: plan).filter { count < $0.unlockAt }
    }

    static func isLocked(_ tile: FarmTile, tastedCount: Int) -> Bool {
        plots.contains { $0.contains(tile) && tastedCount < $0.unlockAt }
    }

    static func spots(kind: FarmSpotKind, tastedCount: Int) -> [FarmTile] {
        unlockedPlots(tastedCount: tastedCount).flatMap { plot in
            plot.spots(kind).sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.column < rhs.column
            }
        }
    }

    static func spots(kind: FarmSpotKind, plan: YardPlan) -> [FarmTile] {
        plan.spots(kind)
    }

    static func footprint(kind: FarmItemKind, anchor: FarmTile) -> [FarmTile] {
        guard kind == .house else { return [anchor] }
        return [
            anchor,
            FarmTile(column: anchor.column - 1, row: anchor.row),
            FarmTile(column: anchor.column, row: anchor.row - 1),
            FarmTile(column: anchor.column - 1, row: anchor.row - 1)
        ]
    }

    static func reservedTiles(in records: [FarmRecord], ignoring: UUID? = nil) -> Set<FarmTile> {
        var tiles = Set<FarmTile>()
        for record in records where record.id != ignoring && (record.kind == .house || record.kind == .tractor) {
            tiles.formUnion(footprint(kind: record.kind, anchor: record.tile))
        }
        return tiles
    }

    static func nextFreeSpot(kind: FarmSpotKind, tastedCount: Int, occupied: Set<FarmTile>) -> FarmTile? {
        spots(kind: kind, tastedCount: tastedCount).first { !occupied.contains($0) }
    }

    static func nextFreeSpot(kind: FarmSpotKind, plan: YardPlan, occupied: Set<FarmTile>) -> FarmTile? {
        plan.spots(kind).first { !occupied.contains($0) }
    }

    static func canPlace(
        kind: FarmItemKind,
        spot: FarmSpotKind?,
        on tile: FarmTile,
        tastedCount: Int,
        occupied: Set<FarmTile>,
        reserved: Set<FarmTile> = [],
        plan: YardPlan? = nil,
        water: Set<FarmTile> = [],
        creek: Set<FarmTile> = [],
        openTiles: Set<FarmTile> = []
    ) -> Bool {
        if kind == .house {
            let tiles = footprint(kind: .house, anchor: tile)
            return tiles.allSatisfy { candidate in
                !occupied.contains(candidate) && !reserved.contains(candidate) && !water.contains(candidate)
            }
        }
        if water.contains(tile) {
            return kind == .path && creek.contains(tile)
        }
        if occupied.contains(tile) || reserved.contains(tile) {
            return false
        }
        switch kind {
        case .plant:
            guard let spot else { return false }
            if openTiles.contains(tile) { return true }
            let tiles = plan.map { spots(kind: spot, plan: $0) } ?? spots(kind: spot, tastedCount: tastedCount)
            return tiles.contains(tile)
        case .tractor, .fence, .path, .dirt, .sand, .longgrass, .tilled, .bush, .rock:
            return true
        case .house, .forest, .lake, .creek, .cleared:
            return false
        }
    }

    /// Orchard corners, beds, vines, house, and tractor. The opening zoom fits this span.
    static func openingFocusTiles(for plan: YardPlan) -> [FarmTile] {
        var tiles = [
            FarmTile(column: 0, row: 0),
            FarmTile(column: 8, row: 0),
            FarmTile(column: 0, row: plan.fenceBottom),
            FarmTile(column: 8, row: plan.fenceBottom)
        ]
        tiles.append(contentsOf: plan.bedSpots)
        tiles.append(contentsOf: plan.vineSpots)
        tiles.append(contentsOf: footprint(kind: .house, anchor: houseAnchor))
        tiles.append(tractorTile)
        return tiles
    }

    /// Tiles that should fill the opening camera.
    static func starterFocusTiles() -> [FarmTile] {
        openingFocusTiles(for: plan(treeCount: 0, bedCount: 0, vineCount: 0))
    }

    static func focusTiles(for plan: YardPlan) -> [FarmTile] {
        var tiles = footprint(kind: .house, anchor: houseAnchor)
        tiles.append(tractorTile)
        tiles.append(contentsOf: plan.treeSpots + plan.bedSpots + plan.vineSpots)
        tiles.append(contentsOf: plan.fences.map(\.tile))
        tiles.append(contentsOf: plan.paths)
        return tiles
    }

    /// Fenced orchard, bed block, vine row, and the yard. Plants are added when tasted.
    static func starterRecords() -> [FarmRecord] {
        records(for: plan(treeCount: 0, bedCount: 0, vineCount: 0))
    }

    /// Places tasted varieties on the next free slot of their section, in row order.
    /// A yard that is still scattered, or too small for the plants, is rebuilt.
    /// Cleared cells are filled before the yard grows. `openTiles` empty keeps the original grid.
    static func reconciled(
        _ records: [FarmRecord],
        tried: [(id: String, zone: String)],
        tastedCount: Int,
        openTiles: [FarmTile] = []
    ) -> [FarmRecord] {
        let openSet = Set(openTiles)
        let zones = Dictionary(uniqueKeysWithValues: tried.map { ($0.id, $0.zone) })
        let seated = Set(records.compactMap { record -> String? in
            guard record.kind == .plant, let id = record.varietyID, openSet.contains(record.tile) else { return nil }
            return id
        })
        var freeSeats = openTiles.filter { tile in
            !records.contains { $0.kind == .plant && $0.tile == tile }
        }
        var gridTried: [(id: String, zone: String)] = []
        for item in tried {
            if seated.contains(item.id) { continue }
            if !freeSeats.isEmpty && !records.contains(where: { $0.kind == .plant && $0.varietyID == item.id }) {
                freeSeats.removeFirst()
                continue
            }
            gridTried.append(item)
        }
        let layout = plan(
            treeCount: gridTried.filter { spotKind(zone: $0.zone) == .tree }.count,
            bedCount: gridTried.filter { spotKind(zone: $0.zone) == .bed }.count,
            vineCount: gridTried.filter { spotKind(zone: $0.zone) == .vine }.count
        )
        let keptGround = records.filter { record in
            switch record.kind {
            case .forest, .lake, .creek, .cleared, .dirt, .sand, .longgrass, .tilled: true
            default: false
            }
        }
        if records.isEmpty || needsRelayout(records, tried: tried, plan: layout, openTiles: openSet) {
            return placeAll(tried, plan: layout, openTiles: openTiles, zones: zones) + keptGround
        }
        let triedIDs = Set(tried.map(\.id))
        var next = records.filter { record in
            record.kind != .plant || (record.varietyID.map { triedIDs.contains($0) } ?? false)
        }
        var occupied = Set(next.map(\.tile))
        var seats = openTiles
        for item in tried where !next.contains(where: { $0.kind == .plant && $0.varietyID == item.id }) {
            if let index = seats.firstIndex(where: { seat in
                !next.contains { record in
                    record.tile == seat && record.kind != .cleared && record.kind != .forest && !record.kind.isWater
                }
            }) {
                let tile = seats.remove(at: index)
                next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
                occupied.insert(tile)
                continue
            }
            let kind = spotKind(zone: item.zone)
            guard let tile = nextFreeSpot(kind: kind, plan: layout, occupied: occupied) else { continue }
            next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
            occupied.insert(tile)
        }
        return next
    }

    private static func rowsNeeded(_ count: Int, perRow: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + perRow - 1) / perRow
    }

    private static func needsRelayout(
        _ records: [FarmRecord],
        tried: [(id: String, zone: String)],
        plan: YardPlan,
        openTiles: Set<FarmTile> = []
    ) -> Bool {
        if let house = records.first(where: { $0.kind == .house }) {
            if house.tile == legacyHouseTile { return true }
        } else {
            return true
        }
        if let tractor = records.first(where: { $0.kind == .tractor }) {
            if retiredTractorTiles.contains(tractor.tile) { return true }
        } else {
            return true
        }
        if !records.contains(where: { $0.kind == .fence && $0.varietyID == FarmSprite.fenceSide }) {
            return true
        }
        let fenceTiles = Set(records.filter { $0.kind == .fence }.map(\.tile))
        if !plan.fences.allSatisfy({ fenceTiles.contains($0.tile) }) {
            return true
        }
        for record in records where record.kind == .plant {
            guard let id = record.varietyID, let item = tried.first(where: { $0.id == id }) else { continue }
            if openTiles.contains(record.tile) { continue }
            if !Set(plan.spots(spotKind(zone: item.zone))).contains(record.tile) {
                return true
            }
        }
        return false
    }

    private static func placeAll(
        _ tried: [(id: String, zone: String)],
        plan: YardPlan,
        openTiles: [FarmTile] = [],
        zones: [String: String] = [:]
    ) -> [FarmRecord] {
        var next = records(for: plan)
        var occupied = Set(next.map(\.tile))
        var seats = openTiles
        for item in tried {
            if let index = seats.firstIndex(where: { !occupied.contains($0) }) {
                let tile = seats.remove(at: index)
                next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
                occupied.insert(tile)
                continue
            }
            let kind = zones[item.id].map { spotKind(zone: $0) } ?? spotKind(zone: item.zone)
            guard let tile = nextFreeSpot(kind: kind, plan: plan, occupied: occupied) else { continue }
            next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
            occupied.insert(tile)
        }
        return next
    }

    private static func records(for plan: YardPlan) -> [FarmRecord] {
        var records: [FarmRecord] = [
            FarmRecord(id: UUID(), kind: .house, varietyID: nil, tile: houseAnchor),
            FarmRecord(id: UUID(), kind: .tractor, varietyID: nil, tile: tractorTile)
        ]
        for fence in plan.fences {
            records.append(FarmRecord(
                id: UUID(),
                kind: .fence,
                varietyID: fence.alongColumn ? FarmSprite.fenceSide : nil,
                tile: fence.tile
            ))
        }
        for tile in plan.paths {
            records.append(FarmRecord(id: UUID(), kind: .path, varietyID: nil, tile: tile))
        }
        for tile in [FarmTile(column: 9, row: 2), FarmTile(column: 0, row: plan.fenceBottom + 2)] {
            records.append(FarmRecord(id: UUID(), kind: .bush, varietyID: nil, tile: tile))
        }
        records.append(FarmRecord(id: UUID(), kind: .rock, varietyID: nil, tile: FarmTile(column: 15, row: 5)))
        return records
    }
}
