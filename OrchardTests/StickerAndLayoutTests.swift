import XCTest
@testable import Orchard

final class StickerMatchTests: XCTestCase {
    private let varieties = [
        TestFixtures.entry(id: "pink-lady", name: "Pink Lady", aliases: ["Cripps Pink"], plu: ["4130"]),
        TestFixtures.entry(id: "granny-smith", name: "Granny Smith", plu: ["4017"]),
        TestFixtures.entry(id: "fuji", name: "Fuji", plu: ["4131"]),
        TestFixtures.entry(id: "eve", name: "Eve")
    ]

    func testNameOnTheLabelWins() {
        let match = StickerMatch.suggest(text: "PINK LADY\nProduct of Australia", varieties: varieties)
        XCTAssertEqual(match?.varietyID, "pink-lady")
        XCTAssertEqual(match?.reason, "Name on the label")
    }

    func testAliasMatches() {
        XCTAssertEqual(StickerMatch.suggest(text: "Cripps Pink", varieties: varieties)?.varietyID, "pink-lady")
    }

    func testPLUAndOrganicPrefix() {
        XCTAssertEqual(StickerMatch.suggest(text: "4017", varieties: varieties)?.varietyID, "granny-smith")
        XCTAssertEqual(StickerMatch.suggest(text: "PLU 94017", varieties: varieties)?.varietyID, "granny-smith")
    }

    func testPrintedNameBeatsADisagreeingPLU() {
        let match = StickerMatch.suggest(text: "FUJI\n4017", varieties: varieties)
        XCTAssertEqual(match?.varietyID, "fuji")
    }

    func testShortNameNeedsAWholeWord() {
        XCTAssertEqual(StickerMatch.suggest(text: "Try Eve today", varieties: varieties)?.varietyID, "eve")
        XCTAssertNil(StickerMatch.suggest(text: "evening market", varieties: varieties))
    }

    func testUnknownLabelReturnsNil() {
        XCTAssertNil(StickerMatch.suggest(text: "Coles banana", varieties: varieties))
    }
}

final class PlotLayoutTests: XCTestCase {
    func testSlotsStayOnTheCanvas() {
        let orchard = (0..<9).map { "tree-\($0)" }
        let layout = PlotLayout.make(
            orchard: orchard,
            beds: ["carrot-a", "carrot-b", "carrot-c"],
            trellis: ["tomato", "grape"],
            lab: ["candy"]
        )
        XCTAssertEqual(layout.slots.count, 9 + 3 + 2 + 1)
        for point in layout.slots.values {
            XCTAssertGreaterThan(point.x, 40)
            XCTAssertLessThan(point.x, layout.canvas.width - 40)
            XCTAssertGreaterThan(point.y, 40)
            XCTAssertLessThan(point.y, layout.canvas.height - 20)
        }
        XCTAssertLessThan(layout.house.y, layout.sign.y)
        XCTAssertLessThan(layout.sign.y, layout.greenhouse.y)
    }
}
