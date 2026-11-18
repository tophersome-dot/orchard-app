import UIKit

/// Illustrated assets can replace the procedural drawings later.
/// Add `variety-<id>` for the fruit glyph and `plant-<id>` for the whole plant.
enum VarietyArt {
    static func fruitName(for id: String) -> String { "variety-\(id)" }
    static func plantName(for id: String) -> String { "plant-\(id)" }

    static func fruitImage(id: String) -> UIImage? {
        UIImage(named: fruitName(for: id))
    }

    static func plantImage(id: String) -> UIImage? {
        UIImage(named: plantName(for: id))
    }
}
