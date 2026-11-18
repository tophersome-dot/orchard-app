import Foundation
import SwiftData

enum SeedError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "Orchard couldn't find catalogue.json in the app bundle."
        }
    }
}

enum CatalogueSeeder {
    /// Inserts catalogue rows and refreshes factual fields from the bundled JSON.
    /// Tastings, hunt items and custom varieties are left alone. Removed JSON rows are not deleted.
    static func sync(_ context: ModelContext) throws {
        guard let url = Bundle.main.url(forResource: "catalogue", withExtension: "json") else {
            throw SeedError.missingFile
        }
        let document = try JSONDecoder().decode(CatalogueDocument.self, from: Data(contentsOf: url))
        let existing = try context.fetch(FetchDescriptor<Variety>())
        var bySlug: [String: Variety] = [:]
        for variety in existing {
            if bySlug[variety.slug] == nil {
                bySlug[variety.slug] = variety
            }
        }
        for entry in document.varieties {
            if let found = bySlug[entry.id] {
                if found.isCustom { continue }
                found.apply(entry: entry)
            } else {
                context.insert(Variety(entry: entry))
            }
        }
        try context.save()
    }
}
