import UIKit

private let spriteLock = NSLock()

/// Asset catalog names for the isometric farm sprites.
/// Drop a transparent PNG into an imageset with this exact name.
/// Missing images fall back to the drawn views.
enum FarmSprite {
    static let wiltingTree = "tree_wilting"
    static let sapling = "tree_sapling"
    static let emptyBed = "soil_bed"
    static let soilTree = "soil_tree"
    static let soilVine = "soil_vine"
    static let grass = "ground_grass"
    static let grassDark = "ground_grass_dark"
    static let stonePath = "path_stone"
    static let fence = "fence_picket_straight"
    static let tractor = "tractor"
    static let bush = "bush"
    static let rock = "rock"
    /// Side runs of the orchard fence. Stored on the fence record so the sprite can be mirrored.
    static let fenceSide = "side"

    private static var images: [String: UIImage] = [:]
    private static var aspects: [String: CGFloat] = [:]

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
        spriteLock.lock()
        let cached = images[name]
        spriteLock.unlock()
        if let cached { return cached }
        guard let image = UIImage(named: name) else { return nil }
        store(image, named: name)
        return image
    }

    /// Decodes sprites off the main thread so the first farm frame is not waiting on PNG inflation.
    static func warm(_ names: [String]) async {
        let pending = names.filter { name in
            spriteLock.lock()
            let have = images[name] != nil
            spriteLock.unlock()
            return !have
        }
        let unique = Array(Set(pending))
        guard !unique.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                for name in unique {
                    autoreleasepool {
                        guard let image = UIImage(named: name)?.preparingForDisplay() else { return }
                        store(image, named: name)
                    }
                }
                continuation.resume()
            }
        }
    }

    private static func store(_ image: UIImage, named name: String) {
        spriteLock.lock()
        images[name] = image
        if image.size.width > 0 {
            aspects[name] = image.size.height / image.size.width
        }
        spriteLock.unlock()
    }

    /// Height ÷ width. Nil until the image has been read once.
    static func aspect(named name: String) -> CGFloat? {
        spriteLock.lock()
        let known = aspects[name]
        spriteLock.unlock()
        if let known { return known }
        guard let image = image(named: name), image.size.width > 0 else { return nil }
        return image.size.height / image.size.width
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
