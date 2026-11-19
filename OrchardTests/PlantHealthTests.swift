import XCTest
@testable import Orchard

final class PlantHealthTests: XCTestCase {
    func testLovedFruitIsLushAndLarger() {
        let health = PlantHealth.from(rating: 4.5)
        XCTAssertEqual(health.condition, .lush)
        XCTAssertEqual(health.badge, .loved)
        XCTAssertGreaterThan(health.scale, 1)
        XCTAssertEqual(health.wilt, 0)
    }

    func testBoundaryAtFourIsLoved() {
        XCTAssertEqual(PlantHealth.from(rating: 4).condition, .lush)
        XCTAssertEqual(PlantHealth.from(rating: 3.99).condition, .ordinary)
        XCTAssertEqual(PlantHealth.from(rating: 3.99).badge, .mixed)
    }

    func testMiddlingStaysOrdinary() {
        let health = PlantHealth.from(rating: 3)
        XCTAssertEqual(health.condition, .ordinary)
        XCTAssertEqual(health.badge, .mixed)
        XCTAssertLessThan(health.scale, PlantHealth.from(rating: 5).scale)
    }

    func testLowScoresWilt() {
        XCTAssertEqual(PlantHealth.from(rating: 2.5).condition, .ordinary)
        let wilted = PlantHealth.from(rating: 2.49)
        XCTAssertEqual(wilted.condition, .wilted)
        XCTAssertEqual(wilted.badge, .disliked)
        XCTAssertGreaterThan(wilted.wilt, 0.4)
        XCTAssertLessThan(PlantHealth.from(rating: 1).scale, PlantHealth.from(rating: 2.5).scale)
    }

    func testRatingsOutsideTheScaleAreClamped() {
        XCTAssertEqual(PlantHealth.from(rating: 0).condition, PlantHealth.from(rating: 1).condition)
        XCTAssertEqual(PlantHealth.from(rating: 9).scale, PlantHealth.from(rating: 5).scale)
    }

    func testAutomaticOverallAveragesAllFourSlidersOntoHalfSteps() {
        XCTAssertEqual(TasteScore.automatic(sweet: 3, tart: 3, crunch: 3, juicy: 3), 3)
        XCTAssertEqual(TasteScore.automatic(sweet: 5, tart: 5, crunch: 5, juicy: 5), 5)
        XCTAssertEqual(TasteScore.automatic(sweet: 0, tart: 0, crunch: 0, juicy: 0), 1)
        XCTAssertEqual(TasteScore.automatic(sweet: 3.5, tart: 3.5, crunch: 3.5, juicy: 2.5), 3.5)
        XCTAssertEqual(TasteScore.automatic(sweet: 4, tart: 4, crunch: 4, juicy: 3), 4)
    }
}
