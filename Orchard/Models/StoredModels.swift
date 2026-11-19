import Foundation
import SwiftData
import SwiftUI

@Model
final class Variety {
    @Attribute(.unique) var slug: String
    var name: String
    var aliases: [String]
    var categoryRaw: String
    var zoneRaw: String
    var formRaw: String
    var recordKindRaw: String
    var pluCodes: [String]
    var baseHex: String
    var blushHex: String
    var patternRaw: String
    var blushAmount: Double
    var lenticels: Bool
    var skinVerified: Bool
    var skinNote: String
    var regions: [String]
    var seasonMonths: [Int]
    var seasonKindRaw: String
    var seasonNote: String
    var whereToFind: String
    var fact: String
    var factStatusRaw: String
    var isCustom: Bool

    // Leave these at the property default. Assigning relationships inside init
    // runs before SwiftData backing data exists.
    @Relationship(deleteRule: .cascade, inverse: \Tasting.variety)
    var tastings: [Tasting] = []

    @Relationship(deleteRule: .cascade, inverse: \HuntItem.variety)
    var huntItems: [HuntItem] = []

    init(
        slug: String,
        name: String,
        aliases: [String],
        categoryRaw: String,
        zoneRaw: String,
        formRaw: String,
        recordKindRaw: String,
        pluCodes: [String],
        baseHex: String,
        blushHex: String,
        patternRaw: String,
        blushAmount: Double,
        lenticels: Bool,
        skinVerified: Bool,
        skinNote: String,
        regions: [String],
        seasonMonths: [Int],
        seasonKindRaw: String,
        seasonNote: String,
        whereToFind: String,
        fact: String,
        factStatusRaw: String,
        isCustom: Bool
    ) {
        self.slug = slug
        self.name = name
        self.aliases = aliases
        self.categoryRaw = categoryRaw
        self.zoneRaw = zoneRaw
        self.formRaw = formRaw
        self.recordKindRaw = recordKindRaw
        self.pluCodes = pluCodes
        self.baseHex = baseHex
        self.blushHex = blushHex
        self.patternRaw = patternRaw
        self.blushAmount = blushAmount
        self.lenticels = lenticels
        self.skinVerified = skinVerified
        self.skinNote = skinNote
        self.regions = regions
        self.seasonMonths = seasonMonths
        self.seasonKindRaw = seasonKindRaw
        self.seasonNote = seasonNote
        self.whereToFind = whereToFind
        self.fact = fact
        self.factStatusRaw = factStatusRaw
        self.isCustom = isCustom
    }

    convenience init(entry: CatalogueEntry) {
        self.init(
            slug: entry.id,
            name: entry.name,
            aliases: entry.aliases,
            categoryRaw: entry.category,
            zoneRaw: entry.zone,
            formRaw: entry.form,
            recordKindRaw: entry.recordKind,
            pluCodes: entry.pluCodes,
            baseHex: entry.skin.base,
            blushHex: entry.skin.blush,
            patternRaw: entry.skin.pattern,
            blushAmount: entry.skin.blushAmount,
            lenticels: entry.skin.lenticels,
            skinVerified: entry.skinVerified,
            skinNote: entry.skinNote,
            regions: entry.regions,
            seasonMonths: entry.seasonMonths,
            seasonKindRaw: entry.seasonKind,
            seasonNote: entry.seasonNote,
            whereToFind: entry.whereToFind,
            fact: entry.fact,
            factStatusRaw: entry.factStatus,
            isCustom: false
        )
    }

