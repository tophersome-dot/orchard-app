import Foundation
import SwiftData

enum FarmLayout {
    /// Makes sure the starter yard exists and every tasted variety has a spot.
    /// Safe to call more than once. Does not move anything the player already placed.
    @MainActor
    static func sync(context: ModelContext, tried: [(id: String, zone: String)]) async throws {
        let existing = try context.fetch(FetchDescriptor<FarmPlacement>())
        let records = existing.map(\.record)
        let tastedCount = Set(tried.map(\.id)).count
        let open = records.filter { $0.kind == .cleared }.map(\.tile)
        let next = FarmExpansion.reconciled(records, tried: tried, tastedCount: tastedCount, openTiles: open)
        if next != records {
            try write(next, replacing: existing, in: context)
        }
        if DebugLaunch.demoTerrain {
            try ensureDemoTerrain(in: context)
        }
        let zones = Dictionary(uniqueKeysWithValues: tried.map { ($0.id, $0.zone) })
        try ensureTilledBeds(in: context, zones: zones)
        try await ensureWoodland(in: context, zones: zones, tastedCount: Set(tried.map(\.id)).count)
    }

    /// Grows the island and fills new land. Existing clears, paints, and moved decor stay put.
    @MainActor
    private static func ensureWoodland(in context: ModelContext, zones: [String: String], tastedCount: Int) async throws {
        let worlds = try context.fetch(FetchDescriptor<FarmWorld>())
        let world: FarmWorld
        if let existing = worlds.first {
            world = existing
        } else {
            let created = FarmWorld(seed: Int.random(in: 1...999_999_937))
            context.insert(created)
            world = created
        }
        if world.generatorVersion != Woodland.generatorVersion {
            try resetGeneratedWoods(in: context, world: world)
            world.generatorVersion = Woodland.generatorVersion
            world.builtLevel = 0
        }
        let level = Woodland.level(tastedCount: tastedCount)
        let placements = try context.fetch(FetchDescriptor<FarmPlacement>())
        let records = placements.map(\.record)
        let plan = FarmExpansion.plan(records: records, zones: zones, openTiles: Set(records.filter { $0.kind == .cleared }.map(\.tile)))
        let clearing = FarmExpansion.clearingTiles(for: plan)
        let blocked = Woodland.blockedTiles(records: records, plan: plan)
        let woodsOn = !DebugLaunch.noWoods
        let seedValue = world.seed
        let key = IslandChartCache.cacheKey(seed: seedValue, level: level, clearing: clearing, blocked: blocked, woods: woodsOn)
        let chart = await IslandChartCache.chart(key: key) {
            Woodland.make(
                seed: UInt64(bitPattern: Int64(seedValue)),
                level: level,
                clearing: clearing,
                blocked: blocked,
                woods: woodsOn
            )
        }
        let rebuild = world.builtLevel < 1 || world.builtLevel != level
        let cleared = Set(records.filter { $0.kind == .cleared }.map(\.tile))
        var changed = false
        var byTile: [FarmTile: [FarmPlacement]] = [:]
        for item in placements where item.record.kind.isTerrain {
            let tile = FarmTile(column: item.column, row: item.row)
            byTile[tile, default: []].append(item)
        }
        func ensureWater(_ tiles: Set<FarmTile>, _ kind: FarmItemKind) {
            for tile in tiles {
                let existing = byTile[tile] ?? []
                if existing.contains(where: { $0.record.kind == kind }) { continue }
                for item in existing where item.record.kind != .path {
                    context.delete(item)
                }
                let placed = FarmPlacement(id: UUID(), kindRaw: kind.rawValue, varietySlug: nil, column: tile.column, row: tile.row)
                context.insert(placed)
                byTile[tile] = [placed]
                changed = true
            }
        }
        ensureWater(chart.lakes, .lake)
        ensureWater(chart.creek, .creek)

        var claimed = Set<FarmTile>()
        var forestTiles = Set<FarmTile>()
        var longgrassTiles = Set<FarmTile>()
        var dirtTiles = Set<FarmTile>()
        for record in records {
            switch record.kind {
            case .path, .sand, .tilled, .cleared:
                claimed.insert(record.tile)
            case .longgrass:
                longgrassTiles.insert(record.tile)
                claimed.insert(record.tile)
            case .dirt:
                dirtTiles.insert(record.tile)
                claimed.insert(record.tile)
            case .forest:
                forestTiles.insert(record.tile)
            default:
                break
            }
        }

        if woodsOn && rebuild {
            changed = insertTerrain(chart.groves, kind: .forest, existing: forestTiles, blocked: claimed.union(clearing).union(cleared), in: context) || changed
            changed = insertTerrain(chart.glades, kind: .longgrass, existing: longgrassTiles, blocked: claimed, in: context) || changed
            changed = insertTerrain(chart.dirt, kind: .dirt, existing: dirtTiles, blocked: claimed, in: context) || changed
            for item in placements where item.record.kind == .forest {
                let tile = FarmTile(column: item.column, row: item.row)
                if !chart.groves.contains(tile) || clearing.contains(tile) {
                    context.delete(item)
                    changed = true
                }
            }
        }

        let storedDecor = try context.fetch(FetchDescriptor<FarmDecor>())
        if woodsOn && rebuild {
            let haveTiles = Set(storedDecor.map { FarmTile(column: $0.column, row: $0.row) })
            let haveIDs = Set(storedDecor.map(\.id))
            var inserted = 0
            for draft in chart.decor {
                let tile = draft.tile
                if haveTiles.contains(tile) || haveIDs.contains(draft.id) || cleared.contains(tile) { continue }
                if clearing.contains(tile), let sprite = Woodland.sprite(draft.sprite), sprite.isTall { continue }
                context.insert(FarmDecor(
                    id: draft.id,
                    sprite: draft.sprite,
                    column: tile.column,
                    row: tile.row,
                    scale: draft.scale,
                    flipped: draft.flipped,
                    rotation: draft.rotation,
                    origin: draft.origin
                ))
                inserted += 1
                changed = true
                if inserted.isMultiple(of: 400) {
                    await Task.yield()
                }
            }
            let alive = chart.ground.union(chart.water)
            for item in storedDecor where item.origin == "gen" {
                let tile = FarmTile(column: item.column, row: item.row)
                let onLand = alive.contains(tile) || Woodland.orthogonal(tile).contains { chart.ground.contains($0) }
                let coversFarm = clearing.contains(tile) && (Woodland.sprite(item.sprite)?.isTall ?? false)
                if !onLand || coversFarm {
                    context.delete(item)
                    changed = true
                }
            }
        }
        if world.builtLevel != level || world.generatorVersion != Woodland.generatorVersion {
            world.builtLevel = level
            world.generatorVersion = Woodland.generatorVersion
            changed = true
        }
        if changed {
            try context.save()
        }
    }

