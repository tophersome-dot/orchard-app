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

    static var halfWidth: CGFloat { tileWidth / 2 }
    static var halfHeight: CGFloat { tileHeight / 2 }

    /// Diamond corners around a tile centre, clockwise from the top.
    static func corners(_ tile: FarmTile) -> [CGPoint] {
        let center = center(tile)
        return [
            CGPoint(x: center.x, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y),
            CGPoint(x: center.x, y: center.y + halfHeight),
            CGPoint(x: center.x - halfWidth, y: center.y)
        ]
    }
}

/// One grid edge. `anchor` is the on-screen lower post; the rail runs up to `end`.
struct FarmGridEdge: Hashable {
    var anchor: CGPoint
    var end: CGPoint
    /// True when the rail runs up-right (column boundary). False runs up-left (row boundary).
    var runsNorthEast: Bool
    var groundY: CGFloat { (anchor.y + end.y) / 2 }
}

enum FarmSurface {
    /// The outer edge of each fence tile, chosen so a rectangular run shares posts.
    static func fenceEdges(in records: [FarmRecord]) -> [FarmGridEdge] {
        let fences = records.filter { $0.kind == .fence }
        guard !fences.isEmpty else { return [] }
        let centroid = average(fences.map { IsoMap.center($0.tile) })
        var seen = Set<EdgeKey>()
        var edges: [FarmGridEdge] = []
        for fence in fences {
            let alongColumn = fence.varietyID == FarmSprite.fenceSide
            let choices = candidateEdges(tile: fence.tile, alongColumn: alongColumn)
            guard let picked = choices.max(by: { distance(midpoint($0), centroid) < distance(midpoint($1), centroid) }) else {
                continue
            }
            guard seen.insert(EdgeKey(picked)).inserted else { continue }
            edges.append(picked)
        }
        return edges
    }

    static func fencePosts(on edges: [FarmGridEdge]) -> [CGPoint] {
        var seen = Set<VertexKey>()
        var posts: [CGPoint] = []
        for edge in edges {
            for point in [edge.anchor, edge.end] where seen.insert(VertexKey(point)).inserted {
                posts.append(point)
            }
        }
        return posts
    }

    /// Edges of these cells whose neighbour is not in the set.
    static func boundaryEdges(of tiles: Set<FarmTile>) -> [(edge: FarmGridEdge, outwardFrom: FarmTile)] {
        var result: [(edge: FarmGridEdge, outwardFrom: FarmTile)] = []
        for tile in tiles {
            let pairs: [(FarmTile, FarmGridEdge)] = [
                (FarmTile(column: tile.column + 1, row: tile.row), eastEdge(tile)),
                (FarmTile(column: tile.column - 1, row: tile.row), westEdge(tile)),
                (FarmTile(column: tile.column, row: tile.row + 1), southEdge(tile)),
                (FarmTile(column: tile.column, row: tile.row - 1), northEdge(tile))
            ]
            for (neighbor, edge) in pairs where !tiles.contains(neighbor) {
                result.append((edge, tile))
            }
        }
        return result
    }

    private static func candidateEdges(tile: FarmTile, alongColumn: Bool) -> [FarmGridEdge] {
        if alongColumn {
            return [eastEdge(tile), westEdge(tile)]
        }
        return [northEdge(tile), southEdge(tile)]
    }

    private static func eastEdge(_ tile: FarmTile) -> FarmGridEdge {
        let corners = IsoMap.corners(tile)
        return FarmGridEdge(anchor: corners[2], end: corners[1], runsNorthEast: true)
    }

    private static func westEdge(_ tile: FarmTile) -> FarmGridEdge {
        let corners = IsoMap.corners(tile)
        return FarmGridEdge(anchor: corners[3], end: corners[0], runsNorthEast: true)
    }

    private static func northEdge(_ tile: FarmTile) -> FarmGridEdge {
        let corners = IsoMap.corners(tile)
        return FarmGridEdge(anchor: corners[1], end: corners[0], runsNorthEast: false)
    }

    private static func southEdge(_ tile: FarmTile) -> FarmGridEdge {
        let corners = IsoMap.corners(tile)
        return FarmGridEdge(anchor: corners[2], end: corners[3], runsNorthEast: false)
    }

    private static func midpoint(_ edge: FarmGridEdge) -> CGPoint {
        CGPoint(x: (edge.anchor.x + edge.end.x) / 2, y: (edge.anchor.y + edge.end.y) / 2)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func average(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        return CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }
}

private struct EdgeKey: Hashable {
    var ax: Int
    var ay: Int
    var bx: Int
    var by: Int

    init(_ edge: FarmGridEdge) {
        let a = VertexKey(edge.anchor)
        let b = VertexKey(edge.end)
        ax = a.x
        ay = a.y
        bx = b.x
        by = b.y
    }
}

private struct VertexKey: Hashable {
    var x: Int
    var y: Int

    init(_ point: CGPoint) {
        x = Int((point.x * 10).rounded())
        y = Int((point.y * 10).rounded())
    }
}