    func apply(entry: CatalogueEntry) {
        name = entry.name
        aliases = entry.aliases
        categoryRaw = entry.category
        zoneRaw = entry.zone
        formRaw = entry.form
        recordKindRaw = entry.recordKind
        pluCodes = entry.pluCodes
        baseHex = entry.skin.base
        blushHex = entry.skin.blush
        patternRaw = entry.skin.pattern
        blushAmount = entry.skin.blushAmount
        lenticels = entry.skin.lenticels
        skinVerified = entry.skinVerified
        skinNote = entry.skinNote
        regions = entry.regions
        seasonMonths = entry.seasonMonths
        seasonKindRaw = entry.seasonKind
        seasonNote = entry.seasonNote
        whereToFind = entry.whereToFind
        fact = entry.fact
        factStatusRaw = entry.factStatus
    }
}

@Model
final class Tasting {
    var id: UUID
    var tastedAt: Date
    var sweet: Double
    var tart: Double
    var crunch: Double
    var juicy: Double
    var overall: Double
    /// False when overall is the average of the sliders. Existing rows default to a manual score.
    var overallIsOverride: Bool = true
    var notes: String
    @Attribute(.externalStorage) var photoData: Data?
    var isDebugSample: Bool
    var variety: Variety?

    init(
        id: UUID,
        tastedAt: Date,
        sweet: Double,
        tart: Double,
        crunch: Double,
        juicy: Double,
        overall: Double,
        notes: String,
        photoData: Data? = nil,
        isDebugSample: Bool = false,
        overallIsOverride: Bool = true,
        variety: Variety? = nil
    ) {
        self.id = id
        self.tastedAt = tastedAt
        self.sweet = sweet
        self.tart = tart
        self.crunch = crunch
        self.juicy = juicy
        self.overall = overall
        self.overallIsOverride = overallIsOverride
        self.notes = notes
        self.photoData = photoData
        self.isDebugSample = isDebugSample
        self.variety = variety
    }

    /// Manual overall when Chris set one. Otherwise the live average of the sliders.
    var scoreForDisplay: Double {
        if overallIsOverride { return overall }
        return TasteScore.automatic(sweet: sweet, tart: tart, crunch: crunch, juicy: juicy)
    }
}

@Model
final class FarmPlacement {
    var id: UUID
    var kindRaw: String
    var varietySlug: String?
    var column: Int
    var row: Int

    init(id: UUID, kindRaw: String, varietySlug: String?, column: Int, row: Int) {
        self.id = id
        self.kindRaw = kindRaw
        self.varietySlug = varietySlug
        self.column = column
        self.row = row
    }

    var record: FarmRecord {
        FarmRecord(
            id: id,
            kind: FarmItemKind(rawValue: kindRaw) ?? .path,
            varietyID: varietySlug,
            tile: FarmTile(column: column, row: row)
        )
    }
}

@Model
final class FarmDecor {
    var id: UUID
    var sprite: String
    var column: Int
    var row: Int
    var scale: Double
    var flipped: Bool
    var rotation: Double
    var origin: String

    init(id: UUID, sprite: String, column: Int, row: Int, scale: Double, flipped: Bool, rotation: Double, origin: String) {
        self.id = id
        self.sprite = sprite
        self.column = column
        self.row = row
        self.scale = scale
        self.flipped = flipped
        self.rotation = rotation
        self.origin = origin
    }

    var record: DecorRecord {
        DecorRecord(
            id: id,
            sprite: sprite,
            tile: FarmTile(column: column, row: row),
            scale: scale,
            flipped: flipped,
            rotation: rotation,
            origin: origin
        )
    }
}

/// An item Chris lifted off the map. Plants here are not placed again by the yard layout.
struct StoredRecord: Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: FarmItemKind
    var varietyID: String?
    var sprite: String?
    var scale: Double
    var flipped: Bool
    var rotation: Double
}

@Model
final class FarmStoredItem {
    var id: UUID
    var kindRaw: String
    var varietySlug: String?
    var sprite: String?
    var scale: Double
    var flipped: Bool
    var rotation: Double

    init(
        id: UUID,
        kindRaw: String,
        varietySlug: String?,
        sprite: String?,
        scale: Double,
        flipped: Bool,
        rotation: Double
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.varietySlug = varietySlug
        self.sprite = sprite
        self.scale = scale
        self.flipped = flipped
        self.rotation = rotation
    }

