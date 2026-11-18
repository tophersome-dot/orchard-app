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
}
