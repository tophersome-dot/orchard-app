import Foundation
import SwiftData

enum FarmLayout {
    /// Makes sure the starter yard exists and every tasted variety has a spot.
    /// Safe to call more than once. Does not move anything the player already placed.
    @MainActor
    static func sync(context: ModelContext, tried: [(id: String, zone: String)]) throws {
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
        try ensureWoodland(in: context, zones: zones, tastedCount: Set(tried.map(\.id)).count)
    }

    /// Grows the island and fills new land. Existing clears, paints, and moved decor stay put.
    @MainActor
    private static func ensureWoodland(in context: ModelContext, zones: [String: String], tastedCount: Int) throws {
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
        let chart = Woodland.make(
            seed: UInt64(world.seed),
            level: level,
            clearing: clearing,
            blocked: blocked,
            woods: woodsOn
        )
        let previous = world.builtLevel >= 1
            ? Woodland.make(
                seed: UInt64(world.seed),
                level: world.builtLevel,
                clearing: clearing,
                blocked: blocked,
                woods: woodsOn
            )
            : IslandChart.empty
        let fresh = chart.ground.union(chart.water).subtracting(previous.ground).subtracting(previous.water)
        let first = world.builtLevel < 1
        let cleared = Set(records.filter { $0.kind == .cleared }.map(\.tile))
        var changed = false

        func terrain(at tile: FarmTile) -> [FarmPlacement] {
            placements.filter { $0.column == tile.column && $0.row == tile.row && $0.record.kind.isTerrain }
        }

        for tile in chart.lakes {
            let existing = terrain(at: tile)
            if existing.contains(where: { $0.record.kind == .lake }) { continue }
            for item in existing where item.record.kind != .path {
                context.delete(item)
            }
            context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.lake.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
            changed = true
        }
        for tile in chart.creek {
            let existing = terrain(at: tile)
            if existing.contains(where: { $0.record.kind == .creek }) { continue }
            for item in existing where item.record.kind != .path {
                context.delete(item)
            }
            context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.creek.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
            changed = true
        }

        let claimed = Set(records.filter { record in
            switch record.kind {
            case .path, .dirt, .sand, .longgrass, .tilled, .cleared: true
            default: false
            }
        }.map(\.tile))

        if woodsOn {
            for tile in chart.groves where !clearing.contains(tile) && !cleared.contains(tile) && !claimed.contains(tile) {
                if records.contains(where: { $0.kind == .forest && $0.tile == tile }) { continue }
                guard first || fresh.contains(tile) else { continue }
                context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.forest.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
                changed = true
            }
            for tile in chart.glades where !claimed.contains(tile) && (first || fresh.contains(tile)) {
                if records.contains(where: { $0.kind == .longgrass && $0.tile == tile }) { continue }
                context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.longgrass.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
                changed = true
            }
            for tile in chart.dirt where !claimed.contains(tile) && (first || fresh.contains(tile)) {
                if records.contains(where: { $0.kind == .dirt && $0.tile == tile }) { continue }
                context.insert(FarmPlacement(id: UUID(), kindRaw: FarmItemKind.dirt.rawValue, varietySlug: nil, column: tile.column, row: tile.row))
                changed = true
            }
            for tile in clearing {
                for item in placements where item.column == tile.column && item.row == tile.row && item.record.kind == .forest {
                    context.delete(item)
                    changed = true
                }
            }
        }

        let storedDecor = try context.fetch(FetchDescriptor<FarmDecor>())
        if woodsOn {
            let haveTiles = Set(storedDecor.map { FarmTile(column: $0.column, row: $0.row) })
            let haveIDs = Set(storedDecor.map(\.id))
            for draft in chart.decor {
                let tile = draft.tile
                if haveTiles.contains(tile) || haveIDs.contains(draft.id) || cleared.contains(tile) { continue }
                let touchesFresh = Woodland.orthogonal(tile).contains { fresh.contains($0) }
                guard first || fresh.contains(tile) || touchesFresh else { continue }
                if clearing.contains(tile) && !first { continue }
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
                changed = true
            }
            for item in storedDecor where item.origin == "gen" && clearing.contains(FarmTile(column: item.column, row: item.row)) {
                if let sprite = Woodland.sprite(item.sprite), sprite.isTall {
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
