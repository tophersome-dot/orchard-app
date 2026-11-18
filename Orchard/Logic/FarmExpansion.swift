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
    static let plots: [FarmPlotSpec] = [
        FarmPlotSpec(
            id: "home",
            unlockAt: 0,
            columns: 1...8,
            rows: 1...8,
            treeSpots: [FarmTile(column: 2, row: 2), FarmTile(column: 4, row: 2), FarmTile(column: 3, row: 3), FarmTile(column: 2, row: 4), FarmTile(column: 4, row: 4), FarmTile(column: 3, row: 4)],
            bedSpots: [FarmTile(column: 6, row: 5), FarmTile(column: 8, row: 5), FarmTile(column: 6, row: 6), FarmTile(column: 8, row: 6), FarmTile(column: 7, row: 7), FarmTile(column: 6, row: 8)],
            vineSpots: [FarmTile(column: 2, row: 6), FarmTile(column: 3, row: 6), FarmTile(column: 4, row: 6), FarmTile(column: 3, row: 7)]
        ),
        FarmPlotSpec(
            id: "east",
            unlockAt: 4,
            columns: 10...15,
            rows: 1...7,
            treeSpots: [FarmTile(column: 11, row: 2), FarmTile(column: 13, row: 2), FarmTile(column: 12, row: 3), FarmTile(column: 11, row: 4)],
            bedSpots: [FarmTile(column: 14, row: 3), FarmTile(column: 14, row: 5), FarmTile(column: 12, row: 5), FarmTile(column: 13, row: 6)],
            vineSpots: []
        ),
        FarmPlotSpec(
            id: "south",
            unlockAt: 8,
            columns: 1...8,
            rows: 10...15,
            treeSpots: [FarmTile(column: 2, row: 11), FarmTile(column: 4, row: 11), FarmTile(column: 3, row: 12), FarmTile(column: 2, row: 13), FarmTile(column: 4, row: 13)],
            bedSpots: [],
            vineSpots: [FarmTile(column: 6, row: 12), FarmTile(column: 7, row: 12), FarmTile(column: 6, row: 14), FarmTile(column: 7, row: 14)]
        ),
        FarmPlotSpec(
            id: "corner",
            unlockAt: 12,
            columns: 10...15,
            rows: 10...15,
            treeSpots: [],
            bedSpots: [FarmTile(column: 11, row: 11), FarmTile(column: 13, row: 11), FarmTile(column: 12, row: 13)],
            vineSpots: [FarmTile(column: 14, row: 12), FarmTile(column: 15, row: 13), FarmTile(column: 11, row: 14), FarmTile(column: 13, row: 14)]
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
        unlockedPlots(tastedCount: tastedCount).flatMap { $0.spots(kind) }
    }

    /// Front tile of the house. The other three tiles of its 2×2 footprint sit behind it.
    static let houseAnchor = FarmTile(column: 7, row: 2)
    /// Kept clear of the house so the tractor is not drawn on top of it.
    static let tractorTile = FarmTile(column: 9, row: 0)
    /// Positions written by the first starter layout, before the tractor had its own tile.
    static let legacyTractorTile = FarmTile(column: 8, row: 3)

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

    /// Tiles that should fill the opening camera: the fenced orchard, beds, house, and tractor.
    static func starterFocusTiles() -> [FarmTile] {
        var tiles = footprint(kind: .house, anchor: houseAnchor)
        tiles.append(tractorTile)
        guard let home = plots.first else { return tiles }
        tiles.append(contentsOf: home.treeSpots + home.bedSpots + home.vineSpots)
        for column in 1...5 {
            tiles.append(FarmTile(column: column, row: 1))
            tiles.append(FarmTile(column: column, row: 5))
        }
        for row in 2...4 {
            tiles.append(FarmTile(column: 1, row: row))
            tiles.append(FarmTile(column: 5, row: row))
        }
        return tiles
    }

    /// House, tractor, the home-paddock fence, a short path, and a little scrub.
    /// Plants are added later, when a variety is tasted.
    static func starterRecords() -> [FarmRecord] {
        var records: [FarmRecord] = [
            FarmRecord(id: UUID(), kind: .house, varietyID: nil, tile: houseAnchor),
            FarmRecord(id: UUID(), kind: .tractor, varietyID: nil, tile: tractorTile)
        ]
        for column in 1...5 {
            for row in 1...5 where column == 1 || column == 5 || row == 1 || row == 5 {
                records.append(FarmRecord(id: UUID(), kind: .fence, varietyID: nil, tile: FarmTile(column: column, row: row)))
            }
        }
        for tile in [FarmTile(column: 6, row: 3), FarmTile(column: 6, row: 4), FarmTile(column: 5, row: 5)] {
            records.append(FarmRecord(id: UUID(), kind: .path, varietyID: nil, tile: tile))
        }
        for tile in [FarmTile(column: 0, row: 3), FarmTile(column: 9, row: 1), FarmTile(column: 0, row: 7)] {
            records.append(FarmRecord(id: UUID(), kind: .bush, varietyID: nil, tile: tile))
        }
        for tile in [FarmTile(column: 9, row: 6), FarmTile(column: 1, row: 0)] {
            records.append(FarmRecord(id: UUID(), kind: .rock, varietyID: nil, tile: tile))
        }
        return records
    }

    /// Places any tasted variety that does not yet have a spot, and drops plants that were untasted.
    static func reconciled(_ records: [FarmRecord], tried: [(id: String, zone: String)], tastedCount: Int) -> [FarmRecord] {
        let triedIDs = Set(tried.map(\.id))
        var next = records.filter { record in
            record.kind != .plant || (record.varietyID.map { triedIDs.contains($0) } ?? false)
        }
        if next.isEmpty {
            next = starterRecords()
        }
        if let tractorIndex = next.firstIndex(where: { $0.kind == .tractor && $0.tile == legacyTractorTile }),
           next.contains(where: { $0.kind == .house && $0.tile == houseAnchor }) {
            next[tractorIndex].tile = tractorTile
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
}
