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
    case bush
    case rock
}

struct FarmRecord: Equatable, Identifiable {
    var id: UUID
    var kind: FarmItemKind
    var varietyID: String?
    var tile: FarmTile
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

/// How the map grows. Edit `plots` to retune unlocks and where things can be planted.
enum FarmExpansion {
    /// Starter yard plus the dashed plots beside it. Spots are listed row by row.
    /// Trees are two steps apart so a one-tile sprite does not overlap its neighbour or the fence.
    static let plots: [FarmPlotSpec] = [
        FarmPlotSpec(
            id: "home",
            unlockAt: 0,
            columns: 0...14,
            rows: 0...13,
            treeSpots: [
                FarmTile(column: 2, row: 2), FarmTile(column: 4, row: 2), FarmTile(column: 6, row: 2),
                FarmTile(column: 2, row: 4), FarmTile(column: 4, row: 4), FarmTile(column: 6, row: 4)
            ],
            bedSpots: [
                FarmTile(column: 2, row: 9), FarmTile(column: 4, row: 9), FarmTile(column: 6, row: 9),
                FarmTile(column: 2, row: 11), FarmTile(column: 4, row: 11), FarmTile(column: 6, row: 11)
            ],
            vineSpots: [
                FarmTile(column: 2, row: 13), FarmTile(column: 4, row: 13), FarmTile(column: 6, row: 13), FarmTile(column: 8, row: 13)
            ]
        ),
        FarmPlotSpec(
            id: "east",
            unlockAt: 4,
            columns: 16...21,
            rows: 0...6,
            treeSpots: [
                FarmTile(column: 17, row: 2), FarmTile(column: 19, row: 2),
                FarmTile(column: 17, row: 4), FarmTile(column: 19, row: 4), FarmTile(column: 21, row: 2)
            ],
            bedSpots: [],
            vineSpots: []
        ),
        FarmPlotSpec(
            id: "south",
            unlockAt: 8,
            columns: 0...8,
            rows: 15...19,
            treeSpots: [],
            bedSpots: [
                FarmTile(column: 2, row: 16), FarmTile(column: 4, row: 16), FarmTile(column: 6, row: 16),
                FarmTile(column: 2, row: 18), FarmTile(column: 4, row: 18)
            ],
            vineSpots: []
        ),
        FarmPlotSpec(
            id: "corner",
            unlockAt: 12,
            columns: 16...21,
            rows: 9...13,
            treeSpots: [],
            bedSpots: [FarmTile(column: 21, row: 11)],
            vineSpots: [
                FarmTile(column: 17, row: 10), FarmTile(column: 19, row: 10),
                FarmTile(column: 17, row: 12), FarmTile(column: 19, row: 12)
            ]
        )
    ]

    static func spotKind(zone: String) -> FarmSpotKind {
        switch zone {
        case "bed": .bed
        case "trellis", "greenhouse": .vine
        default: .tree
        }
    }

    static func unlockedPlots(tastedCount: Int) -> [FarmPlotSpec] {
        let count = max(0, tastedCount)
        return plots.filter { count >= $0.unlockAt }
    }

    static func lockedPlots(tastedCount: Int) -> [FarmPlotSpec] {
        let count = max(0, tastedCount)
        return plots.filter { count < $0.unlockAt }
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

    /// Front tile of the house, in the yard beside the orchard path.
    static let houseAnchor = FarmTile(column: 12, row: 4)
    /// Beside the yard, clear of the house footprint.
    static let tractorTile = FarmTile(column: 14, row: 2)
    /// The scattered layout's house tile. Seeing it means the yard should be rebuilt.
    static let legacyHouseTile = FarmTile(column: 7, row: 2)

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
        let reserved = occupied
        return spots(kind: kind, tastedCount: tastedCount).first { !reserved.contains($0) }
    }

    static func canPlace(
        kind: FarmItemKind,
        spot: FarmSpotKind?,
        on tile: FarmTile,
        tastedCount: Int,
        occupied: Set<FarmTile>,
        reserved: Set<FarmTile> = []
    ) -> Bool {
        if kind == .house {
            let tiles = footprint(kind: .house, anchor: tile)
            return tiles.allSatisfy { candidate in
                !occupied.contains(candidate) && !reserved.contains(candidate) && !isLocked(candidate, tastedCount: tastedCount)
            }
        }
        if occupied.contains(tile) || reserved.contains(tile) || isLocked(tile, tastedCount: tastedCount) {
            return false
        }
        switch kind {
        case .plant:
            guard let spot else { return false }
            return spots(kind: spot, tastedCount: tastedCount).contains(tile)
        case .tractor, .fence, .path, .bush, .rock:
            return true
        case .house:
            return true
        }
    }

