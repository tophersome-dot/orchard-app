import Foundation

enum CatalogueValidator {
    static let patterns: Set<String> = ["solid", "blush", "stripe", "speckle"]
    static let zones: Set<String> = ["orchard", "bed", "trellis", "greenhouse"]
    static let forms: Set<String> = ["apple", "pear", "mango", "grape", "carrot", "tomato"]
    static let categories: Set<String> = ["apple", "pear", "grape", "tropical", "vegetable"]
    static let factStatuses: Set<String> = ["verified", "unverified", "none"]
    static let seasonKinds: Set<String> = ["harvest", "retail", "unspecified"]
    static let recordKinds: Set<String> = ["cultivar", "marketType"]

    static func issues(in document: CatalogueDocument) -> [String] {
        var issues: [String] = []
        var seen = Set<String>()
        for entry in document.varieties {
            if entry.id.isEmpty {
                issues.append("blank id")
                continue
            }
            if !seen.insert(entry.id).inserted {
                issues.append("\(entry.id) duplicated")
            }
            if entry.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("\(entry.id) missing name")
            }
            if !categories.contains(entry.category) { issues.append("\(entry.id) bad category") }
            if !zones.contains(entry.zone) { issues.append("\(entry.id) bad zone") }
            if !forms.contains(entry.form) { issues.append("\(entry.id) bad form") }
            if !recordKinds.contains(entry.recordKind) { issues.append("\(entry.id) bad recordKind") }
            if !factStatuses.contains(entry.factStatus) { issues.append("\(entry.id) bad factStatus") }
            if !seasonKinds.contains(entry.seasonKind) { issues.append("\(entry.id) bad seasonKind") }
            if !patterns.contains(entry.skin.pattern) { issues.append("\(entry.id) bad pattern") }
            if entry.skin.blushAmount < 0 || entry.skin.blushAmount > 1 {
                issues.append("\(entry.id) blushAmount out of range")
            }
            if !isHex(entry.skin.base) || !isHex(entry.skin.blush) {
                issues.append("\(entry.id) bad hex")
            }
            if entry.seasonMonths.contains(where: { $0 < 1 || $0 > 12 }) {
                issues.append("\(entry.id) bad season month")
            }
            switch entry.factStatus {
            case "verified":
                if entry.fact.trimmingCharacters(in: .whitespaces).isEmpty || entry.sources.isEmpty {
                    issues.append("\(entry.id) verified fact needs text and a source")
                }
            case "unverified":
                if entry.sources.isEmpty { issues.append("\(entry.id) unverified fact needs a source") }
            case "none":
                if !entry.fact.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append("\(entry.id) factStatus none should have an empty fact")
                }
            default:
                break
            }
            if entry.recordKind == "cultivar" && !entry.whereToFind.trimmingCharacters(in: .whitespaces).isEmpty && entry.sources.isEmpty {
                issues.append("\(entry.id) whereToFind needs a source")
            }
            if entry.category == "apple" {
                let hook = !entry.whereToFind.trimmingCharacters(in: .whitespaces).isEmpty || !entry.regions.isEmpty
                if !hook { issues.append("\(entry.id) apple has no commercial hook") }
            }
        }
        let apples = document.varieties.filter { $0.category == "apple" }
        if apples.isEmpty { issues.append("apple catalogue is empty") }
        return issues
    }

    private static func isHex(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }
}
