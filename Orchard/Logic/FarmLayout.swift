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
        let next = FarmExpansion.reconciled(records, tried: tried, tastedCount: tastedCount)
        if next != records {
            try write(next, replacing: existing, in: context)
        }
        if DebugLaunch.demoTerrain {
            try ensureDemoTerrain(in: context)
        }
        try ensureTilledBeds(in: context, zones: Dictionary(uniqueKeysWithValues: tried.map { ($0.id, $0.zone) }))
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
