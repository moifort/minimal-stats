import XCTest
@testable import Stats

final class ChangelogBlockTests: XCTestCase {

    func testParsesTheChangelogAssembledByTheUpdater() {
        let changelog = """
        ## v1.10.0

        ## Fixes
        - **Per-process CPU** is now measured
          like Activity Monitor.

        ## Internals
        - New test target.

        ---

        ## v1.11.0

        - CPU and Memory tabs now list applications.
        """
        XCTAssertEqual(ChangelogBlock.parse(changelog), [
            .heading(level: 2, text: "v1.10.0"),
            .heading(level: 2, text: "Fixes"),
            .bullet(indent: 0, marker: "•", text: "**Per-process CPU** is now measured like Activity Monitor."),
            .heading(level: 2, text: "Internals"),
            .bullet(indent: 0, marker: "•", text: "New test target."),
            .separator,
            .heading(level: 2, text: "v1.11.0"),
            .bullet(indent: 0, marker: "•", text: "CPU and Memory tabs now list applications."),
        ])
    }

    func testParagraphAfterAListStaysAParagraph() {
        XCTAssertEqual(ChangelogBlock.parse("- one\n- two\n\nThanks to\neveryone."), [
            .bullet(indent: 0, marker: "•", text: "one"),
            .bullet(indent: 0, marker: "•", text: "two"),
            .paragraph("Thanks to everyone."),
        ])
    }

    func testNestedAndNumberedItems() {
        XCTAssertEqual(ChangelogBlock.parse("1. First\n  * nested\n2) Second\r\n+ plus"), [
            .bullet(indent: 0, marker: "1.", text: "First"),
            .bullet(indent: 1, marker: "•", text: "nested"),
            .bullet(indent: 0, marker: "2.", text: "Second"),
            .bullet(indent: 0, marker: "•", text: "plus"),
        ])
    }

    func testSeparatorsAndHeadingVariants() {
        XCTAssertEqual(ChangelogBlock.parse("***\n_ _ _\n# Title #\n### Small\n#NoSpace\n--"), [
            .separator,
            .separator,
            .heading(level: 1, text: "Title"),
            .heading(level: 3, text: "Small"),
            .paragraph("#NoSpace --"),
        ])
    }

    func testEmptyChangelogHasNoBlocks() {
        XCTAssertEqual(ChangelogBlock.parse(""), [])
        XCTAssertEqual(ChangelogBlock.parse("\n\n"), [])
    }
}
