import XCTest
@testable import StorescreensCore

final class FailedCaptureTests: XCTestCase {
    private func result(_ exitCode: Int32, output: String = "") -> ProcessResult {
        ProcessResult(stdout: output, stderr: "", exitCode: exitCode)
    }

    func testFailedProcessIsRejectedEvenWhenResultsCannotBeRead() {
        XCTAssertThrowsError(try TestRunDiagnostics.requireSuccess(result(65), device: "sim", summary: nil)) {
            guard case CLIError.testFailed = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    func testRecordedAssertionFailureIsRejectedEvenWithSuccessfulExitStatus() {
        let summary = XCTestSummary(totalTests: 1, passedTests: 0, failedTests: 1, skippedTests: 0,
                                    failures: [.init(testName: "Screens/testHome", targetName: "Screens",
                                                     failureText: "Required button is missing")])
        XCTAssertThrowsError(try TestRunDiagnostics.requireSuccess(result(0), device: "sim", summary: summary)) {
            XCTAssertTrue($0.localizedDescription.contains("Required button is missing"))
        }
    }

    func testFailureDetailsCannotBeHiddenByAnInconsistentZeroFailureCount() {
        let summary = XCTestSummary(totalTests: 1, passedTests: 0, failedTests: 0, skippedTests: 0,
                                    failures: [.init(testName: "Screens/testHome", targetName: "Screens", failureText: "Failed")])
        XCTAssertThrowsError(try TestRunDiagnostics.requireSuccess(result(0), device: "sim", summary: summary))
    }

    func testSuccessfulProcessDoesNotRequireNewerResultSummarySchema() throws {
        try TestRunDiagnostics.requireSuccess(result(0), device: "sim", summary: nil)
    }

    func testLegacyFailureIsRejectedWhenTheModernSummaryIsUnavailable() {
        XCTAssertThrowsError(try TestRunDiagnostics.requireSuccess(
            result(0), device: "sim", summary: nil, details: ["XCTAssertTrue failed at Screens.swift:12"]
        )) {
            XCTAssertTrue($0.localizedDescription.contains("Screens.swift:12"))
        }
    }

    func testLaunchFailureStillReportsItsRecoveryInstruction() {
        XCTAssertThrowsError(try TestRunDiagnostics.requireSuccess(
            result(65, output: "Failed to install or launch the test runner"), device: "sim", summary: nil
        )) {
            guard case CLIError.testRunnerLaunchFailed = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }
}
