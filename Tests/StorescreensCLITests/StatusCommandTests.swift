import XCTest
@testable import storescreens_cli

final class StatusCommandTests: XCTestCase {
    private func report(_ states: [String]) -> StatusCommand.StatusReport {
        .init(
            app: .init(id: "APP"), platform: "IOS", versions: [],
            reviewSubmissions: states.enumerated().map {
                .init(id: "SUB-\($0.offset)", state: $0.element)
            }
        )
    }

    func testQueuedSubmissionTakesPrecedenceOverLeftoverDraftInEitherOrder() throws {
        for states in [["READY_FOR_REVIEW", "WAITING_FOR_REVIEW"],
                       ["WAITING_FOR_REVIEW", "READY_FOR_REVIEW"]] {
            let hint = try XCTUnwrap(StatusCommand().nextActionHint(report(states)))
            XCTAssertTrue(hint.contains("Submission is queued"))
            XCTAssertFalse(hint.contains("submit --submit-for-review"))
            XCTAssertTrue(hint.contains("cancel SUB-\(states.firstIndex(of: "WAITING_FOR_REVIEW")!)"))
        }
    }

    func testInReviewTakesPrecedenceOverQueuedRejectedAndDraftSubmissions() throws {
        for states in [["READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "WAITING_FOR_REVIEW", "IN_REVIEW"],
                       ["IN_REVIEW", "WAITING_FOR_REVIEW", "UNRESOLVED_ISSUES", "READY_FOR_REVIEW"]] {
            let hint = try XCTUnwrap(StatusCommand().nextActionHint(report(states)))
            XCTAssertTrue(hint.contains("Apple is reviewing"))
            XCTAssertFalse(hint.contains("submit --submit-for-review"))
        }
    }

    func testRejectedSubmissionTakesPrecedenceOverDraft() throws {
        let hint = try XCTUnwrap(StatusCommand().nextActionHint(
            report(["READY_FOR_REVIEW", "UNRESOLVED_ISSUES"])
        ))
        XCTAssertTrue(hint.contains("Apple rejected"))
        XCTAssertTrue(hint.contains("cancel SUB-1"))
    }

    func testDraftAloneStillExplainsHowToSubmit() throws {
        let hint = try XCTUnwrap(StatusCommand().nextActionHint(report(["COMPLETE", "READY_FOR_REVIEW"])))
        XCTAssertTrue(hint.contains("submit --submit-for-review"))
    }

    func testNewestSubmissionWithinStateProvidesCancellationID() throws {
        var value = report(["WAITING_FOR_REVIEW", "WAITING_FOR_REVIEW", "READY_FOR_REVIEW"])
        value.reviewSubmissions[1].submittedDate = Date(timeIntervalSince1970: 2)
        value.reviewSubmissions[0].submittedDate = Date(timeIntervalSince1970: 1)
        let hint = try XCTUnwrap(StatusCommand().nextActionHint(value))
        XCTAssertTrue(hint.contains("cancel SUB-1"))
    }

    func testVersionAdvisoriesStillWorkWithoutOpenSubmission() throws {
        for (state, expected) in [
            ("PENDING_DEVELOPER_RELEASE", "pending your manual release"),
            ("PENDING_APPLE_RELEASE", "scheduled for Apple to release"),
            ("REJECTED", "needs attention"),
            ("READY_FOR_SALE", "Live on the App Store"),
        ] {
            var value = report(["COMPLETE"])
            value.versions = [.init(id: "VERSION", versionString: "1.2.3", state: state)]
            let hint = try XCTUnwrap(StatusCommand().nextActionHint(value))
            XCTAssertTrue(hint.contains(expected))
            XCTAssertTrue(hint.contains("1.2.3"))
        }
        XCTAssertNil(StatusCommand().nextActionHint(report(["COMPLETE"])))
    }
}
