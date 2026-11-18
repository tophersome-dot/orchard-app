import Foundation
@testable import Orchard

enum TestFixtures {
    static func entry(
        id: String,
        name: String,
        aliases: [String] = [],
        category: String = "apple",
        plu: [String] = [],
        whereToFind: String = "Shops",
        regions: [String] = [],
        fact: String = "",
        factStatus: String = "none",
        sources: [String] = [],
        seasonMonths: [Int] = []
    ) -> CatalogueEntry {
        CatalogueEntry(
            id: id,
            name: name,
            aliases: aliases,
            category: category,
            zone: "orchard",
            form: "apple",
            recordKind: "cultivar",
            pluCodes: plu,
            skin: SkinRecord(base: "#FF0000", blush: "#00FF00", pattern: "solid", blushAmount: 0, lenticels: false),
            skinVerified: true,
            skinNote: "",
            regions: regions,
            seasonMonths: seasonMonths,
            seasonKind: "unspecified",
            seasonNote: "",
            whereToFind: whereToFind,
            fact: fact,
            factStatus: factStatus,
            sources: sources
        )
    }

    static func snapshot(_ overall: Double, notes: String = "Crunchy") -> TastingSnapshot {
        TastingSnapshot(overall: overall, notes: notes, sweet: 3, tart: 2, crunch: 4, juicy: 3, tastedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
