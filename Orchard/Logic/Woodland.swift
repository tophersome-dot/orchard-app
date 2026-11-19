import CoreGraphics
import Foundation

struct DecorRecord: Equatable, Identifiable, Sendable {
    var id: UUID
    var sprite: String
    var tile: FarmTile
    var scale: Double
    var flipped: Bool
    var rotation: Double
    /// "gen" for seeded scenery, "placed" when Chris adds it from the palette.
    var origin: String
}

struct DecorSprite: Equatable, Identifiable {
    var name: String
    var size: CGSize
    var anchor: CGPoint
    var category: Category

    var id: String { name }
    var isTall: Bool { category == .tall }

    enum Category: String, CaseIterable {
        case tall
        case small
        case rock
        case wood
        case water
    }
}

struct GrassTint: Equatable, Sendable {
    var tile: FarmTile
    var radius: CGFloat
    var light: Bool
}

/// The generated island. Ground is dry land, including the farm clearing.
struct IslandChart: Equatable, Sendable {
    var ground: Set<FarmTile>
    var lakes: Set<FarmTile>
    var creek: Set<FarmTile>
    var groves: Set<FarmTile>
    var glades: Set<FarmTile>
    var dirt: Set<FarmTile>
    var decor: [DecorRecord]
    var tints: [GrassTint]

    var water: Set<FarmTile> { lakes.union(creek) }

    static let empty = IslandChart(
        ground: [],
        lakes: [],
        creek: [],
        groves: [],
        glades: [],
        dirt: [],
        decor: [],
        tints: []
    )

    static var placeholder: IslandChart {
        var chart = IslandChart.empty
        chart.ground = FarmExpansion.clearingTiles(for: FarmExpansion.plan(treeCount: 0, bedCount: 0, vineCount: 0))
        return chart
    }
}

/// One generated island, shared by the map and the save so the expensive build runs once per seed and level.
enum IslandChartCache {
    private static let lock = NSLock()
    private static var storedKey = ""
    private static var storedChart = IslandChart.empty

    static func cacheKey(seed: Int, level: Int, clearing: Set<FarmTile>, blocked: Set<FarmTile>, woods: Bool) -> String {
        let columns = clearing.map(\.column)
        let rows = clearing.map(\.row)
        return "\(seed)|\(level)|\(columns.min() ?? 0)|\(columns.max() ?? 0)|\(rows.min() ?? 0)|\(rows.max() ?? 0)|\(blocked.count)|\(woods)"
    }

    static func chart(key: String, build: @escaping @Sendable () -> IslandChart) async -> IslandChart {
        lock.lock()
        if storedKey == key, !storedChart.ground.isEmpty {
            let hit = storedChart
            lock.unlock()
            return hit
        }
        lock.unlock()
        let started = CFAbsoluteTimeGetCurrent()
        let built = await Task.detached(priority: .userInitiated) { build() }.value
        OrchardTiming.log(String(format: "island generate %.3fs ground %d decor %d key %@", CFAbsoluteTimeGetCurrent() - started, built.ground.count, built.decor.count, key))
        lock.lock()
        storedKey = key
        storedChart = built
        lock.unlock()
        return built
    }
}

enum ShoreStamp {
    /// App-copy art is drawn for a 128pt tile. The farm tile is 84pt.
    static let artTile: CGFloat = 128
    /// Waterline sits 45pt below the island top in the app copies, before tile scaling.
    static let waterline: CGFloat = 45

    static let faceSW = DecorSprite(name: "cliff_face_sw", size: CGSize(width: 64, height: 90), anchor: CGPoint(x: 0, y: 7), category: .rock)
    static let faceSE = DecorSprite(name: "cliff_face_se", size: CGSize(width: 64, height: 90), anchor: CGPoint(x: 0, y: 39), category: .rock)
    static let cornerS = DecorSprite(name: "cliff_corner_s", size: CGSize(width: 32, height: 90), anchor: CGPoint(x: 16, y: 15), category: .rock)
    static let bridgeNE = DecorSprite(name: "wooden_bridge_ne", size: CGSize(width: 108, height: 87), anchor: CGPoint(x: 22, y: 75), category: .wood)
    static let bridgeNW = DecorSprite(name: "wooden_bridge_nw", size: CGSize(width: 108, height: 87), anchor: CGPoint(x: 86, y: 75), category: .wood)

    static func pixelScale(_ camera: CGFloat) -> CGFloat {
        (IsoMap.tileWidth / artTile) * camera
    }

    static func waterDrop(camera: CGFloat) -> CGFloat {
        waterline * pixelScale(camera)
    }
}

