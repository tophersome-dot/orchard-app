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

    func testEmptyProfileIsThePrior() {
        let profile = TasteScore.profile(samples: [])
        XCTAssertEqual(profile.sweet, 3.5)
        XCTAssertEqual(profile.tart, 2.5)
        XCTAssertEqual(profile.crunch, 4)
        XCTAssertEqual(profile.juicy, 4)
    }

    func testLikedOverridesMoveTheProfileAndThePriorIsWorthThreeFours() {
        let liked = TasteSample(sweet: 5, tart: 2, crunch: 4, juicy: 4, overall: 4, overallIsOverride: true)
        let once = TasteScore.profile(samples: [liked])
        XCTAssertEqual(once.sweet, 3.875, accuracy: 0.001)
        XCTAssertEqual(once.tart, 2.375, accuracy: 0.001)
        let thrice = TasteScore.profile(samples: [liked, liked, liked])
        XCTAssertEqual(thrice.sweet, 4.25, accuracy: 0.001)
        XCTAssertEqual(thrice.tart, 2.25, accuracy: 0.001)
    }

    func testAutoScoresAndLowRatingsDoNotTeachTheProfile() {
        let prior = TasteScore.profile(samples: [])
        let ignored = [
            TasteSample(sweet: 0, tart: 0, crunch: 0, juicy: 0, overall: 5, overallIsOverride: false),
            TasteSample(sweet: 1, tart: 5, crunch: 1, juicy: 1, overall: 2, overallIsOverride: true),
            TasteSample(sweet: 1, tart: 5, crunch: 1, juicy: 1, overall: 2.5, overallIsOverride: true)
        ]
        let profile = TasteScore.profile(samples: ignored)
        XCTAssertEqual(profile, prior)
    }

    func testAutomaticOverallIsAMatchNotAnAverage() {
        let prior = TasteProfile.prior
        XCTAssertEqual(
            TasteScore.automatic(sweet: 3.5, tart: 2.5, crunch: 4, juicy: 4, profile: prior),
            5
        )
        XCTAssertEqual(
            TasteScore.automatic(sweet: 5, tart: 5, crunch: 4, juicy: 4, profile: prior),
            3.5
        )
        XCTAssertEqual(
            TasteScore.automatic(sweet: 0, tart: 5, crunch: 0, juicy: 0, profile: prior),
            1.5
        )
        let opposite = TasteProfile(sweet: 0, tart: 0, crunch: 0, juicy: 0)
        XCTAssertEqual(
            TasteScore.automatic(sweet: 5, tart: 5, crunch: 5, juicy: 5, profile: opposite),
            1
        )
    }

    func testHintNamesTheBiggestGap() {
        let prior = TasteProfile.prior
        XCTAssertEqual(
            TasteScore.hint(sweet: 3.5, tart: 2.5, crunch: 4, juicy: 4, profile: prior),
            "Auto: close to your taste"
        )
        XCTAssertEqual(
            TasteScore.hint(sweet: 3.5, tart: 5, crunch: 4, juicy: 4, profile: prior),
            "Auto: tarter than you usually like"
        )
        XCTAssertEqual(
            TasteScore.hint(sweet: 0, tart: 2.5, crunch: 4, juicy: 4, profile: prior),
            "Auto: less sweet than you usually like"
        )
        XCTAssertEqual(
            TasteScore.hint(sweet: 3.5, tart: 2.5, crunch: 0, juicy: 4, profile: prior),
            "Auto: softer than you usually like"
        )
    }
}
