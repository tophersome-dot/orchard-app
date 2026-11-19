import Foundation

enum StickerMatch {
    struct Suggestion: Equatable {
        var varietyID: String
        var reason: String
    }

    /// Prefer a variety name or alias printed on the label. Fall back to a 4-digit PLU,
    /// including the organic 9-prefix. Returns nil when nothing lines up.
    static func suggest(text: String, varieties: [CatalogueEntry]) -> Suggestion? {
        let compact = OrchardText.compact(text)
        let words = Set(OrchardText.words(text))
        var bestLength = 0
        var bestID: String?
        for variety in varieties {
            for term in [variety.name] + variety.aliases {
                let termCompact = OrchardText.compact(term)
                let termWords = OrchardText.words(term)
                guard termCompact.count >= 3 else { continue }
                let hit: Bool
                if termWords.count >= 2 || termCompact.count >= 5 {
                    hit = compact.contains(termCompact)
                } else {
                    hit = words.contains(termCompact)
                }
                if hit && termCompact.count > bestLength {
                    bestLength = termCompact.count
                    bestID = variety.id
                }
            }
        }
        if let bestID {
            return Suggestion(varietyID: bestID, reason: "Name on the label")
        }

        let runs = text.split { !$0.isNumber }.map(String.init).filter { $0.count == 4 || $0.count == 5 }
        let codes = Set(runs)
        for variety in varieties {
            for plu in variety.pluCodes where codes.contains(plu) || codes.contains("9" + plu) {
                return Suggestion(varietyID: variety.id, reason: "PLU \(plu)")
            }
        }
        return nil
    }
}
