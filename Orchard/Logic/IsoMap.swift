import CoreGraphics
import Foundation

struct FarmTile: Hashable, Equatable, Sendable {
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

/// Rounds a closed cell outline so a staircase of tile corners becomes a soft coast.
enum ShoreOutline {
    /// Cuts each sharp corner by about half an edge, twice, then eases the chamfer.
    static func round(_ points: [CGPoint]) -> [CGPoint] {
        let first = chopCorners(points, fraction: 0.46)
        let second = chopCorners(first, fraction: 0.32)
        return chaikin(second, passes: 2, weight: 0.25)
    }

    /// Pushes the outline outward by a low-frequency wave, about 0.3–0.8 tiles.
    /// The shift is always away from the loop's centre, so the land cells stay inside.
    static func wobble(_ points: [CGPoint], seed: UInt64, minTiles: CGFloat = 0.3, maxTiles: CGFloat = 0.8) -> [CGPoint] {
        let sampled = sample(points, spacing: 16)
        guard sampled.count >= 3 else { return points }
        let count = CGFloat(sampled.count)
        let middle = CGPoint(
            x: sampled.reduce(CGFloat(0)) { $0 + $1.x } / count,
            y: sampled.reduce(CGFloat(0)) { $0 + $1.y } / count
        )
        let tile = hypot(IsoMap.tileWidth / 2, IsoMap.tileHeight / 2)
        var pushed: [CGPoint] = []
        pushed.reserveCapacity(sampled.count)
        for (index, point) in sampled.enumerated() {
            let previous = sampled[(index + sampled.count - 1) % sampled.count]
            let following = sampled[(index + 1) % sampled.count]
            let dx = following.x - previous.x
            let dy = following.y - previous.y
            let length = max(hypot(dx, dy), 0.001)
            var outward = CGPoint(x: dy / length, y: -dx / length)
            let away = CGPoint(x: point.x - middle.x, y: point.y - middle.y)
            if outward.x * away.x + outward.y * away.y < 0 {
                outward = CGPoint(x: -outward.x, y: -outward.y)
            }
            let turn = Double(index) / Double(sampled.count)
            let slow = sin(turn * .pi * 2 * 4 + Double(seed % 997) * 0.01)
            let slower = sin(turn * .pi * 2 * 7 + Double((seed / 13) % 991) * 0.017)
            let unit = min(1, max(0, 0.5 + 0.34 * slow + 0.16 * slower))
            let distance = (minTiles + (maxTiles - minTiles) * CGFloat(unit)) * tile
            pushed.append(CGPoint(x: point.x + outward.x * distance, y: point.y + outward.y * distance))
        }
        return chaikin(pushed, passes: 1, weight: 0.25)
    }

    /// Fewer points, for a continuous stroke. The clip path keeps the full rounded loop.
    static func sample(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard points.count >= 3, spacing > 1 else { return points }
        var result: [CGPoint] = [points[0]]
        var travelled: CGFloat = 0
        var nextMark = spacing
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let length = hypot(end.x - start.x, end.y - start.y)
            if length < 0.01 { continue }
            while nextMark <= travelled + length {
                let t = (nextMark - travelled) / length
                result.append(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                nextMark += spacing
            }
            travelled += length
        }
        return result.count >= 3 ? result : points
    }

    private static func chopCorners(_ points: [CGPoint], fraction: CGFloat) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        let cut = min(max(fraction, 0.05), 0.49)
        var next: [CGPoint] = []
        next.reserveCapacity(points.count * 2)
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let following = points[(index + 1) % points.count]
            let inX = current.x - previous.x
            let inY = current.y - previous.y
            let outX = following.x - current.x
            let outY = following.y - current.y
            let inLen = max(hypot(inX, inY), 0.001)
            let outLen = max(hypot(outX, outY), 0.001)
            let dot = (inX / inLen) * (outX / outLen) + (inY / inLen) * (outY / outLen)
            if dot > 0.94 {
                next.append(current)
                continue
            }
            let takeIn = inLen * cut
            let takeOut = outLen * cut
            next.append(CGPoint(x: current.x - (inX / inLen) * takeIn, y: current.y - (inY / inLen) * takeIn))
            next.append(CGPoint(x: current.x + (outX / outLen) * takeOut, y: current.y + (outY / outLen) * takeOut))
        }
        return next
    }

    private static func chaikin(_ points: [CGPoint], passes: Int, weight: CGFloat) -> [CGPoint] {
        var pts = points
        let keep = min(max(weight, 0.05), 0.45)
        let take = 1 - keep
        for _ in 0..<passes {
            guard pts.count >= 3 else { return pts }
            var next: [CGPoint] = []
            next.reserveCapacity(pts.count * 2)
            for index in pts.indices {
                let current = pts[index]
                let following = pts[(index + 1) % pts.count]
                next.append(CGPoint(x: current.x * take + following.x * keep, y: current.y * take + following.y * keep))
                next.append(CGPoint(x: current.x * keep + following.x * take, y: current.y * keep + following.y * take))
            }
            pts = next
        }
        return pts
    }
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