enum BridgeSpan: Equatable {
    /// Deck runs from the south edge midpoint to the north edge midpoint.
    case northSouth
    /// Deck runs from the east edge midpoint to the west edge midpoint.
    case eastWest
}

/// Seeded island, woodland, and shore helpers. The same seed and level always rebuild the same coast.
enum Woodland {
    /// Smallest level-1 radius when the clearing itself is tiny.
    static let levelOneFloor: Double = 9
    /// Woods beyond the edge of the clearing at level 1. Short enough that the farm view shows the sea.
    static let levelOneRing: Double = 3
    /// Each collection level adds two tiles of radius, until the island is about 50 tiles across.
    static let radiusGrowth: Double = 2
    static let radiusCap: Double = 50
    /// Bump when grove, water, or patch generation changes so existing saves rebuild.
    static let generatorVersion = 8

    static func level(tastedCount: Int) -> Int {
        LaunchOverrides.shared.resolvedLevel(tastedCount: tastedCount)
    }

    /// Level 1 is the clearing plus about a 4-tile ring of woods, and never under 9.
    /// Each further level adds two tiles.
    static func radius(level: Int, around clearing: Set<FarmTile> = []) -> Double {
        let center = centroid(clearing)
        let half = clearing.map { distance($0, center) }.max() ?? 0
        let base = max(half + levelOneRing, levelOneFloor)
        let steps = Double(max(0, level - 1))
        return min(radiusCap, base + steps * radiusGrowth)
    }

    static func sprite(_ name: String) -> DecorSprite? {
        catalog.first { $0.name == name }
    }

    static func palette(in category: DecorSprite.Category) -> [DecorSprite] {
        let wanted: [String]
        switch category {
        case .tall:
            wanted = ["tree_pine_a", "tree_gum_a", "tree_forest_oak", "tree_autumn"]
        case .small:
            wanted = ["bush_a", "fern", "flowers_a", "mushrooms"]
        case .rock:
            wanted = ["rock_boulder_group", "rock_medium_a", "rock_pebbles"]
        case .wood:
            wanted = ["log_fallen", "stump"]
        case .water:
            wanted = ["lily_pads", "driftwood"]
        }
        return wanted.compactMap { name in catalog.first { $0.name == name } }
    }

    static func blockedTiles(records: [FarmRecord], plan: YardPlan) -> Set<FarmTile> {
        var tiles = Set(plan.treeSpots)
        tiles.formUnion(plan.bedSpots)
        tiles.formUnion(plan.vineSpots)
        tiles.formUnion(plan.paths)
        tiles.formUnion(plan.fences.map(\.tile))
        for record in records where record.kind == .house || record.kind == .tractor {
            tiles.formUnion(FarmExpansion.footprint(kind: record.kind, anchor: record.tile))
        }
        return tiles
    }

    static func make(
        seed: UInt64,
        level: Int,
        clearing: Set<FarmTile>,
        blocked: Set<FarmTile>,
        woods: Bool
    ) -> IslandChart {
        let safeLevel = max(1, level)
        let center = centroid(clearing)
        let protected = protectedLand(around: clearing)
        var ground = rawLand(seed: seed, level: safeLevel, center: center, clearing: clearing, protected: protected)
        ground = smoothed(ground, protected: protected)
        let waters = carveWater(into: ground, seed: seed, level: safeLevel, clearing: clearing, protected: protected, center: center)
        ground.subtract(waters.lakes)
        ground.subtract(waters.creek)
        let cover = woods
            ? coverTiles(ground: ground, clearing: clearing, protected: protected, seed: seed)
            : (groves: Set<FarmTile>(), glades: Set<FarmTile>(), dirt: Set<FarmTile>())
        let decor = woods
            ? scenery(
                ground: ground,
                clearing: clearing,
                protected: protected,
                groves: cover.groves,
                glades: cover.glades,
                lakes: waters.lakes,
                creek: waters.creek,
                seed: seed,
                blocked: blocked
            )
            : []
        return IslandChart(
            ground: ground,
            lakes: waters.lakes,
            creek: waters.creek,
            groves: cover.groves,
            glades: cover.glades,
            dirt: cover.dirt,
            decor: decor,
            tints: grassTints(ground: ground, seed: seed, center: center)
        )
    }

