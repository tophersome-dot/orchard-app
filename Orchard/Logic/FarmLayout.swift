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
        guard next != records else { return }
        try write(next, replacing: existing, in: context)
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