    var record: StoredRecord {
        StoredRecord(
            id: id,
            kind: FarmItemKind(rawValue: kindRaw) ?? .bush,
            varietyID: varietySlug,
            sprite: sprite,
            scale: scale,
            flipped: flipped,
            rotation: rotation
        )
    }
}

/// A tasted variety Chris removed from the farm. The tasting record stays.
@Model
final class FarmSkippedPlant {
    var varietySlug: String

    init(varietySlug: String) {
        self.varietySlug = varietySlug
    }
}

@Model
final class FarmWorld {
    var seed: Int
    var builtLevel: Int
    var generatorVersion: Int = 0

    init(seed: Int, builtLevel: Int = 0, generatorVersion: Int = 0) {
        self.seed = seed
        self.builtLevel = builtLevel
        self.generatorVersion = generatorVersion
    }
}

@Model
final class HuntItem {
    var id: UUID
    var addedAt: Date
    var variety: Variety?

    init(id: UUID, addedAt: Date, variety: Variety? = nil) {
        self.id = id
        self.addedAt = addedAt
        self.variety = variety
    }
}

extension Variety {
    var zone: FarmZone { FarmZone(rawValue: zoneRaw) ?? .orchard }
    var form: PlantForm { PlantForm(rawValue: formRaw) ?? .apple }
    var factStatus: FactStatus { FactStatus(rawValue: factStatusRaw) ?? .none }
    var seasonKind: SeasonKind { SeasonKind(rawValue: seasonKindRaw) ?? .unspecified }
    var recordKind: RecordKind { RecordKind(rawValue: recordKindRaw) ?? .cultivar }
    var categoryTitle: String { ProduceCategory.title(for: categoryRaw) }

    var tastingList: [Tasting] { tastings }
    var huntList: [HuntItem] { huntItems }
    var isTried: Bool { !tastingList.isEmpty }

    var latestTasting: Tasting? {
        tastingList.max { $0.tastedAt < $1.tastedAt }
    }

    var firstTastedAt: Date? {
        tastingList.map(\.tastedAt).min()
    }

    var onHunt: Bool { !huntList.isEmpty }

    var fruitSkin: FruitSkin {
        FruitSkin(
            base: Color(hex: baseHex),
            blush: Color(hex: blushHex),
            pattern: SkinPattern(rawValue: patternRaw) ?? .solid,
            blushAmount: blushAmount,
            lenticels: lenticels
        )
    }

    func asEntry() -> CatalogueEntry {
        CatalogueEntry(
            id: slug,
            name: name,
            aliases: aliases,
            category: categoryRaw,
            zone: zoneRaw,
            form: formRaw,
            recordKind: recordKindRaw,
            pluCodes: pluCodes,
            skin: SkinRecord(
                base: baseHex,
                blush: blushHex,
                pattern: patternRaw,
                blushAmount: blushAmount,
                lenticels: lenticels
            ),
            skinVerified: skinVerified,
            skinNote: skinNote,
            regions: regions,
            seasonMonths: seasonMonths,
            seasonKind: seasonKindRaw,
            seasonNote: seasonNote,
            whereToFind: whereToFind,
            fact: fact,
            factStatus: factStatusRaw,
            sources: []
        )
    }

    func snapshot() -> TastingSnapshot? {
        guard let latest = latestTasting else { return nil }
        return TastingSnapshot(
            overall: latest.scoreForDisplay,
            notes: latest.notes,
            sweet: latest.sweet,
            tart: latest.tart,
            crunch: latest.crunch,
            juicy: latest.juicy,
            tastedAt: latest.tastedAt
        )
    }
}

struct FruitSkin: Equatable {
    var base: Color
    var blush: Color
    var pattern: SkinPattern
    var blushAmount: Double
    var lenticels: Bool
}