    /// A path crosses this creek cell. The span is the deck direction, perpendicular to the flow.
    static func bridge(at tile: FarmTile, creek: Set<FarmTile>, paths: Set<FarmTile>) -> BridgeSpan? {
        guard creek.contains(tile) else { return nil }
        let north = FarmTile(column: tile.column, row: tile.row - 1)
        let south = FarmTile(column: tile.column, row: tile.row + 1)
        let east = FarmTile(column: tile.column + 1, row: tile.row)
        let west = FarmTile(column: tile.column - 1, row: tile.row)
        let crossesEastWest = paths.contains(tile) && (paths.contains(east) || paths.contains(west))
            || (paths.contains(east) && paths.contains(west))
        let crossesNorthSouth = paths.contains(tile) && (paths.contains(north) || paths.contains(south))
            || (paths.contains(north) && paths.contains(south))
        if crossesEastWest && !crossesNorthSouth { return .eastWest }
        if crossesNorthSouth && !crossesEastWest { return .northSouth }
        guard paths.contains(tile) else { return nil }
        let flowNorthSouth = creek.contains(north) || creek.contains(south)
        let flowEastWest = creek.contains(east) || creek.contains(west)
        if flowNorthSouth && !flowEastWest { return .eastWest }
        if flowEastWest && !flowNorthSouth { return .northSouth }
        return .northSouth
    }

    static func bankIsSand(seed: UInt64, edge: FarmGridEdge) -> Bool {
        let column = Int(edge.anchor.x.rounded())
        let row = Int(edge.anchor.y.rounded())
        return unit(seed, column, row, 21) < 0.28
    }

    static let catalog: [DecorSprite] = [
        DecorSprite(name: "tree_pine_a", size: CGSize(width: 141, height: 251), anchor: CGPoint(x: 70.5, y: 247), category: .tall),
        DecorSprite(name: "tree_pine_b", size: CGSize(width: 121, height: 275), anchor: CGPoint(x: 58.5, y: 271.5), category: .tall),
        DecorSprite(name: "tree_pine_c", size: CGSize(width: 128, height: 219), anchor: CGPoint(x: 63.5, y: 216), category: .tall),
        DecorSprite(name: "tree_gum_a", size: CGSize(width: 166, height: 225), anchor: CGPoint(x: 87, y: 222), category: .tall),
        DecorSprite(name: "tree_gum_b", size: CGSize(width: 205, height: 246), anchor: CGPoint(x: 107, y: 242), category: .tall),
        DecorSprite(name: "tree_forest_oak", size: CGSize(width: 192, height: 232), anchor: CGPoint(x: 96.5, y: 228.5), category: .tall),
        DecorSprite(name: "tree_forest_birch", size: CGSize(width: 166, height: 217), anchor: CGPoint(x: 85, y: 213), category: .tall),
        DecorSprite(name: "tree_autumn", size: CGSize(width: 179, height: 218), anchor: CGPoint(x: 88, y: 214.5), category: .tall),
        DecorSprite(name: "bush_a", size: CGSize(width: 89, height: 79), anchor: CGPoint(x: 44.5, y: 69.5), category: .small),
        DecorSprite(name: "bush_berry", size: CGSize(width: 89, height: 78), anchor: CGPoint(x: 45, y: 69.5), category: .small),
        DecorSprite(name: "fern", size: CGSize(width: 77, height: 63), anchor: CGPoint(x: 38.5, y: 55.5), category: .small),
        DecorSprite(name: "flowers_a", size: CGSize(width: 77, height: 65), anchor: CGPoint(x: 38, y: 57.5), category: .small),
        DecorSprite(name: "flowers_b", size: CGSize(width: 77, height: 66), anchor: CGPoint(x: 38.5, y: 59), category: .small),
        DecorSprite(name: "reeds", size: CGSize(width: 64, height: 59), anchor: CGPoint(x: 31.5, y: 52.5), category: .small),
        DecorSprite(name: "mushrooms", size: CGSize(width: 38, height: 36), anchor: CGPoint(x: 19, y: 32), category: .small),
        DecorSprite(name: "rock_boulder_group", size: CGSize(width: 128, height: 103), anchor: CGPoint(x: 64, y: 91), category: .rock),
        DecorSprite(name: "rock_medium_a", size: CGSize(width: 77, height: 70), anchor: CGPoint(x: 38.5, y: 61.5), category: .rock),
        DecorSprite(name: "rock_medium_b", size: CGSize(width: 70, height: 65), anchor: CGPoint(x: 35, y: 57), category: .rock),
        DecorSprite(name: "rock_pebbles", size: CGSize(width: 45, height: 32), anchor: CGPoint(x: 22, y: 27.5), category: .rock),
        DecorSprite(name: "rock_slab", size: CGSize(width: 77, height: 46), anchor: CGPoint(x: 38.5, y: 40.5), category: .rock),
        DecorSprite(name: "log_fallen", size: CGSize(width: 102, height: 81), anchor: CGPoint(x: 51, y: 60.5), category: .wood),
        DecorSprite(name: "stump", size: CGSize(width: 64, height: 55), anchor: CGPoint(x: 32, y: 52.5), category: .wood),
        DecorSprite(name: "lily_pads", size: CGSize(width: 77, height: 64), anchor: CGPoint(x: 38, y: 51), category: .water),
        DecorSprite(name: "rock_in_water", size: CGSize(width: 70, height: 67), anchor: CGPoint(x: 35, y: 53), category: .water),
        DecorSprite(name: "driftwood", size: CGSize(width: 96, height: 69), anchor: CGPoint(x: 47.5, y: 55), category: .water)
    ]

