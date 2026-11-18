import XCTest
@testable import Orchard

final class FarmExpansionTests: XCTestCase {
    func testStarterPlotIsOpenAndLaterPlotsWait() {
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 0).map(\.id), ["home"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 4).map(\.id), ["home", "east"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 8).map(\.id), ["home", "east", "south"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 12).map(\.id), ["home", "east", "south", "corner"])
        XCTAssertTrue(FarmExpansion.isLocked(FarmTile(column: 11, row: 2), tastedCount: 0))
        XCTAssertFalse(FarmExpansion.isLocked(FarmTile(column: 11, row: 2), tastedCount: 4))
    }

    func testAutoPlaceUsesTheNextFreeMatchingSpot() {
        let firstTree = FarmExpansion.nextFreeSpot(kind: .tree, tastedCount: 0, occupied: [])
        XCTAssertEqual(firstTree, FarmTile(column: 2, row: 2))
        let second = FarmExpansion.nextFreeSpot(kind: .tree, tastedCount: 0, occupied: [FarmTile(column: 2, row: 2)])
        XCTAssertEqual(second, FarmTile(column: 4, row: 2))
        XCTAssertEqual(
            FarmExpansion.nextFreeSpot(kind: .bed, tastedCount: 0, occupied: []),
            FarmTile(column: 6, row: 5)
        )
        XCTAssertEqual(
            FarmExpansion.nextFreeSpot(kind: .vine, tastedCount: 0, occupied: []),
            FarmTile(column: 2, row: 6)
        )
        XCTAssertNil(FarmExpansion.nextFreeSpot(kind: .tree, tastedCount: 0, occupied: Set(FarmExpansion.spots(kind: .tree, tastedCount: 0))))
    }

    func testReconcilePlacesATastedAppleAndDropsUntastedPlants() {
        let starter = FarmExpansion.starterRecords()
        let placed = FarmExpansion.reconciled(starter, tried: [(id: "pink-lady", zone: "orchard")], tastedCount: 1)
        let plant = placed.first { $0.kind == .plant }
        XCTAssertEqual(plant?.varietyID, "pink-lady")
        XCTAssertEqual(plant?.tile, FarmTile(column: 2, row: 2))

        let removed = FarmExpansion.reconciled(placed, tried: [], tastedCount: 0)
        XCTAssertFalse(removed.contains { $0.kind == .plant })
        XCTAssertTrue(removed.contains { $0.kind == .house })
    }

    func testPlantsOnlySitOnTheirOwnSpots() {
        let tree = FarmTile(column: 2, row: 2)
        let bed = FarmTile(column: 6, row: 5)
        XCTAssertTrue(FarmExpansion.canPlace(kind: .plant, spot: .tree, on: tree, tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(kind: .plant, spot: .tree, on: bed, tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(kind: .plant, spot: .bed, on: tree, tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(kind: .house, spot: nil, on: FarmTile(column: 11, row: 2), tastedCount: 0, occupied: []))
        XCTAssertTrue(FarmExpansion.canPlace(kind: .fence, spot: nil, on: FarmTile(column: 0, row: 3), tastedCount: 0, occupied: []))
    }

    func testSpriteNames() {
        XCTAssertEqual(FarmSprite.house(.shed), "house_1_shed")
        XCTAssertEqual(FarmSprite.house(.homestead), "house_4_homestead")
        XCTAssertEqual(FarmSprite.tree(category: "apple", varietyID: "pink-lady"), "tree_apple_pink-lady")
        XCTAssertEqual(FarmSprite.bed(varietyID: "dutch-carrot"), "bed_dutch-carrot")
        XCTAssertEqual(FarmSprite.vine(varietyID: "cherry-tomato"), "vine_cherry-tomato")
        XCTAssertEqual(FarmSprite.fruit(varietyID: "fuji"), "fruit_fuji")
        XCTAssertEqual(
            FarmSprite.plantName(zone: "orchard", category: "apple", varietyID: "granny-smith", rating: 2),
            "tree_wilting"
        )
        XCTAssertEqual(
            FarmSprite.plantName(zone: "orchard", category: "apple", varietyID: "pink-lady", rating: 4.5),
            "tree_apple_pink-lady"
        )
        XCTAssertEqual(Double(FarmSprite.scale(for: 4.5)), 1.12, accuracy: 0.001)
        XCTAssertEqual(Double(FarmSprite.scale(for: 3)), 1, accuracy: 0.001)
    }

    func testLegacyTractorMovesOffTheHouse() {
        let records = [
            FarmRecord(id: UUID(), kind: .house, varietyID: nil, tile: FarmExpansion.houseAnchor),
            FarmRecord(id: UUID(), kind: .tractor, varietyID: nil, tile: FarmExpansion.legacyTractorTile)
        ]
        let fixed = FarmExpansion.reconciled(records, tried: [], tastedCount: 0)
        XCTAssertEqual(fixed.first { $0.kind == .tractor }?.tile, FarmExpansion.tractorTile)
        let footprint = Set(FarmExpansion.footprint(kind: .house, anchor: FarmExpansion.houseAnchor))
        XCTAssertFalse(footprint.contains(FarmExpansion.tractorTile))
    }

    func testIsoCenterRoundTrips() {
        let tile = FarmTile(column: 7, row: 2)
        XCTAssertEqual(IsoMap.tile(at: IsoMap.center(tile)), tile)
        XCTAssertEqual(IsoMap.tile(at: IsoMap.center(FarmTile(column: 11, row: 14))), FarmTile(column: 11, row: 14))
    }
}
