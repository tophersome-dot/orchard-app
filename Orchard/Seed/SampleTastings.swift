import Foundation
import SwiftData

enum SampleTastings {
    struct Spec {
        var slug: String
        var overall: Double
        var sweet: Double
        var tart: Double
        var crunch: Double
        var juicy: Double
        var notes: String
    }

    /// Screenshot data only. Not Chris's real notebook.
    static let specs: [Spec] = [
        Spec(slug: "pink-lady", overall: 4.5, sweet: 4, tart: 2, crunch: 5, juicy: 4, notes: "Great crunch, buy again, Coles had good ones"),
        Spec(slug: "granny-smith", overall: 2, sweet: 1.5, tart: 5, crunch: 4, juicy: 3, notes: "Too sour for snacking"),
        Spec(slug: "jazz", overall: 4, sweet: 3.5, tart: 3.5, crunch: 5, juicy: 3.5, notes: "Tangy, great crunch"),
        Spec(slug: "envy", overall: 3.5, sweet: 5, tart: 1.5, crunch: 2.5, juicy: 3.5, notes: "Very sweet, a bit soft"),
        Spec(slug: "red-delicious", overall: 1.5, sweet: 3, tart: 1, crunch: 1, juicy: 2, notes: "Mealy, skip"),
        Spec(slug: "bravo", overall: 5, sweet: 4.5, tart: 2.5, crunch: 5, juicy: 4.5, notes: "Deep colour, proper crunch"),
        Spec(slug: "fuji", overall: 4, sweet: 4.5, tart: 1.5, crunch: 4, juicy: 4, notes: "Honey sweet"),
        Spec(slug: "royal-gala", overall: 3, sweet: 3.5, tart: 2, crunch: 3, juicy: 3, notes: "Fine, nothing special"),
        Spec(slug: "sundowner", overall: 2.5, sweet: 3, tart: 3, crunch: 3, juicy: 2.5, notes: "Late season, a bit plain"),
        Spec(slug: "packhams-triumph", overall: 4, sweet: 4, tart: 1, crunch: 2, juicy: 4.5, notes: "Juicy when ripe"),
        Spec(slug: "dutch-carrot", overall: 4.5, sweet: 4, tart: 0.5, crunch: 4.5, juicy: 3, notes: "Sweet and snappy"),
        Spec(slug: "purple-carrot", overall: 3.5, sweet: 3, tart: 1, crunch: 4, juicy: 3, notes: "Earthier than the Dutch ones"),
        Spec(slug: "yellow-carrot", overall: 3, sweet: 3, tart: 0.5, crunch: 3, juicy: 2.5, notes: "Mild"),
        Spec(slug: "cherry-tomato", overall: 4.5, sweet: 4, tart: 2.5, crunch: 3, juicy: 5, notes: "Bursting"),
        Spec(slug: "menindee-seedless", overall: 3, sweet: 3.5, tart: 1, crunch: 3, juicy: 3.5, notes: "Decent table grape"),
        Spec(slug: "cotton-candy", overall: 4.5, sweet: 5, tart: 0.5, crunch: 3.5, juicy: 4, notes: "Tastes like the name"),
        Spec(slug: "kensington-pride", overall: 4, sweet: 4.5, tart: 1.5, crunch: 1, juicy: 5, notes: "Summer in a mouthful")
    ]

    static func seed(_ context: ModelContext) throws {
        let varieties = try context.fetch(FetchDescriptor<Variety>())
        let bySlug = Dictionary(grouping: varieties, by: \.slug).compactMapValues(\.first)
        let base = Date(timeIntervalSince1970: 1_720_000_000)
        for (index, spec) in specs.enumerated() {
            guard let variety = bySlug[spec.slug] else { continue }
            if variety.tastingList.contains(where: \.isDebugSample) { continue }
            if variety.isTried { continue }
            let tasting = Tasting(
                id: UUID(),
                tastedAt: base.addingTimeInterval(Double(index) * 86_400),
                sweet: spec.sweet,
                tart: spec.tart,
                crunch: spec.crunch,
                juicy: spec.juicy,
                overall: spec.overall,
                notes: spec.notes,
                isDebugSample: true
            )
            context.insert(tasting)
            tasting.variety = variety
        }
        try context.save()
    }
}