    static func unit(_ seed: UInt64, _ column: Int, _ row: Int, _ salt: UInt64 = 0) -> Double {
        Double(mix(seed, column, row, salt) >> 11) / Double(1 << 53)
    }

    // MARK: - Land

    private static func centroid(_ tiles: Set<FarmTile>) -> (x: Double, y: Double) {
        guard !tiles.isEmpty else { return (7, 6) }
        let count = Double(tiles.count)
        let x = tiles.reduce(0) { $0 + $1.column } 
        let y = tiles.reduce(0) { $0 + $1.row }
        return (Double(x) / count, Double(y) / count)
    }

    private static func protectedLand(around clearing: Set<FarmTile>) -> Set<FarmTile> {
        var tiles = clearing
        for tile in clearing {
            for neighbor in orthogonal(tile) {
                tiles.insert(neighbor)
            }
        }
        return tiles
    }

    private static func rawLand(
        seed: UInt64,
        level: Int,
        center: (x: Double, y: Double),
        clearing: Set<FarmTile>,
        protected: Set<FarmTile>
    ) -> Set<FarmTile> {
        let reachRadius = radius(level: level, around: clearing)
        let reach = Int(ceil(reachRadius + reachRadius * 0.5)) + 2
        let originColumn = Int(center.x.rounded())
        let originRow = Int(center.y.rounded())
        var land = protected
        for column in (originColumn - reach)...(originColumn + reach) {
            for row in (originRow - reach)...(originRow + reach) {
                let tile = FarmTile(column: column, row: row)
                if land.contains(tile) { continue }
                let dx = Double(column) - center.x
                let dy = Double(row) - center.y
                let distance = (dx * dx + dy * dy).squareRoot()
                let broad = field(column, row, seed: seed, cell: 7, salt: 1)
                let detail = field(column, row, seed: seed, cell: 3, salt: 2)
                let wobble = (broad - 0.5) * 1.0 + (detail - 0.5) * 0.35
                if distance <= reachRadius + wobble {
                    land.insert(tile)
                }
            }
        }
        land.formUnion(clearing)
        return land
    }

    /// Drops one-cell spikes and fills one-cell notches so the coast is a smooth headland, not a stair.
    private static func smoothed(_ land: Set<FarmTile>, protected: Set<FarmTile>) -> Set<FarmTile> {
        var land = land
        for _ in 0..<12 {
            let drops = land.filter { tile in
                !protected.contains(tile) && orthogonal(tile).filter { land.contains($0) }.count < 2
            }
            for tile in drops {
                land.remove(tile)
            }
            var candidates = Set<FarmTile>()
            for tile in land {
                for neighbor in orthogonal(tile) where !land.contains(neighbor) {
                    candidates.insert(neighbor)
                }
            }
            let fills = candidates.filter { orthogonal($0).filter { land.contains($0) }.count >= 3 }
            if drops.isEmpty && fills.isEmpty { break }
            land.formUnion(fills)
        }
        return land
    }

    private static func carveWater(
        into land: Set<FarmTile>,
        seed: UInt64,
        level: Int,
        clearing: Set<FarmTile>,
        protected: Set<FarmTile>,
        center: (x: Double, y: Double)
    ) -> (lakes: Set<FarmTile>, creek: Set<FarmTile>) {
        let coast = coastTiles(in: land)
        let inland = land.subtracting(protected).subtracting(coast)
        let lakeLand = inland.isEmpty ? land.subtracting(protected) : inland
        let reach = radius(level: level, around: clearing)
        var pools: [Set<FarmTile>] = []
        let wanted = unit(seed, 3, 5, 30) < 0.55 ? 2 : 1
        var used = Set<FarmTile>()
        for index in 0..<wanted {
            let band = lakeLand.filter { tile in
                !used.contains(tile) && distance(tile, center) > reach * 0.55 && distance(tile, center) < reach - 1
            }
            let choices = band.isEmpty ? lakeLand.filter { !used.contains($0) } : band
            guard let start = choices.min(by: { mix(seed, $0.column, $0.row, UInt64(40 + index)) < mix(seed, $1.column, $1.row, UInt64(40 + index)) }) else { break }
            let lake = roundedLake(at: start, land: lakeLand, protected: protected, seed: seed, salt: UInt64(40 + index))
            if lake.count >= 6 {
                pools.append(lake)
                used.formUnion(lake)
                for tile in lake {
                    for neighbor in orthogonal(tile) {
                        used.insert(neighbor)
                    }
                }
            }
        }
        let lakes = pools.reduce(into: Set<FarmTile>()) { $0.formUnion($1) }
        let creek = pools.first.map { widenedCreek(from: $0, land: land, avoid: clearing.union(lakes), seed: seed, center: center) } ?? []
        return (lakes, creek)
    }

