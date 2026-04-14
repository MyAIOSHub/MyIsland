import XCTest
@testable import My_Island

final class MeetingSkillCatalogTests: XCTestCase {
    func testParseAwesomeIndexExtractsCategoryAndRepoMetadata() {
        let markdown = """
        ## Personas
        - [Elon Musk Skill](https://github.com/alchaincyf/elon-musk-skill) - First principles and manufacturing rigor.
        ## Strategy
        - [Business Planner](https://github.com/example/business-plan-skill) - Business planning and go-to-market.
        """

        let entries = MeetingSkillCatalogService.parseCatalogEntries(
            markdown: markdown,
            sourceIndexURL: "https://example.com/index"
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].category, "Personas")
        XCTAssertEqual(entries[0].title, "Elon Musk Skill")
        XCTAssertEqual(entries[0].repoFullName, "alchaincyf/elon-musk-skill")
        XCTAssertEqual(entries[1].category, "Strategy")
        XCTAssertEqual(entries[1].repoFullName, "example/business-plan-skill")
        XCTAssertTrue(entries.allSatisfy(\.isInstallable))
    }

    func testParseAwesomeIndexSkipsMalformedAndUnsupportedEntries() {
        let markdown = """
        ## Mixed
        - [Valid](https://github.com/example/valid-skill) - usable entry.
        - [Website](https://example.com/not-github) - should be ignored.
        - invalid line without markdown shape
        """

        let entries = MeetingSkillCatalogService.parseCatalogEntries(
            markdown: markdown,
            sourceIndexURL: "https://example.com/index"
        )

        XCTAssertEqual(entries.map(\.repoFullName), ["example/valid-skill"])
    }
}
