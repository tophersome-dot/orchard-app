import CoreGraphics
import Foundation

/// How a tasted variety is drawn on the farm. Loved fruit is large and lush,
/// middling fruit stays ordinary, and low scores wilt.
struct PlantHealth: Equatable {
    enum Condition: String, Equatable {
        case lush
        case ordinary
        case wilted
    }

    enum Badge: String, Equatable {
        case loved
        case mixed
        case disliked

        var label: String {
            switch self {
            case .loved: "Loved"
            case .mixed: "Mixed"
            case .disliked: "Disliked"
            }
        }
    }

    var condition: Condition
    var badge: Badge
    /// Drawn size relative to an ordinary plant. Grows with the rating.
    var scale: CGFloat
    /// 0 upright, 1 drooping.
    var wilt: CGFloat
    /// 0 saturated leaves, 1 brown and dull.
    var leafDull: CGFloat

    static func from(rating: Double) -> PlantHealth {
        let clamped = min(5, max(1, rating))
        let scale = 0.70 + CGFloat((clamped - 1) / 4) * 0.54
        if clamped >= 4 {
            return PlantHealth(condition: .lush, badge: .loved, scale: scale, wilt: 0, leafDull: 0)
        }
        if clamped >= 2.5 {
            return PlantHealth(condition: .ordinary, badge: .mixed, scale: scale, wilt: 0.08, leafDull: 0.18)
        }
        let severity = CGFloat((2.5 - clamped) / 1.5)
        return PlantHealth(
            condition: .wilted,
            badge: .disliked,
            scale: scale,
            wilt: 0.45 + severity * 0.4,
            leafDull: 0.55 + severity * 0.35
        )
    }
}