    /// Grows a 6–15 cell pool, preferring a noisy radius so the shore stays rounded.
    private static func roundedLake(
        at start: FarmTile,
        land: Set<FarmTile>,
        protected: Set<FarmTile>,
        seed: UInt64,
        salt: UInt64
    ) -> Set<FarmTile> {
        let target = 6 + Int(mix(seed, start.column, start.row, salt) % 10)
        let reach = 1.6 + unit(seed, start.column, start.row, salt) * 1.3
        var lake: Set<FarmTile> = [start]
        while lake.count < target {
            let options = lake.flatMap { orthogonal($0) }.filter { land.contains($0) && !protected.contains($0) && !lake.contains($0) }
            guard let next = options.min(by: { lhs, rhs in
                lakeScore(lhs, start: start, reach: reach, seed: seed, salt: salt) < lakeScore(rhs, start: start, reach: reach, seed: seed, salt: salt)
            }) else { break }
            lake.insert(next)
        }
        for _ in 0..<2 {
            let drops = lake.filter { orthogonal($0).filter { lake.contains($0) }.count < 2 }
            lake.subtract(drops)
        }
        while lake.count < 6 {
            let options = lake.flatMap { orthogonal($0) }.filter { land.contains($0) && !protected.contains($0) && !lake.contains($0) }
            guard let next = options.first else { break }
            lake.insert(next)
        }
        return lake
    }

    private static func lakeScore(_ tile: FarmTile, start: FarmTile, reach: Double, seed: UInt64, salt: UInt64) -> Double {
        let dx = Double(tile.column - start.column)
        let dy = Double(tile.row - start.row)
        let noise = field(tile.column, tile.row, seed: seed, cell: 3, salt: salt &+ 2)
        return abs((dx * dx + dy * dy).squareRoot() - reach * (0.85 + 0.3 * noise))
    }

    /// A one-tile channel that wanders, then gains a second tile as it nears the sea.
    private static func widenedCreek(
        from lake: Set<FarmTile>,
        land: Set<FarmTile>,
        avoid: Set<FarmTile>,
        seed: UInt64,
        center: (x: Double, y: Double)
    ) -> Set<FarmTile> {
        let spine = creekLine(from: lake, land: land, avoid: avoid, seed: seed, center: center)
        guard spine.count > 4 else { return spine }
        let ordered = orderedCreek(spine, lake: lake, center: center)
        var creek = spine
        let mouth = max(3, ordered.count / 3)
        for (index, tile) in ordered.enumerated() where index >= ordered.count - mouth {
            let side = orthogonal(tile)
                .filter { land.contains($0) && !avoid.contains($0) && !creek.contains($0) && !lake.contains($0) }
                .max { unit(seed, $0.column, $0.row, 48) < unit(seed, $1.column, $1.row, 48) }
            if let side {
                creek.insert(side)
            }
        }
        return creek
    }

    private static func orderedCreek(_ creek: Set<FarmTile>, lake: Set<FarmTile>, center: (x: Double, y: Double)) -> [FarmTile] {
        guard let start = creek.min(by: { distance($0, center) < distance($1, center) }) else { return [] }
        var ordered = [start]
        var seen: Set<FarmTile> = [start]
        while let last = ordered.last {
            let next = orthogonal(last).filter { creek.contains($0) && !seen.contains($0) }
            guard let step = next.first else { break }
            seen.insert(step)
            ordered.append(step)
        }
        if ordered.count < creek.count, let extra = creek.subtracting(seen).min(by: { distance($0, center) < distance($1, center) }) {
            ordered.append(extra)
        }
        _ = lake
        return ordered
    }

