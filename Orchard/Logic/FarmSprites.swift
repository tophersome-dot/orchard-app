import UIKit

/// Asset catalog names for the isometric farm sprites.
/// Drop a transparent PNG into an imageset with this exact name.
/// Missing images fall back to the drawn views.
enum FarmSprite {
    static let wiltingTree = "tree_wilting"
    static let sapling = "tree_sapling"
    static let emptyBed = "bed_empty"
    static let fence = "fence_picket_straight"
    static let tractor = "tractor"
    static let bush = "bush"
    static let rock = "rock"

    static func house(_ tier: HouseTier) -> String {
        switch tier {
        case .shed: "house_1_shed"
        case .cottage: "house_2_cottage"
        case .farmhouse: "house_3_farmhouse"
        case .homestead: "house_4_homestead"
        }
    }

    static func tree(category: String, varietyID: String) -> String {
        "tree_\(category)_\(varietyID)"
    }

    static func bed(varietyID: String) -> String { "bed_\(varietyID)" }
    static func vine(varietyID: String) -> String { "vine_\(varietyID)" }
    static func fruit(varietyID: String) -> String { "fruit_\(varietyID)" }

    static func image(named name: String) -> UIImage? {
        UIImage(named: name)
    }

    /// Loved plants scale up a little. Wilting trees draw slightly smaller.
    static func scale(for rating: Double?) -> CGFloat {
        guard let rating else { return 1 }
        if rating >= 4 { return 1.12 }
        if rating < 2.5 { return 0.92 }
        return 1
    }

    static func usesWiltingTree(zone: String, rating: Double?) -> Bool {
        guard let rating, rating < 2.5 else { return false }
        return FarmExpansion.spotKind(zone: zone) == .tree
    }

    static func plantName(zone: String, category: String, varietyID: String, rating: Double?) -> String {
        if usesWiltingTree(zone: zone, rating: rating) {
            return wiltingTree
        }
        switch FarmExpansion.spotKind(zone: zone) {
        case .tree: return tree(category: category, varietyID: varietyID)
        case .bed: return bed(varietyID: varietyID)
        case .vine: return vine(varietyID: varietyID)
        }
    }
}
