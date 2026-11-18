import Foundation

enum TraitSummary {
    static func glance(notes: String, sweet: Double, tart: Double, crunch: Double, juicy: Double) -> String {
        let line = notes
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !line.isEmpty {
            if line.count <= 80 { return line }
            let end = line.index(line.startIndex, offsetBy: 79)
            return String(line[..<end]).trimmingCharacters(in: .whitespaces) + "…"
        }
        let ranked = [
            ("Sweet", sweet),
            ("Tart", tart),
            ("Crunchy", crunch),
            ("Juicy", juicy)
        ]
        .filter { $0.1 >= 3.5 }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
        if ranked.isEmpty { return "No note yet" }
        if ranked.count == 1 { return ranked[0] }
        return ranked.prefix(2).joined(separator: " and ")
    }
}
