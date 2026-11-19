import XCTest
@testable import Orchard

final class FarmExpansionTests: XCTestCase {
    func testStarterPlotIsOpenAndLaterPlotsWait() {
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 0).map(\.id), ["home"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 4).map(\.id), ["home", "east"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 8).map(\.id), ["home", "east", "south"])
        XCTAssertEqual(FarmExpansion.unlockedPlots(tastedCount: 12).map(\.id), ["home", "east", "south", "corner"])
        XCTAssertTrue(FarmExpansion.isLocked(FarmTile(column: 17, row: 2), tastedCount: 0))
        XCTAssertFalse(FarmExpansion.isLocked(FarmTile(column: 17, row: 2), tastedCount: 4))
    }

    func testAutoPlaceUsesTheNextFreeMatchingSpot() {
        let firstTree = FarmExpansion.nextFreeSpot(kind: .tree, tastedCount: 0, occupied: [])
        XCTAssertEqual(firstTree, FarmTile(column: 2, row: 2))
        let second = FarmExpansion.nextFreeSpot(kind: .tree, tastedCount: 0, occupied: [FarmTile(column: 2, row: 2)])
        XCTAssertEqual(second, FarmTile(column: 4, row: 2))
        XCTAssertEqual(
            FarmExpansion.nextFreeSpot(kind: .bed, tastedCount: 0, occupied: []),
            FarmTile(column: 2, row: 8)
        )
        XCTAssertEqual(
            FarmExpansion.nextFreeSpot(kind: .vine, tastedCount: 0, occupied: []),
            FarmTile(column: 2, row: 11)
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
        let bed = FarmTile(column: 2, row: 8)
        XCTAssertTrue(FarmExpansion.canPlace(kind: .plant, spot: .tree, on: tree, tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(kind: .plant, spot: .tree, on: bed, tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(kind: .plant, spot: .bed, on: tree, tastedCount: 0, occupied: []))
        XCTAssertTrue(FarmExpansion.canPlace(kind: .house, spot: nil, on: FarmTile(column: 17, row: 2), tastedCount: 0, occupied: []))
        XCTAssertFalse(FarmExpansion.canPlace(
            kind: .house,
            spot: nil,
            on: FarmTile(column: 17, row: 2),
            tastedCount: 0,
            occupied: [],
            water: [FarmTile(column: 17, row: 2)]
        ))
        XCTAssertTrue(FarmExpansion.canPlace(
            kind: .plant,
            spot: .tree,
            on: FarmTile(column: 20, row: 4),
            tastedCount: 0,
            occupied: [],
            openTiles: [FarmTile(column: 20, row: 4)]
        ))
        XCTAssertTrue(FarmExpansion.canPlace(kind: .fence, spot: nil, on: FarmTile(column: 0, row: 3), tastedCount: 0, occupied: []))
    }

    func testSpriteNames() {
        XCTAssertEqual(FarmSprite.house(.shed), "house_1_shed")
        XCTAssertEqual(FarmSprite.house(.homestead), "house_4_homestead")
        XCTAssertEqual(FarmSprite.tree(category: "apple", varietyID: "pink-lady"), "tree_apple_pink-lady")
        XCTAssertEqual(FarmSprite.crop(varietyID: "dutch-carrot"), "crop_dutch-carrot")
        XCTAssertEqual(FarmSprite.arbor(varietyID: "cherry-tomato"), "vine_cherry-tomato_arbor")
        XCTAssertEqual(
            FarmSprite.plantName(zone: "bed", category: "vegetable", varietyID: "dutch-carrot", rating: 4),
            "crop_dutch-carrot"
        )
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

    func testScatteredYardIsRebuiltIntoSections() {
        let records = [
            FarmRecord(id: UUID(), kind: .house, varietyID: nil, tile: FarmExpansion.legacyHouseTile),
            FarmRecord(id: UUID(), kind: .tractor, varietyID: nil, tile: FarmTile(column: 9, row: 0)),
            FarmRecord(id: UUID(), kind: .plant, varietyID: "pink-lady", tile: FarmTile(column: 3, row: 3))
        ]
        let fixed = FarmExpansion.reconciled(records, tried: [(id: "pink-lady", zone: "orchard")], tastedCount: 1)
        XCTAssertEqual(fixed.first { $0.kind == .house }?.tile, FarmExpansion.houseAnchor)
        XCTAssertEqual(fixed.first { $0.kind == .tractor }?.tile, FarmExpansion.tractorTile)
        XCTAssertEqual(fixed.first { $0.kind == .plant }?.tile, FarmTile(column: 2, row: 2))
        let fence = fixed.filter { $0.kind == .fence }.map(\.tile)
        XCTAssertFalse(fence.contains(FarmTile(column: 4, row: 6)), "The front fence keeps a gate opening")
        XCTAssertTrue(fence.contains(FarmTile(column: 0, row: 0)))
        XCTAssertTrue(fence.contains(FarmTile(column: 8, row: 6)))
        let footprint = Set(FarmExpansion.footprint(kind: .house, anchor: FarmExpansion.houseAnchor))
        XCTAssertFalse(footprint.contains(FarmExpansion.tractorTile))
        XCTAssertTrue(fixed.contains { $0.kind == .fence && $0.varietyID == FarmSprite.fenceSide })
    }

    func testOrchardAndBedsGrowToFitEveryPlant() {
        let trees = (0..<30).map { (id: "tree-\($0)", zone: "orchard") }
        let planted = FarmExpansion.reconciled([], tried: trees, tastedCount: 30)
        let treeTiles = planted.filter { $0.kind == .plant }.map(\.tile)
        XCTAssertEqual(treeTiles.count, 30)
        let columns = Set(planted.filter { $0.kind == .fence }.map(\.tile.column))
        let left = columns.min() ?? 0
        let right = columns.max() ?? 0
        for tile in treeTiles {
            XCTAssertGreaterThan(tile.column, left)
            XCTAssertLessThan(tile.column, right)
        }
        XCTAssertTrue(treeTiles.contains(FarmTile(column: 2, row: 2)))
        XCTAssertTrue(treeTiles.contains(FarmTile(column: 6, row: 20)))

        let beds = (0..<5).map { (id: "bed-\($0)", zone: "bed") }
        let bedTiles = FarmExpansion.reconciled([], tried: beds, tastedCount: 5).filter { $0.kind == .plant }.map(\.tile)
        XCTAssertEqual(bedTiles.count, 5)
        XCTAssertTrue(planted.contains { $0.kind == .tractor && $0.tile == FarmExpansion.tractorTile })
    }

    func testOrchardFenceSharesPostsAndKeepsOneGate() {
        let pieces = FarmSurface.fenceEdges(in: FarmExpansion.starterRecords())
        let posts = FarmSurface.fencePosts(on: pieces)
        XCTAssertEqual(pieces.count, 31)
        XCTAssertEqual(posts.count, 32)
        let gate = FarmGridEdge(
            anchor: IsoMap.corners(FarmTile(column: 4, row: 6))[2],
            end: IsoMap.corners(FarmTile(column: 4, row: 6))[3],
            runsNorthEast: false
        )
        XCTAssertFalse(pieces.contains(gate))
    }

    func testIsoCenterRoundTrips() {
        let tile = FarmTile(column: 7, row: 2)
        XCTAssertEqual(IsoMap.tile(at: IsoMap.center(tile)), tile)
        XCTAssertEqual(IsoMap.tile(at: IsoMap.center(FarmTile(column: 11, row: 14))), FarmTile(column: 11, row: 14))
    }
}
