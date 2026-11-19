import XCTest
@testable import Orchard

final class CatalogueSearchTests: XCTestCase {
    private let pink = TestFixtures.entry(id: "pink-lady", name: "Pink Lady", aliases: ["Cripps Pink"], plu: ["4130"])
    private let granny = TestFixtures.entry(id: "granny-smith", name: "Granny Smith", plu: ["4017"])
    private let fuji = TestFixtures.entry(id: "fuji", name: "Fuji", plu: ["4131"])
    private let pear = TestFixtures.entry(id: "packham", name: "Packham's Triumph", category: "pear")
    private let cosmic = TestFixtures.entry(id: "cosmic-crisp", name: "Cosmic Crisp")

    private var varieties: [CatalogueEntry] { [pink, granny, fuji, pear, cosmic] }

    func testEmptyQueryShowsTastedFruitHighestFirst() {
        let latest = [
            "pink-lady": TestFixtures.snapshot(4.5, notes: "Great crunch"),
            "granny-smith": TestFixtures.snapshot(2, notes: "Too sour"),
            "fuji": TestFixtures.snapshot(4, notes: "Honey sweet")
        ]
        let results = CatalogueSearch.shopResults(query: "", varieties: varieties, latestByVariety: latest)
        XCTAssertEqual(results.tried.map(\.variety.id), ["pink-lady", "fuji", "granny-smith"])
        XCTAssertTrue(results.untried.isEmpty)
    }

    func testTypedQueryIncludesUntastedMatches() {
        let latest = ["pink-lady": TestFixtures.snapshot(4.5)]
        let results = CatalogueSearch.shopResults(query: "app", varieties: varieties, latestByVariety: latest)
        XCTAssertEqual(results.tried.map(\.variety.id), ["pink-lady"])
        XCTAssertEqual(results.untried.map(\.variety.id), ["cosmic-crisp", "fuji", "granny-smith"])
        XCTAssertFalse(results.untried.contains { $0.variety.id == "packham" })
    }

    func testAliasAndPLUSearch() {
        let results = CatalogueSearch.shopResults(query: "cripps", varieties: varieties, latestByVariety: [:])
        XCTAssertEqual(results.untried.map(\.variety.id), ["pink-lady"])

        let byCode = CatalogueSearch.shopResults(query: "4130", varieties: varieties, latestByVariety: [:])
        XCTAssertEqual(byCode.untried.map(\.variety.id), ["pink-lady"])
    }

    func testShortDigitQueryDoesNotMatchEveryPLU() {
        XCTAssertFalse(CatalogueSearch.matches(pink, query: "4"))
        XCTAssertTrue(CatalogueSearch.matches(pink, query: "413"))
    }

    func testAccentInsensitiveName() {
        let bosc = TestFixtures.entry(id: "bosc", name: "Beurré Bosc", category: "pear")
        XCTAssertTrue(CatalogueSearch.matches(bosc, query: "beurre"))
    }

    func testGlanceUsesTheNoteThenTheSliders() {
        XCTAssertEqual(
            TraitSummary.glance(notes: "Great crunch, buy again", sweet: 1, tart: 1, crunch: 1, juicy: 1),
            "Great crunch, buy again"
        )
        XCTAssertEqual(
            TraitSummary.glance(notes: "   ", sweet: 4.5, tart: 1, crunch: 5, juicy: 2),
            "Crunchy and Sweet"
        )
        XCTAssertEqual(
            TraitSummary.glance(notes: "", sweet: 1, tart: 1, crunch: 1, juicy: 1),
            "No note yet"
        )
    }
}