    private static func creekLine(
        from lake: Set<FarmTile>,
        land: Set<FarmTile>,
        avoid: Set<FarmTile>,
        seed: UInt64,
        center: (x: Double, y: Double)
    ) -> Set<FarmTile> {
        guard let start = lake.max(by: { distance($0, center) < distance($1, center) }) else { return [] }
        var current = start
        var walked = Set<FarmTile>()
        var creek = Set<FarmTile>()
        for _ in 0..<90 {
            let options = orthogonal(current).filter { candidate in
                land.contains(candidate) && !avoid.contains(candidate) && !walked.contains(candidate) && !lake.contains(candidate)
            }
            if options.contains(where: { orthogonal($0).contains { !land.contains($0) } }) {
                if let mouth = options.first(where: { orthogonal($0).contains { !land.contains($0) } }) {
                    creek.insert(mouth)
                }
                break
            }
            guard let next = options.max(by: { scoreCreek($0, seed: seed, center: center) < scoreCreek($1, seed: seed, center: center) }) else { break }
            creek.insert(next)
            walked.insert(next)
            current = next
        }
        return creek
    }

    private static func scoreCreek(_ tile: FarmTile, seed: UInt64, center: (x: Double, y: Double)) -> Double {
        distance(tile, center) + (unit(seed, tile.column, tile.row, 44) - 0.5) * 5.5
    }

    private static func coverTiles(
        ground: Set<FarmTile>,
        clearing: Set<FarmTile>,
        protected: Set<FarmTile>,
        seed: UInt64
    ) -> (groves: Set<FarmTile>, glades: Set<FarmTile>, dirt: Set<FarmTile>) {
        let coast = coastTiles(in: ground.union(clearing))
        let open = ground.subtracting(protected).subtracting(coast)
        var groves = Set<FarmTile>()
        var reserved = protected
        let cap = max(8, Int(Double(open.count) * 0.22))
        let seeds = open.sorted { mix(seed, $0.column, $0.row, 4) < mix(seed, $1.column, $1.row, 4) }
        for start in seeds where groves.count < cap {
            if reserved.contains(start) { continue }
            let size = 3 + Int(mix(seed, start.column, start.row, 6) % 10)
            var grove: Set<FarmTile> = [start]
            while grove.count < size {
                let options = grove.flatMap { orthogonal($0) }.filter { open.contains($0) && !grove.contains($0) && !reserved.contains($0) }
                guard let next = options.min(by: { mix(seed, $0.column, $0.row, 7) < mix(seed, $1.column, $1.row, 7) }) else { break }
                grove.insert(next)
            }
            guard grove.count >= 3 else { continue }
            groves.formUnion(grove)
            for tile in grove {
                for column in (tile.column - 2)...(tile.column + 2) {
                    for row in (tile.row - 2)...(tile.row + 2) where max(abs(column - tile.column), abs(row - tile.row)) <= 2 {
                        reserved.insert(FarmTile(column: column, row: row))
                    }
                }
            }
        }
        var glades = Set<FarmTile>()
        var dirt = Set<FarmTile>()
        let meadow = open.subtracting(reserved)
        for tile in meadow {
            let cover = field(tile.column, tile.row, seed: seed, cell: 6, salt: 5)
            if cover < 0.28 {
                glades.insert(tile)
            } else if cover > 0.72 {
                dirt.insert(tile)
            }
        }
        return (
            groves,
            solidPatches(glades, minimum: 4),
            solidPatches(dirt, minimum: 3)
        )
    }

    /// Drops one-cell specks and tiny clumps so a patch has a soft, continuous edge.
    private static func solidPatches(_ tiles: Set<FarmTile>, minimum: Int) -> Set<FarmTile> {
        var tiles = tiles
        for _ in 0..<5 {
            let drops = tiles.filter { orthogonal($0).filter { tiles.contains($0) }.count < 2 }
            if drops.isEmpty { break }
            tiles.subtract(drops)
        }
        var seen = Set<FarmTile>()
        var keep = Set<FarmTile>()
        for start in tiles where !seen.contains(start) {
            var stack = [start]
            var component = Set<FarmTile>()
            while let tile = stack.popLast() {
                guard tiles.contains(tile), seen.insert(tile).inserted else { continue }
                component.insert(tile)
                for neighbor in orthogonal(tile) where tiles.contains(neighbor) {
                    stack.append(neighbor)
                }
            }
            if component.count >= minimum {
                keep.formUnion(component)
            }
        }
        return keep
    }

