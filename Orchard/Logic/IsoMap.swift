import CoreGraphics
import Foundation

struct FarmTile: Hashable, Equatable {
    var column: Int
    var row: Int
}

/// Three-quarter isometric projection. `center` is the middle of a tile.
enum IsoMap {
    static let tileWidth: CGFloat = 84
    static let tileHeight: CGFloat = 42

    static func center(_ tile: FarmTile) -> CGPoint {
        CGPoint(
            x: CGFloat(tile.column - tile.row) * tileWidth / 2,
            y: CGFloat(tile.column + tile.row) * tileHeight / 2
        )
    }

    static func tile(at point: CGPoint) -> FarmTile {
        let halfWidth = tileWidth / 2
        let halfHeight = tileHeight / 2
        let column = (point.x / halfWidth + point.y / halfHeight) / 2
        let row = (point.y / halfHeight - point.x / halfWidth) / 2
        return FarmTile(column: Int(column.rounded()), row: Int(row.rounded()))
    }
}
