import XCTest
@testable import Orchard

final class CatalogueIntegrityTests: XCTestCase {
    func testBundledCatalogueIsConsistent() throws {
        let bundle = Bundle(for: CatalogueIntegrityTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "catalogue", withExtension: "json"))
        let document = try JSONDecoder().decode(CatalogueDocument.self, from: Data(contentsOf: url))
        let issues = CatalogueValidator.issues(in: document)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))

        let apples = document.varieties.filter { $0.category == "apple" }
        XCTAssertFalse(apples.isEmpty)
        // The collection denominator is this count. It is whatever the file contains, not a target of 30.
        XCTAssertEqual(
            apples.count,
            Set(apples.map(\.id)).count
        )
    }
}
