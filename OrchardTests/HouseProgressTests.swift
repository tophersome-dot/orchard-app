import XCTest
@testable import Orchard

final class HouseProgressTests: XCTestCase {
    func testThresholdsStayOrderedFromAShed() {
        let minimums = HouseRules.thresholds.map(\.minimum)
        XCTAssertEqual(minimums, minimums.sorted())
        XCTAssertEqual(Set(minimums).count, minimums.count)
        XCTAssertEqual(minimums.first, 0)
        XCTAssertEqual(HouseRules.thresholds.map(\.tier), HouseTier.allCases)
    }

    func testTiersFollowTheTunableThresholds() {
        XCTAssertEqual(HouseRules.progress(for: 0).tier, .shed)
        XCTAssertEqual(HouseRules.progress(for: 2).tier, .shed)
        XCTAssertEqual(HouseRules.progress(for: 2).varietiesToNext, 1)
        XCTAssertEqual(HouseRules.progress(for: 3).tier, .cottage)
        XCTAssertEqual(HouseRules.progress(for: 7).tier, .cottage)
        XCTAssertEqual(HouseRules.progress(for: 8).tier, .farmhouse)
        XCTAssertEqual(HouseRules.progress(for: 14).tier, .farmhouse)
        XCTAssertEqual(HouseRules.progress(for: 15).tier, .homestead)
        XCTAssertNil(HouseRules.progress(for: 15).varietiesToNext)
        XCTAssertEqual(HouseRules.progress(for: 40).tier, .homestead)
    }

    func testFractionResetsAtEachUpgrade() {
        XCTAssertEqual(HouseRules.progress(for: 0).fraction, 0, accuracy: 0.001)
        XCTAssertEqual(HouseRules.progress(for: 3).fraction, 0, accuracy: 0.001)
        XCTAssertEqual(HouseRules.progress(for: 4).fraction, 0.2, accuracy: 0.001)
        XCTAssertEqual(HouseRules.progress(for: 15).fraction, 1, accuracy: 0.001)
        XCTAssertEqual(HouseRules.progress(for: -3).tier, .shed)
    }
}