    /// Tiles that should fill the opening camera: orchard, beds, vines, yard.
    static func starterFocusTiles() -> [FarmTile] {
        var tiles = footprint(kind: .house, anchor: houseAnchor)
        tiles.append(tractorTile)
        guard let home = plots.first else { return tiles }
        tiles.append(contentsOf: home.treeSpots + home.bedSpots + home.vineSpots)
        for column in 0...8 {
            tiles.append(FarmTile(column: column, row: 0))
            tiles.append(FarmTile(column: column, row: 6))
            tiles.append(FarmTile(column: column, row: 13))
        }
        for row in 0...6 {
            tiles.append(FarmTile(column: 0, row: row))
            tiles.append(FarmTile(column: 8, row: row))
        }
        return tiles
    }

    /// Fenced orchard, bed block, vine row, and the yard. Plants are added when tasted.
    static func starterRecords() -> [FarmRecord] {
        var records: [FarmRecord] = [
            FarmRecord(id: UUID(), kind: .house, varietyID: nil, tile: houseAnchor),
            FarmRecord(id: UUID(), kind: .tractor, varietyID: nil, tile: tractorTile)
        ]
        let gate = FarmTile(column: 4, row: 6)
        for column in 0...8 {
            for row in 0...6 where column == 0 || column == 8 || row == 0 || row == 6 {
                let tile = FarmTile(column: column, row: row)
                if tile == gate { continue }
                records.append(FarmRecord(id: UUID(), kind: .fence, varietyID: nil, tile: tile))
            }
        }
        var paths: [FarmTile] = [gate]
        for column in 2...8 {
            paths.append(FarmTile(column: column, row: 7))
            paths.append(FarmTile(column: column, row: 10))
            paths.append(FarmTile(column: column, row: 12))
        }
        for tile in [FarmTile(column: 9, row: 4), FarmTile(column: 10, row: 4), FarmTile(column: 12, row: 5), FarmTile(column: 12, row: 6), FarmTile(column: 12, row: 7)] {
            paths.append(tile)
        }
        for tile in paths {
            records.append(FarmRecord(id: UUID(), kind: .path, varietyID: nil, tile: tile))
        }
        for tile in [FarmTile(column: 9, row: 1), FarmTile(column: 0, row: 8)] {
            records.append(FarmRecord(id: UUID(), kind: .bush, varietyID: nil, tile: tile))
        }
        records.append(FarmRecord(id: UUID(), kind: .rock, varietyID: nil, tile: FarmTile(column: 14, row: 5)))
        return records
    }

    /// Places tasted varieties on the next free slot of their section, in row order.
    /// An older scattered yard is rebuilt into the fenced sections once.
    static func reconciled(_ records: [FarmRecord], tried: [(id: String, zone: String)], tastedCount: Int) -> [FarmRecord] {
        let triedIDs = Set(tried.map(\.id))
        if records.isEmpty || needsRelayout(records, tried: tried) {
            return placeAll(tried, tastedCount: tastedCount)
        }
        var next = records.filter { record in
            record.kind != .plant || (record.varietyID.map { triedIDs.contains($0) } ?? false)
        }
        var occupied = Set(next.map(\.tile))
        for item in tried where !next.contains(where: { $0.kind == .plant && $0.varietyID == item.id }) {
            let kind = spotKind(zone: item.zone)
            guard let tile = nextFreeSpot(kind: kind, tastedCount: tastedCount, occupied: occupied) else { continue }
            next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
            occupied.insert(tile)
        }
        return next
    }

    private static func needsRelayout(_ records: [FarmRecord], tried: [(id: String, zone: String)]) -> Bool {
        if records.contains(where: { $0.kind == .house && $0.tile == legacyHouseTile }) {
            return true
        }
        let valid = spotSets()
        for record in records where record.kind == .plant {
            guard let id = record.varietyID, let item = tried.first(where: { $0.id == id }) else { continue }
            if !valid[spotKind(zone: item.zone), default: []].contains(record.tile) {
                return true
            }
        }
        return false
    }

    private static func spotSets() -> [FarmSpotKind: Set<FarmTile>] {
        var sets: [FarmSpotKind: Set<FarmTile>] = [:]
        for plot in plots {
            for kind in [FarmSpotKind.tree, .bed, .vine] {
                sets[kind, default: []].formUnion(plot.spots(kind))
            }
        }
        return sets
    }

    private static func placeAll(_ tried: [(id: String, zone: String)], tastedCount: Int) -> [FarmRecord] {
        var next = starterRecords()
        var occupied = Set(next.map(\.tile))
        for item in tried {
            let kind = spotKind(zone: item.zone)
            guard let tile = nextFreeSpot(kind: kind, tastedCount: tastedCount, occupied: occupied) else { continue }
            next.append(FarmRecord(id: UUID(), kind: .plant, varietyID: item.id, tile: tile))
            occupied.insert(tile)
        }
        return next
    }
}
