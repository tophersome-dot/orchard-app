import XCTest
@testable import Orchard

final class WoodlandTests: XCTestCase {
    private let clearing = FarmExpansion.clearingTiles(for: FarmExpansion.plan(treeCount: 0, bedCount: 0, vineCount: 0))

    func testLevelOneIslandIsLargerAndStillGrows() {
        XCTAssertEqual(Woodland.radius(level: 1), 22, accuracy: 0.001)
        XCTAssertEqual(Woodland.radius(level: 2) - Woodland.radius(level: 1), Woodland.radiusGrowth, accuracy: 0.001)
        XCTAssertEqual(Woodland.level(tastedCount: 0), 1)
        let start = Woodland.make(seed: 11, level: 1, clearing: clearing, blocked: [], woods: true)
        let grown = Woodland.make(seed: 11, level: 6, clearing: clearing, blocked: [], woods: true)
        XCTAssertTrue(clearing.isSubset(of: start.ground))
        XCTAssertTrue(start.ground.isSubset(of: grown.ground.union(grown.water)))
        XCTAssertGreaterThan(start.ground.count, clearing.count + 400)
    }

    func testCoastHasNoSpikesOrNotches() {
        let chart = Woodland.make(seed: 42, level: 1, clearing: clearing, blocked: [], woods: false)
        let land = chart.ground.union(chart.water)
        let protected = clearing
        for tile in land where !protected.contains(tile) {
            let neighbors = Woodland.orthogonal(tile).filter { land.contains($0) }.count
            XCTAssertGreaterThanOrEqual(neighbors, 2)
        }
    }

    func testLakesAndCreekStayOffTheFarm() {
        let chart = Woodland.make(seed: 7, level: 1, clearing: clearing, blocked: [], woods: false)
        XCTAssertFalse(chart.lakes.isEmpty)
        XCTAssertTrue((3...8).contains(chart.lakes.count) || chart.lakes.count <= 16)
        XCTAssertTrue(chart.lakes.isDisjoint(with: clearing))
        XCTAssertTrue(chart.creek.isDisjoint(with: clearing))
        XCTAssertTrue(chart.creek.isDisjoint(with: chart.lakes))
        if let mouth = chart.creek.first(where: { tile in
            Woodland.orthogonal(tile).contains { !chart.ground.contains($0) && !chart.water.contains($0) }
        }) {
            XCTAssertTrue(chart.creek.contains(mouth))
        } else {
            XCTFail("The creek should reach the coast")
        }
    }

    func testWoodsAreGrovesNotASolidWall() {
        let blocked = Woodland.blockedTiles(records: FarmExpansion.starterRecords(), plan: FarmExpansion.plan(treeCount: 0, bedCount: 0, vineCount: 0))
        let chart = Woodland.make(seed: 19, level: 1, clearing: clearing, blocked: blocked, woods: true)
        let outside = chart.ground.subtracting(clearing).count
        let tall = chart.decor.filter { Woodland.sprite($0.sprite)?.isTall == true }.count
        let low = chart.decor.filter { Woodland.sprite($0.sprite)?.isTall == false }.count
        XCTAssertGreaterThan(chart.glades.count, 40)
        XCTAssertGreaterThan(chart.groves.count, 40)
        XCTAssertLessThan(chart.decor.count, outside / 2)
        XCTAssertLessThan(tall, low)
        XCTAssertFalse(chart.tints.isEmpty)
        for decor in chart.decor {
            XCTAssertGreaterThanOrEqual(decor.scale, 0.85)
            XCTAssertLessThanOrEqual(decor.scale, 1.15)
        }
    }

    func testClearedCellIsUsedBeforeTheGridGrows() {
        let starter = FarmExpansion.starterRecords()
        let open = FarmTile(column: 18, row: 4)
        let placed = FarmExpansion.reconciled(
            starter,
            tried: [(id: "pink-lady", zone: "orchard")],
            tastedCount: 1,
            openTiles: [open]
        )
        XCTAssertEqual(placed.first { $0.kind == .plant }?.tile, open)
    }

    func testBridgeFollowsTheCrossing() {
        let creek = FarmTile(column: 4, row: 4)
        let paths: Set<FarmTile> = [
            FarmTile(column: 3, row: 4),
            creek,
            FarmTile(column: 5, row: 4)
        ]
        XCTAssertEqual(Woodland.bridge(at: creek, creek: [creek], paths: paths), .eastWest)
        let northPaths: Set<FarmTile> = [
            FarmTile(column: 4, row: 3),
            creek,
            FarmTile(column: 4, row: 5)
        ]
        XCTAssertEqual(Woodland.bridge(at: creek, creek: [creek], paths: northPaths), .northSouth)
        XCTAssertNil(Woodland.bridge(at: creek, creek: [], paths: paths))
    }
}
