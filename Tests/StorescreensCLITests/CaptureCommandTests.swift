import XCTest
@testable import storescreens_cli

final class CaptureCommandTests: XCTestCase {
    func testCaptureFlagsSurviveTheSharedOrchestratorRewrite() throws {
        let command = try CaptureCommand.parse(["--locale", "el", "--appearance", "dark", "--only", "Home,Search", "--xcresult", "--no-parallel"])
        XCTAssertEqual(command.locale, ["el"])
        XCTAssertEqual(command.appearance, ["dark"])
        XCTAssertEqual(command.only, "Home,Search")
        XCTAssertTrue(command.xcresult)
        XCTAssertTrue(command.noParallel)
    }

    func testInvalidRetriesAreRejectedBeforeStartingXcode() {
        XCTAssertThrowsError(try CaptureCommand.parse(["--retries", "-1"]))
    }

    func testGeneratedHarnessSupportsFilesystemAndAttachmentCollection() throws {
        let source = try SetupCommand().generateTestFile(screenNames: ["Home", "Quoted \"screen\""])
        XCTAssertTrue(source.contains("screenshot.pngRepresentation.write"))
        XCTAssertTrue(source.contains("XCTAttachment(screenshot:"))
        XCTAssertTrue(source.contains("harness.json"))
        XCTAssertTrue(source.contains("takeScreenshot(named: \"Home\")"))
        XCTAssertFalse(source.contains("{{SCREENSHOT_CALLS}}"))
        XCTAssertTrue(source.contains("Quoted\\\"screen\\\""))
    }
}
