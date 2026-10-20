import XCTest
@testable import StorescreensCore

final class ArchiveRunnerTests: XCTestCase {
    private let xcode = XcodeInstall(
        appPath: "/Applications/Xcode.app",
        developerDir: "/Applications/Xcode.app/Contents/Developer",
        version: "27.1", isBeta: false
    )

    func testArchiveAndExportUseResolvedKeyAndCleanUp() async throws {
        for source in [ASCCredentials.Source.environment, .file] {
            let recorder = XcodeInvocationRecorder()
            try await exerciseBothOperations(recorder: recorder, source: source)
            let invocations = await recorder.invocations
            XCTAssertEqual(invocations.count, 2)
            XCTAssertEqual(invocations[0].arguments.first, "archive")
            XCTAssertEqual(invocations[1].arguments.first, "-exportArchive")
            XCTAssertEqual(invocations[0].arguments.last, "CUSTOM_SETTING=YES")
            for invocation in invocations {
                XCTAssertEqual(invocation.environment["DEVELOPER_DIR"], xcode.developerDir)
                XCTAssertTrue(invocation.arguments.contains("-allowProvisioningUpdates"))
                XCTAssertEqual(invocation.value(after: "-authenticationKeyID"), "TESTKEY")
                XCTAssertEqual(invocation.value(after: "-authenticationKeyIssuerID"), "TESTISSUER")
                let keyPath = try XCTUnwrap(invocation.value(after: "-authenticationKeyPath"))
                XCTAssertFalse(FileManager.default.fileExists(atPath: keyPath))
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: URL(fileURLWithPath: keyPath).deletingLastPathComponent().path
                ))
            }
        }
    }

    func testFailedXcodeOperationsRemoveKeys() async throws {
        try await exerciseBothOperations(recorder: XcodeInvocationRecorder(exitCode: 65))
    }

    func testLaunchErrorsRemoveKeys() async throws {
        try await exerciseBothOperations(recorder: XcodeInvocationRecorder(launchFails: true))
    }

    func testDisabledProvisioningOmitsAuthentication() async throws {
        let recorder = XcodeInvocationRecorder()
        try await exerciseBothOperations(recorder: recorder, allowProvisioningUpdates: false)
        let invocations = await recorder.invocations
        for invocation in invocations {
            XCTAssertFalse(invocation.arguments.contains("-allowProvisioningUpdates"))
            XCTAssertFalse(invocation.arguments.contains(where: { $0.hasPrefix("-authenticationKey") }))
        }
    }

    func testNoCredentialsPreservesXcodeAccountSigning() async throws {
        let recorder = XcodeInvocationRecorder()
        try await exerciseBothOperations(recorder: recorder, useCredentials: false)
        let invocations = await recorder.invocations
        for invocation in invocations {
            XCTAssertTrue(invocation.arguments.contains("-allowProvisioningUpdates"))
            XCTAssertFalse(invocation.arguments.contains(where: { $0.hasPrefix("-authenticationKey") }))
        }
    }

    private func exerciseBothOperations(
        recorder: XcodeInvocationRecorder,
        source: ASCCredentials.Source = .environment,
        allowProvisioningUpdates: Bool = true,
        useCredentials: Bool = true
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-runner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ipa = directory.appendingPathComponent("Test.ipa")
        try Data().write(to: ipa)
        let credentials = useCredentials ? ASCCredentials(
            keyID: "TESTKEY", issuerID: "TESTISSUER",
            privateKeyPEM: "test private key", source: source
        ) : nil
        let runner = ArchiveRunner(xcode: xcode, runXcodebuild: { args, env, _ in
            try await recorder.run(arguments: args, environment: env)
        })
        for isExport in [false, true] {
            do {
                if isExport {
                    let path = try await runner.export(
                        archivePath: "/tmp/Test.xcarchive", exportPath: directory.path,
                        exportOptionsPlistPath: "/tmp/ExportOptions.plist",
                        allowProvisioningUpdates: allowProvisioningUpdates,
                        credentials: credentials
                    )
                    XCTAssertEqual(path, ipa.path)
                } else {
                    try await runner.archive(
                        project: "/tmp/Test.xcodeproj", workspace: nil, scheme: "Test",
                        configuration: "Release", destination: "generic/platform=iOS",
                        archivePath: "/tmp/Test.xcarchive", derivedDataPath: nil,
                        allowProvisioningUpdates: allowProvisioningUpdates,
                        credentials: credentials, buildSettings: ["CUSTOM_SETTING": "YES"]
                    )
                }
                XCTAssertFalse(recorder.launchFails)
                XCTAssertEqual(recorder.exitCode, 0)
            } catch {
                if recorder.launchFails {
                    XCTAssertTrue(error is XcodeInvocationRecorder.LaunchError)
                } else if recorder.exitCode != 0, let cliError = error as? CLIError {
                    switch (isExport, cliError) {
                    case (true, .exportFailed), (false, .archiveFailed): break
                    default: XCTFail("Unexpected error: \(error)")
                    }
                } else {
                    throw error
                }
            }
            let invocations = await recorder.invocations
            let invocation = try XCTUnwrap(invocations.last)
            if let keyPath = invocation.value(after: "-authenticationKeyPath") {
                XCTAssertFalse(FileManager.default.fileExists(atPath: keyPath))
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: URL(fileURLWithPath: keyPath).deletingLastPathComponent().path
                ))
            }
        }
    }
}

private actor XcodeInvocationRecorder {
    struct Invocation: Sendable {
        let arguments: [String]
        let environment: [String: String]

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
    }
    struct LaunchError: Error {}
    let exitCode: Int32
    let launchFails: Bool
    var invocations: [Invocation] = []

    init(exitCode: Int32 = 0, launchFails: Bool = false) {
        self.exitCode = exitCode
        self.launchFails = launchFails
    }

    func run(arguments: [String], environment: [String: String]) throws -> ProcessResult {
        let invocation = Invocation(arguments: arguments, environment: environment)
        invocations.append(invocation)
        if let path = invocation.value(after: "-authenticationKeyPath") {
            XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "test private key")
            let filePermissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
            XCTAssertEqual(filePermissions, 0o600)
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? Int
            XCTAssertEqual(directoryPermissions, 0o700)
        }
        if launchFails { throw LaunchError() }
        return ProcessResult(stdout: "", stderr: "", exitCode: exitCode)
    }
}
