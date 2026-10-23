import XCTest
@testable import StorescreensCore

final class SimulatorReadinessTests: XCTestCase {
    private actor Commands {
        var responses: [ProcessResult]
        var arguments: [[String]] = []
        init(_ responses: [ProcessResult]) { self.responses = responses }
        func run(_ args: [String], timeout: Duration) -> ProcessResult {
            arguments.append(args)
            return responses.isEmpty ? ProcessResult(stdout: "", stderr: "No response", exitCode: 1) : responses.removeFirst()
        }
    }

    private func ok(_ output: String = "") -> ProcessResult {
        ProcessResult(stdout: output, stderr: "", exitCode: 0)
    }

    func testStartupWaitsPastBootstatusUntilSystemUIStarts() async throws {
        let commands = Commands([ok(), ok("com.apple.springboard.finishedstartup 0"), ok("com.apple.springboard.finishedstartup 3524")])
        try await SimulatorManager.waitForStartup("watch", pollInterval: .zero) { args, timeout in
            await commands.run(args, timeout: timeout)
        }
        let calls = await commands.arguments
        XCTAssertEqual(calls, [
            ["bootstatus", "watch", "-b"],
            ["spawn", "watch", "notifyutil", "-g", "com.apple.springboard.finishedstartup"],
            ["spawn", "watch", "notifyutil", "-g", "com.apple.springboard.finishedstartup"],
        ])
    }

    func testFailedBootstatusCannotBeAccepted() async {
        let commands = Commands([ProcessResult(stdout: "", stderr: "boot failed", exitCode: 1), ok("com.apple.springboard.finishedstartup 1")])
        do {
            try await SimulatorManager.waitForStartup("watch") { args, timeout in await commands.run(args, timeout: timeout) }
            XCTFail("Failed startup was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("bootstatus failed"))
        }
        let calls = await commands.arguments
        XCTAssertEqual(calls.count, 1)
    }

    func testUnavailableReadinessCheckCannotBeAccepted() async {
        let commands = Commands([ok(), ProcessResult(stdout: "", stderr: "device shut down", exitCode: 1)])
        do {
            try await SimulatorManager.waitForStartup("watch") { args, timeout in await commands.run(args, timeout: timeout) }
            XCTFail("Unavailable startup signal was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("could not verify system UI startup"))
        }
    }

    func testZeroAndMalformedReadinessSignalsTimeOut() async {
        for signal in ["com.apple.springboard.finishedstartup 0", "unexpected output"] {
            do {
                try await SimulatorManager.waitForStartup("watch", timeout: .milliseconds(5), pollInterval: .milliseconds(1)) { args, _ in
                    ProcessResult(stdout: args[0] == "bootstatus" ? "" : signal, stderr: "", exitCode: 0)
                }
                XCTFail("Unready simulator was accepted")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("timed out"))
            }
        }
    }

    func testCancellationCannotBeAccepted() async {
        let task = Task {
            try await SimulatorManager.waitForStartup("watch", pollInterval: .seconds(5)) { args, _ in
                ProcessResult(stdout: "com.apple.springboard.finishedstartup 0", stderr: "", exitCode: 0)
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Canceled startup was accepted")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testHungCommandIsTerminatedAndReported() async throws {
        let result = try await ShellRunner().run("/bin/sleep", arguments: ["30"], timeout: .milliseconds(20))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stderr.contains("Command timed out"))
    }

    func testSuccessfulCommandWithDeadlineIsUnchanged() async throws {
        let result = try await ShellRunner().run("/usr/bin/true", timeout: .seconds(10))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stderr, "")
    }

    func testCommandCannotHideTimeoutByExitingSuccessfully() async throws {
        let result = try await ShellRunner().run(
            "/bin/sh", arguments: ["-c", "trap 'exit 0' TERM; while :; do :; done"],
            timeout: .milliseconds(100)
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stderr.contains("Command timed out"))
    }
}
