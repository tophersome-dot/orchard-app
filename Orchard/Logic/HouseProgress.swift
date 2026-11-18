import Foundation

/// The farmhouse is the progression element. There is no farmer or avatar.
/// Edit `thresholds` to retune how many distinct tasted varieties each stage needs.
enum HouseTier: Int, CaseIterable, Equatable {
    case shed
    case cottage
    case farmhouse
    case homestead

    var title: String {
        switch self {
        case .shed: "Shed"
        case .cottage: "Cottage"
        case .farmhouse: "Farmhouse"
        case .homestead: "Homestead"
        }
    }
}

struct HouseProgress: Equatable {
    var tier: HouseTier
    var tastedCount: Int
    var nextTier: HouseTier?
    /// Distinct varieties still needed to reach the next tier. Nil at the homestead.
    var varietiesToNext: Int?
    /// Progress from the current tier's threshold toward the next one. 1 at the top tier.
    var fraction: Double

    var subtitle: String {
        if let nextTier, let varietiesToNext {
            return "\(tastedCount) tasted · \(varietiesToNext) to \(nextTier.title.lowercased())"
        }
        return "\(tastedCount) tasted · the homestead is up"
    }
}

enum HouseRules {
    /// Distinct tasted varieties required to reach each tier, lowest first.
    /// Shed is the starting building, so its minimum stays at 0.
    static let thresholds: [(tier: HouseTier, minimum: Int)] = [
        (.shed, 0),
        (.cottage, 3),
        (.farmhouse, 8),
        (.homestead, 15)
    ]

    static func progress(for tastedCount: Int) -> HouseProgress {
        let count = max(0, tastedCount)
        let sorted = thresholds.sorted { $0.minimum < $1.minimum }
        let current = sorted.last(where: { count >= $0.minimum }) ?? sorted[0]
        let next = sorted.first(where: { $0.minimum > current.minimum })
        let fraction: Double
        if let next {
            let span = max(1, next.minimum - current.minimum)
            fraction = min(1, max(0, Double(count - current.minimum) / Double(span)))
        } else {
            fraction = 1
        }
        return HouseProgress(
            tier: current.tier,
            tastedCount: count,
            nextTier: next?.tier,
            varietiesToNext: next.map { max(0, $0.minimum - count) },
            fraction: fraction
        )
    }
}
