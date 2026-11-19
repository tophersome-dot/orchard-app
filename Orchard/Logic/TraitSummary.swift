import Foundation

/// One tasting's sliders, used to learn a taste profile without the SwiftData model.
struct TasteSample: Equatable {
    var sweet: Double
    var tart: Double
    var crunch: Double
    var juicy: Double
    var overall: Double
    var overallIsOverride: Bool
}

/// Preferred slider values. Sweet and tart count more than crunch and juicy.
struct TasteProfile: Equatable {
    var sweet: Double
    var tart: Double
    var crunch: Double
    var juicy: Double

    /// Used until liked tastings outweigh it.
    static let prior = TasteProfile(sweet: 3.5, tart: 2.5, crunch: 4, juicy: 4)

    /// Three tastings scored 4. Each of those weighs `4 − 2.5 = 1.5`.
    static let priorWeight = 4.5
}

/// Turns the taste sliders into the half-step overall the apple picker uses.
enum TasteScore {
    static let sweetWeight = 1.0
    static let tartWeight = 1.0
    static let crunchWeight = 0.6
    static let juicyWeight = 0.6

    /// Liked override tastings pull the prior toward what Chris actually enjoys.
    /// Auto scores stay out, so a generated overall cannot teach the next one.
    static func profile(samples: [TasteSample]) -> TasteProfile {
        let prior = TasteProfile.prior
        var weight = TasteProfile.priorWeight
        var sweet = prior.sweet * weight
        var tart = prior.tart * weight
        var crunch = prior.crunch * weight
        var juicy = prior.juicy * weight
        for sample in samples {
            guard sample.overallIsOverride else { continue }
            let like = sample.overall - 2.5
            guard like > 0 else { continue }
            weight += like
            sweet += like * sample.sweet
            tart += like * sample.tart
            crunch += like * sample.crunch
            juicy += like * sample.juicy
        }
        return TasteProfile(
            sweet: sweet / weight,
            tart: tart / weight,
            crunch: crunch / weight,
            juicy: juicy / weight
        )
    }

    /// 5 is a perfect match. A far apple falls toward 1.
    static func automatic(
        sweet: Double,
        tart: Double,
        crunch: Double,
        juicy: Double,
        profile: TasteProfile
    ) -> Double {
        let raw = 5 - distance(sweet: sweet, tart: tart, crunch: crunch, juicy: juicy, profile: profile)
        let half = (raw * 2).rounded() / 2
        return min(5, max(1, half))
    }

    /// One line under the overall, from the trait furthest from the profile.
    static func hint(
        sweet: Double,
        tart: Double,
        crunch: Double,
        juicy: Double,
        profile: TasteProfile
    ) -> String {
        let gaps = [
            ("sweet", sweet - profile.sweet, sweetWeight),
            ("tart", tart - profile.tart, tartWeight),
            ("crunch", crunch - profile.crunch, crunchWeight),
            ("juicy", juicy - profile.juicy, juicyWeight)
        ]
        let biggest = gaps.max { lhs, rhs in
            abs(lhs.1) * lhs.2 < abs(rhs.1) * rhs.2
        }
        guard let biggest, abs(biggest.1) >= 1 else {
            return "Auto: close to your taste"
        }
        let higher = biggest.1 > 0
        let phrase: String
        switch biggest.0 {
        case "sweet":
            phrase = higher ? "sweeter than you usually like" : "less sweet than you usually like"
        case "tart":
            phrase = higher ? "tarter than you usually like" : "less tart than you usually like"
        case "crunch":
            phrase = higher ? "crunchier than you usually like" : "softer than you usually like"
        default:
            phrase = higher ? "juicier than you usually like" : "less juicy than you usually like"
        }
        return "Auto: \(phrase)"
    }

    private static func distance(
        sweet: Double,
        tart: Double,
        crunch: Double,
        juicy: Double,
        profile: TasteProfile
    ) -> Double {
        let weighted = sweetWeight * square(sweet - profile.sweet)
            + tartWeight * square(tart - profile.tart)
            + crunchWeight * square(crunch - profile.crunch)
            + juicyWeight * square(juicy - profile.juicy)
        let total = sweetWeight + tartWeight + crunchWeight + juicyWeight
        return (weighted / total).squareRoot()
    }

    private static func square(_ value: Double) -> Double {
        value * value
    }
}

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