    @MainActor
    private static func insertTerrain(
        _ tiles: Set<FarmTile>,
        kind: FarmItemKind,
        existing: Set<FarmTile>,
        blocked: Set<FarmTile>,
        in context: ModelContext
    ) -> Bool {
        var changed = false
        for tile in tiles where !existing.contains(tile) && !blocked.contains(tile) {
            context.insert(FarmPlacement(id: UUID(), kindRaw: kind.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
            changed = true
        }
        return changed
    }

    /// Drops seeded woods so a new generator can fill the current island. Placed decor stays.
    @MainActor
    private static func resetGeneratedWoods(in context: ModelContext, world: FarmWorld) throws {
        let placements = try context.fetch(FetchDescriptor<FarmPlacement>())
        let records = placements.map(\.record)
        let plan = FarmExpansion.plan(records: records, zones: [:], openTiles: Set(records.filter { $0.kind == .cleared }.map(\.tile)))
        let clearing = FarmExpansion.clearingTiles(for: plan)
        for item in placements {
            let tile = FarmTile(column: item.column, row: item.row)
            let kind = item.record.kind
            let outside = !clearing.contains(tile)
            if kind == .forest || (outside && (kind == .longgrass || kind == .dirt)) {
                context.delete(item)
            }
        }
        let decor = try context.fetch(FetchDescriptor<FarmDecor>())
        for item in decor where item.origin == "gen" {
            context.delete(item)
        }
        world.builtLevel = 0
        try context.save()
    }

    @MainActor
    static func writeDecor(_ decor: [DecorRecord], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<FarmDecor>())
        var byID: [UUID: FarmDecor] = [:]
        for item in existing {
            byID[item.id] = item
        }
        var keep = Set<UUID>()
        for record in decor {
            keep.insert(record.id)
            if let stored = byID[record.id] {
                stored.sprite = record.sprite
                stored.column = record.tile.column
                stored.row = record.tile.row
                stored.scale = record.scale
                stored.flipped = record.flipped
                stored.rotation = record.rotation
                stored.origin = record.origin
            } else {
                context.insert(FarmDecor(
                    id: record.id,
                    sprite: record.sprite,
                    column: record.tile.column,
                    row: record.tile.row,
                    scale: record.scale,
                    flipped: record.flipped,
                    rotation: record.rotation,
                    origin: record.origin
                ))
            }
        }
        for item in existing where !keep.contains(item.id) {
            context.delete(item)
        }
        try context.save()
    }

    /// Bed spots and planted vines sit on one tilled-soil layer.
    @MainActor
    private static func ensureTilledBeds(in context: ModelContext, zones: [String: String]) throws {
        let existing = try context.fetch(FetchDescriptor<FarmPlacement>())
        let records = existing.map(\.record)
        var trees = 0
        var beds = 0
        var vines = 0
        var planted: [FarmTile] = []
        for record in records where record.kind == .plant {
            guard let id = record.varietyID, let zone = zones[id] else { continue }
            switch FarmExpansion.spotKind(zone: zone) {
            case .tree: trees += 1
            case .bed:
                beds += 1
                planted.append(record.tile)
            case .vine:
                vines += 1
                planted.append(record.tile)
            }
        }
        let plan = FarmExpansion.plan(treeCount: trees, bedCount: beds, vineCount: vines)
        var wanted = Set(plan.bedSpots)
        wanted.formUnion(planted)
        let tilled = Set(records.filter { $0.kind == .tilled }.map(\.tile))
        var changed = false
        for tile in wanted where !tilled.contains(tile) {
            if let other = existing.first(where: { $0.record.kind.isTerrain && $0.column == tile.column && $0.row == tile.row }) {
                context.delete(other)
            }
            context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.tilled.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
            changed = true
        }
        if changed {
            try context.save()
        }
    }

    /// A few painted cells beside the yard, for screenshots of edit mode.
    @MainActor
    private static func ensureDemoTerrain(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<FarmPlacement>())
        let occupied = Set(existing.filter { $0.record.kind.isTerrain }.map { FarmTile(column: $0.column, row: $0.row) })
        let samples: [(FarmItemKind, FarmTile)] = [
            (.dirt, FarmTile(column: 11, row: 9)),
            (.dirt, FarmTile(column: 12, row: 9)),
            (.dirt, FarmTile(column: 12, row: 10)),
            (.sand, FarmTile(column: 15, row: 8)),
            (.sand, FarmTile(column: 16, row: 8)),
            (.sand, FarmTile(column: 15, row: 9)),
            (.longgrass, FarmTile(column: 9, row: 12)),
            (.longgrass, FarmTile(column: 10, row: 12)),
            (.longgrass, FarmTile(column: 9, row: 13))
        ]
        var inserted = false
        for sample in samples where !occupied.contains(sample.1) {
            context.insert(FarmPlacement(id: UUID(), kindRaw: sample.0.rawValue, varietySlug: nil, column: sample.1.column, row: sample.1.row))
            inserted = true
        }
        if inserted {
            try context.save()
        }
    }

    @MainActor
    static func write(_ records: [FarmRecord], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<FarmPlacement>())
        try write(records, replacing: existing, in: context)
    }

    @MainActor
    private static func write(_ records: [FarmRecord], replacing existing: [FarmPlacement], in context: ModelContext) throws {
        var byID: [UUID: FarmPlacement] = [:]
        for item in existing {
            byID[item.id] = item
        }
        var keep = Set<UUID>()
        for record in records {
            keep.insert(record.id)
            if let stored = byID[record.id] {
                stored.kindRaw = record.kind.rawValue
                stored.varietySlug = record.varietyID
                stored.column = record.tile.column
                stored.row = record.tile.row
            } else {
                context.insert(
                    FarmPlacement(
                        id: record.id,
                        kindRaw: record.kind.rawValue,
                        varietySlug: record.varietyID,
                        column: record.tile.column,
                        row: record.tile.row
                    )
                )
            }
        }
        for item in existing where !keep.contains(item.id) {
            context.delete(item)
        }
        try context.save()
    }
}