    private static func scenery(
        ground: Set<FarmTile>,
        clearing: Set<FarmTile>,
        protected: Set<FarmTile>,
        groves: Set<FarmTile>,
        glades: Set<FarmTile>,
        lakes: Set<FarmTile>,
        creek: Set<FarmTile>,
        seed: UInt64,
        blocked: Set<FarmTile>
    ) -> [DecorRecord] {
        var placed = Set<FarmTile>()
        var decor: [DecorRecord] = []
        let front = clearing.map { $0.column + $0.row }.max() ?? 0
        let frontZone = frontBand(clearing: clearing, front: front)
        func add(_ name: String, _ tile: FarmTile, _ salt: UInt64) {
            guard ground.contains(tile) || lakes.contains(tile) || !ground.contains(tile) else { return }
            guard placed.insert(tile).inserted else { return }
            guard let sprite = sprite(name) else { return }
            decor.append(DecorRecord(
                id: stableID(seed: seed, tile: tile, salt: salt),
                sprite: sprite.name,
                tile: tile,
                scale: 0.85 + unit(seed, tile.column, tile.row, salt &+ 3) * 0.30,
                flipped: mix(seed, tile.column, tile.row, salt &+ 4) & 1 == 0,
                rotation: (unit(seed, tile.column, tile.row, salt &+ 5) - 0.5) * 0.35,
                origin: "gen"
            ))
        }
        for tile in groves {
            let roll = unit(seed, tile.column, tile.row, 9)
            if frontZone.contains(tile) || roll >= 0.60 {
                add(understory(seed: seed, tile: tile, salt: 10), tile, 10)
            } else {
                add(tallTree(seed: seed, tile: tile), tile, 9)
            }
        }
        let open = ground.subtracting(protected).subtracting(groves).subtracting(glades)
        for tile in open where unit(seed, tile.column, tile.row, 11) < 0.10 {
            add(understory(seed: seed, tile: tile, salt: 11), tile, 11)
        }
        for tile in glades where unit(seed, tile.column, tile.row, 12) < 0.05 {
            add(understory(seed: seed, tile: tile, salt: 12), tile, 12)
        }
        let free = clearing.filter { tile in
            !blocked.contains(tile) && !placed.contains(tile)
        }
        for tile in free where unit(seed, tile.column, tile.row, 13) < 0.15 {
            add(understory(seed: seed, tile: tile, salt: 13), tile, 13)
        }
        let edge = free.filter { tile in
            orthogonal(tile).contains { !clearing.contains($0) } && !frontZone.contains(tile)
        }
        let tallEdges = edge.sorted { mix(seed, $0.column, $0.row, 14) < mix(seed, $1.column, $1.row, 14) }
        for tile in tallEdges.prefix(3) where !placed.contains(tile) {
            add(tallTree(seed: seed, tile: tile), tile, 14)
        }
        for tile in lakes where unit(seed, tile.column, tile.row, 15) < 0.55 {
            add("lily_pads", tile, 15)
        }
        let banks = ground.filter { tile in
            orthogonal(tile).contains { lakes.contains($0) || creek.contains($0) }
        }
        for tile in banks where unit(seed, tile.column, tile.row, 18) < 0.42 {
            add("reeds", tile, 18)
        }
        for tile in creek where unit(seed, tile.column, tile.row, 19) < 0.28 {
            add("lily_pads", tile, 19)
        }
        let shore = coastTiles(in: ground)
        for tile in shore {
            guard unit(seed, tile.column, tile.row, 16) < 0.09 else { continue }
            guard let water = orthogonal(tile).first(where: { !ground.contains($0) && !lakes.contains($0) }) else { continue }
            let name = unit(seed, tile.column, tile.row, 17) < 0.55 ? "rock_in_water" : "driftwood"
            add(name, water, 16)
        }
        return decor
    }

    private static func grassTints(ground: Set<FarmTile>, seed: UInt64, center: (x: Double, y: Double)) -> [GrassTint] {
        let columns = ground.map(\.column)
        let reach = max(((columns.max() ?? 0) - (columns.min() ?? 0)) / 2, 8)
        let originColumn = Int(center.x.rounded())
        let originRow = Int(center.y.rounded())
        var tints: [GrassTint] = []
        var index = 0
        for column in stride(from: originColumn - reach, through: originColumn + reach, by: 5) {
            for row in stride(from: originRow - reach, through: originRow + reach, by: 5) {
                let tile = FarmTile(column: column, row: row)
                let roll = unit(seed, column, row, 18)
                guard roll > 0.42 else { continue }
                let nudged = FarmTile(
                    column: column + Int(unit(seed, column, row, 19) * 3) - 1,
                    row: row + Int(unit(seed, column, row, 20) * 3) - 1
                )
                guard ground.contains(nudged) || ground.contains(tile) else { continue }
                tints.append(GrassTint(
                    tile: ground.contains(nudged) ? nudged : tile,
                    radius: CGFloat(3.5 + unit(seed, column, row, 22) * 3.5),
                    light: index.isMultiple(of: 2)
                ))
                index += 1
            }
        }
        return tints
    }

