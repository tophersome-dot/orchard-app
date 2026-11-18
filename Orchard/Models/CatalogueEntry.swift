import Foundation

struct CatalogueDocument: Codable, Equatable {
    var version: Int
    var about: String
    var varieties: [CatalogueEntry]
}

struct SkinRecord: Codable, Equatable {
    var base: String
    var blush: String
    var pattern: String
    var blushAmount: Double
    var lenticels: Bool
}

struct CatalogueEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var aliases: [String]
    var category: String
    var zone: String
    var form: String
    var recordKind: String
    var pluCodes: [String]
    var skin: SkinRecord
    var skinVerified: Bool
    var skinNote: String
    var regions: [String]
    var seasonMonths: [Int]
    var seasonKind: String
    var seasonNote: String
    var whereToFind: String
    var fact: String
    var factStatus: String
    var sources: [String]
}

struct TastingSnapshot: Equatable {
    var overall: Double
    var notes: String
    var sweet: Double
    var tart: Double
    var crunch: Double
    var juicy: Double
    var tastedAt: Date
}

struct ShopHit: Equatable, Identifiable {
    var id: String { variety.id }
    var variety: CatalogueEntry
    var latest: TastingSnapshot?
}
