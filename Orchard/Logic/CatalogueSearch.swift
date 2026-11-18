import Foundation

enum CatalogueSearch {
    /// Empty query returns tasted varieties only, highest score first.
    /// A typed query also returns matching varieties that have not been tasted.
    static func shopResults(
        query: String,
        varieties: [CatalogueEntry],
        latestByVariety: [String: TastingSnapshot]
    ) -> (tried: [ShopHit], untried: [ShopHit]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool: [CatalogueEntry]
        if trimmed.isEmpty {
            pool = varieties.filter { latestByVariety[$0.id] != nil }
        } else {
            pool = varieties.filter { matches($0, query: trimmed) }
        }

        var tried: [ShopHit] = []
        var untried: [ShopHit] = []
        for variety in pool {
            let hit = ShopHit(variety: variety, latest: latestByVariety[variety.id])
            if hit.latest == nil {
                if !trimmed.isEmpty {
                    untried.append(hit)
                }
            } else {
                tried.append(hit)
            }
        }

        tried.sort { lhs, rhs in
            let left = lhs.latest?.overall ?? 0
            let right = rhs.latest?.overall ?? 0
            if left != right { return left > right }
            return lhs.variety.name.localizedCaseInsensitiveCompare(rhs.variety.name) == .orderedAscending
        }
        untried.sort {
            $0.variety.name.localizedCaseInsensitiveCompare($1.variety.name) == .orderedAscending
        }
        return (tried, untried)
    }

    static func matches(_ variety: CatalogueEntry, query: String) -> Bool {
        let compact = OrchardText.compact(query)
        if compact.isEmpty { return true }
        let fields = [variety.name, variety.category] + variety.aliases
        if fields.contains(where: { OrchardText.compact($0).contains(compact) }) {
            return true
        }
        let digits = compact.allSatisfy(\.isNumber)
        if digits && compact.count >= 3 {
            return variety.pluCodes.contains { $0.contains(compact) }
        }
        return false
    }
}