    private static func tallTree(seed: UInt64, tile: FarmTile) -> String {
        if unit(seed, tile.column, tile.row, 24) < 0.08 {
            return "tree_autumn"
        }
        let names = ["tree_pine_a", "tree_pine_b", "tree_pine_c", "tree_gum_a", "tree_gum_b", "tree_forest_oak", "tree_forest_birch"]
        let index = Int(mix(seed, tile.column, tile.row, 23) % UInt64(names.count))
        return names[index]
    }

    private static func understory(seed: UInt64, tile: FarmTile, salt: UInt64) -> String {
        let names = ["bush_a", "bush_berry", "fern", "flowers_a", "flowers_b", "reeds", "mushrooms", "rock_medium_a", "rock_medium_b", "rock_pebbles", "rock_slab", "log_fallen", "stump"]
        let index = Int(mix(seed, tile.column, tile.row, salt) % UInt64(names.count))
        return names[index]
    }

    private static func frontBand(clearing: Set<FarmTile>, front: Int) -> Set<FarmTile> {
        var band = Set<FarmTile>()
        for spot in clearing where spot.column + spot.row >= front - 1 {
            for column in (spot.column - 3)...(spot.column + 3) {
                for row in (spot.row - 3)...(spot.row + 3) where max(abs(column - spot.column), abs(row - spot.row)) <= 3 {
                    let tile = FarmTile(column: column, row: row)
                    if tile.column + tile.row > front + 1 {
                        band.insert(tile)
                    }
                }
            }
        }
        return band
    }

    private static func coastTiles(in land: Set<FarmTile>) -> Set<FarmTile> {
        var coast = Set<FarmTile>()
        for tile in land where orthogonal(tile).contains(where: { !land.contains($0) }) {
            coast.insert(tile)
        }
        return coast
    }

    private static func distance(_ tile: FarmTile, _ center: (x: Double, y: Double)) -> Double {
        let dx = Double(tile.column) - center.x
        let dy = Double(tile.row) - center.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func orthogonal(_ tile: FarmTile) -> [FarmTile] {
        [
            FarmTile(column: tile.column + 1, row: tile.row),
            FarmTile(column: tile.column - 1, row: tile.row),
            FarmTile(column: tile.column, row: tile.row + 1),
            FarmTile(column: tile.column, row: tile.row - 1)
        ]
    }

    private static func stableID(seed: UInt64, tile: FarmTile, salt: UInt64) -> UUID {
        let mixed = mix(seed, tile.column, tile.row, salt)
        let high = mix(mixed, tile.row, tile.column, salt &+ 7)
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((mixed >> (index * 8)) & 0xff)
            bytes[index + 8] = UInt8((high >> (index * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func field(_ column: Int, _ row: Int, seed: UInt64, cell: Int, salt: UInt64) -> Double {
        let x0 = floorDivide(column, cell)
        let y0 = floorDivide(row, cell)
        let fx = Double(column - x0 * cell) / Double(cell)
        let fy = Double(row - y0 * cell) / Double(cell)
        let sx = fx * fx * (3 - 2 * fx)
        let sy = fy * fy * (3 - 2 * fy)
        let v00 = unit(seed, x0, y0, salt)
        let v10 = unit(seed, x0 + 1, y0, salt)
        let v01 = unit(seed, x0, y0 + 1, salt)
        let v11 = unit(seed, x0 + 1, y0 + 1, salt)
        let a = v00 + (v10 - v00) * sx
        let b = v01 + (v11 - v01) * sx
        return a + (b - a) * sy
    }

    private static func floorDivide(_ value: Int, _ cell: Int) -> Int {
        let quotient = value / cell
        let remainder = value % cell
        if remainder != 0 && value < 0 {
            return quotient - 1
        }
        return quotient
    }

    static func mix(_ seed: UInt64, _ column: Int, _ row: Int, _ salt: UInt64 = 0) -> UInt64 {
        var mixed = seed
        mixed &+= UInt64(bitPattern: Int64(column)) &* 0x9E3779B185EBCA87
        mixed ^= UInt64(bitPattern: Int64(row)) &* 0xC2B2AE3D27D4EB4F
        mixed ^= salt &* 0x165667B19E3779F9
        mixed ^= mixed >> 30
        mixed &*= 0xBF58476D1CE4E5B9
        mixed ^= mixed >> 27
        mixed &*= 0x94D049BB133111EB
        mixed ^= mixed >> 31
        return mixed
    }
}
