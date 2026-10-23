import Foundation

package actor XcodeBuildRunner {
    private let shell = ShellRunner()
    package let logLevel: Logger.LogLevel
    private let codeSigningAllowed: Bool
    /// Directory where xcodebuild log files are written. Nil means no log files.
    package var logDir: String?

    package init(logLevel: Logger.LogLevel = .normal, logDir: String? = nil, codeSigningAllowed: Bool = false) {
        self.logLevel = logLevel
        self.logDir = logDir
        self.codeSigningAllowed = codeSigningAllowed
    }

    package func setLogDir(_ dir: String) {
        self.logDir = dir
    }

    /// Build for testing - produces a .xctestrun file.
    /// Returns the path to the .xctestrun file.
    package func buildForTesting(
        project: String?,
        workspace: String?,
        scheme: String,
        derivedDataPath: String,
        platform: CapturePlatform = .iOS
    ) async throws -> String {
        var args = ["build-for-testing"]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        if platform == .macOS {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", "platform=macOS,arch=arm64",
            ]
        } else {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", platform.destination(),
                "CODE_SIGNING_ALLOWED=\(codeSigningAllowed ? "YES" : "NO")",
                "ONLY_ACTIVE_ARCH=YES",
                "EXCLUDED_ARCHS=x86_64",
            ]
        }

        let log = openStreamingLog(name: "build-for-testing")
        let result = try await shell.xcodebuild(
            arguments: args,
            stdoutLineHandler: log.map { makeLogLineHandler(handle: $0.0) }
        )
        if let (handle, _) = log { finalizeLog(handle: handle, stderr: result.stderr) }
        if logLevel == .verbose {
            print(result.stdout)
        }
        guard result.succeeded else {
            throw CLIError.buildFailed(output: result.stderr)
        }

        return try findXCTestRun(in: derivedDataPath)
    }

    /// Run tests without building on a specific simulator.
    /// Returns the path to the .xcresult bundle.
    package func testWithoutBuilding(
        xctestrunPath: String,
        destinationUDID: String,
        resultBundlePath: String,
        testTarget: String? = nil,
        testClass: String? = nil,
        testLanguage: String? = nil,
        testRegion: String? = nil,
        platform: CapturePlatform = .iOS
    ) async throws -> String {
        let destination = platform.destination(udid: destinationUDID)
        var args = [
            "test-without-building",
            "-xctestrun", xctestrunPath,
            "-destination", destination,
            "-resultBundlePath", resultBundlePath,
            "-parallel-testing-enabled", "NO",
            "-collect-test-diagnostics", "never",
        ]

        if let target = testTarget, let cls = testClass {
            args += ["-only-testing", "\(target)/\(cls)"]
        } else if let target = testTarget {
            args += ["-only-testing", target]
        }

        if let testLanguage {
            args += ["-testLanguage", testLanguage]
        }
        if let testRegion {
            args += ["-testRegion", testRegion]
        }

        // Include device UDID in filename to avoid conflicts during parallel runs
        let shortUDID = String(destinationUDID.prefix(8))
        let log = openStreamingLog(name: "test-\(shortUDID)")
        let result = try await shell.xcodebuild(
            arguments: args,
            stdoutLineHandler: log.map { makeLogLineHandler(handle: $0.0) }
        )
        if let (handle, _) = log { finalizeLog(handle: handle, stderr: result.stderr) }
        if logLevel == .verbose {
            print(result.stdout)
        }

        return try await validatedTestResult(result, device: destinationUDID, path: resultBundlePath)
    }

    /// Build and test in a single xcodebuild invocation.
    /// Unlike build-for-testing + test-without-building, this lets XCTest clone the
    /// simulator for a clean state (no stale data, no hardware keyboard issues).
    /// For macOS, tests run natively on the host Mac (no simulator needed).
    /// Returns the path to the .xcresult bundle.
    ///
    /// When `testSelectors` is non-empty, each entry becomes its own
    /// `-only-testing <selector>` pair, replacing the target/class collapse. Used
    /// by per-device `tests:` config so e.g. an iPad-only landscape test doesn't
    /// run on the iPhone simulator. Selectors are pre-resolved to fully
    /// qualified `Target/Class/method` strings by the orchestrator.
    package func test(
        project: String?,
        workspace: String?,
        scheme: String,
        destinationUDID: String,
        derivedDataPath: String,
        resultBundlePath: String,
        testTarget: String? = nil,
        testClass: String? = nil,
        testSelectors: [String]? = nil,
        testLanguage: String? = nil,
        testRegion: String? = nil,
        platform: CapturePlatform = .iOS,
        liveLineHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        var args = ["test"]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        if platform == .macOS {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", "platform=macOS,arch=arm64",
                "-resultBundlePath", resultBundlePath,
                "-parallel-testing-enabled", "NO",
                "-collect-test-diagnostics", "never",
            ]
        } else {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", platform.destination(udid: destinationUDID),
                "-resultBundlePath", resultBundlePath,
                "-parallel-testing-enabled", "NO",
                "-collect-test-diagnostics", "never",
                "CODE_SIGNING_ALLOWED=\(codeSigningAllowed ? "YES" : "NO")",
                "ONLY_ACTIVE_ARCH=YES",
                "EXCLUDED_ARCHS=x86_64",
            ]
        }

        if let selectors = testSelectors, !selectors.isEmpty {
            for selector in selectors {
                args += ["-only-testing", selector]
            }
        } else if let target = testTarget, let cls = testClass {
            args += ["-only-testing", "\(target)/\(cls)"]
        } else if let target = testTarget {
            args += ["-only-testing", target]
        }

        if let testLanguage {
            args += ["-testLanguage", testLanguage]
        }
        if let testRegion {
            args += ["-testRegion", testRegion]
        }

        let shortUDID = String(destinationUDID.prefix(8))
        let log = openStreamingLog(name: "test-\(shortUDID)")
        let result = try await shell.xcodebuild(
            arguments: args,
            stdoutLineHandler: log.map { makeLogLineHandler(handle: $0.0, liveLineHandler: liveLineHandler) }
        )
        if let (handle, _) = log { finalizeLog(handle: handle, stderr: result.stderr) }
        if logLevel == .verbose {
            print(result.stdout)
        }

        return try await validatedTestResult(result, device: destinationUDID, path: resultBundlePath)
    }

    /// A result bundle can exist after a failed test or an interrupted run.
    /// Check both the process and the recorded tests before accepting any images.
    private func validatedTestResult(_ result: ProcessResult, device: String, path: String) async throws -> String {
        let parser = XCResultParser()
        let summary = await parser.extractTestSummary(resultBundlePath: path)
        let details = !result.succeeded || summary == nil || summary?.hasFailures == true
            ? await parser.extractFailureSummaries(resultBundlePath: path) : []
        try TestRunDiagnostics.requireSuccess(result, device: device, summary: summary, details: details)
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.resultBundleNotFound(path: path)
        }
        return path
    }

    /// Simple build (for simple capture mode).
    /// Returns path to the .app bundle.
    package func build(
        project: String?,
        workspace: String?,
        scheme: String,
        destinationUDID: String,
        derivedDataPath: String,
        platform: CapturePlatform = .iOS
    ) async throws -> String {
        var args = ["build"]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        if platform == .macOS {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", "platform=macOS,arch=arm64",
            ]
        } else {
            args += [
                "-scheme", scheme,
                "-derivedDataPath", derivedDataPath,
                "-destination", platform.destination(udid: destinationUDID),
                "CODE_SIGNING_ALLOWED=\(codeSigningAllowed ? "YES" : "NO")",
            ]
        }

        let log = openStreamingLog(name: "build")
        let result = try await shell.xcodebuild(
            arguments: args,
            stdoutLineHandler: log.map { makeLogLineHandler(handle: $0.0) }
        )
        if let (handle, _) = log { finalizeLog(handle: handle, stderr: result.stderr) }
        if logLevel == .verbose {
            print(result.stdout)
        }
        guard result.succeeded else {
            throw CLIError.buildFailed(output: result.stdout + "\n" + result.stderr)
        }

        // A scheme can build Release or use a custom products directory. Resolve the
        // product from the same destination's settings instead of guessing Debug.
        return try await findAppBundle(project: project, workspace: workspace, scheme: scheme,
                                       destinationUDID: destinationUDID, derivedDataPath: derivedDataPath,
                                       platform: platform)
    }

    /// List available schemes for a project/workspace.
    package func listSchemes(project: String?, workspace: String?) async throws -> [String] {
        var args = ["-list", "-json"]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }

        let result = try await shell.xcodebuild(arguments: args)
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let ws = obj["workspace"] as? [String: Any],
           let schemes = ws["schemes"] as? [String] {
            return schemes
        }
        if let proj = obj["project"] as? [String: Any],
           let schemes = proj["schemes"] as? [String] {
            return schemes
        }
        return []
    }

    // MARK: - Private

    /// Create a streaming log file and return the handle + path.
    /// Lines are appended in real-time so `tail -f` works during the build.
    private func openStreamingLog(name: String) -> (FileHandle, String)? {
        guard let logDir else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let path = (logDir as NSString).appendingPathComponent("\(name).log")
        fm.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        return (handle, path)
    }

    /// Build a line handler that appends each line to the given file handle,
    /// and optionally forwards all lines to a live handler (e.g. for non-TTY CLI output).
    private func makeLogLineHandler(
        handle: FileHandle,
        liveLineHandler: (@Sendable (String) -> Void)? = nil
    ) -> @Sendable (String) -> Void {
        let h = handle
        return { line in
            if let data = (line + "\n").data(using: .utf8) {
                h.write(data)
            }
            liveLineHandler?(line)
        }
    }

    /// Append stderr to an already-open log file, then close it.
    private func finalizeLog(handle: FileHandle, stderr: String) {
        if !stderr.isEmpty {
            if let data = ("\n\n--- stderr ---\n\n" + stderr).data(using: .utf8) {
                handle.write(data)
            }
        }
        try? handle.close()
    }

    private func findXCTestRun(in derivedDataPath: String) throws -> String {
        let productsDir = (derivedDataPath as NSString)
            .appendingPathComponent("Build/Products")
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: productsDir) else {
            throw CLIError.xctestrunNotFound(derivedDataPath: derivedDataPath)
        }

        guard let xctestrun = contents.first(where: { $0.hasSuffix(".xctestrun") }) else {
            throw CLIError.xctestrunNotFound(derivedDataPath: derivedDataPath)
        }

        return (productsDir as NSString).appendingPathComponent(xctestrun)
    }

    package func findAppBundle(
        project: String?, workspace: String?, scheme: String, destinationUDID: String,
        derivedDataPath: String, platform: CapturePlatform, buildForTesting: Bool = false
    ) async throws -> String {
        var args = [buildForTesting ? "build-for-testing" : "build", "-showBuildSettings", "-json",
                    "-scheme", scheme, "-derivedDataPath", derivedDataPath,
                    "-destination", platform.destination(udid: destinationUDID),
                    "CODE_SIGNING_ALLOWED=\(codeSigningAllowed ? "YES" : "NO")"]
        if let workspace { args += ["-workspace", workspace] }
        else if let project { args += ["-project", project] }
        let result = try await shell.xcodebuild(arguments: args)
        guard result.succeeded else { throw CLIError.buildFailed(output: result.stderr) }
        return try Self.builtAppBundle(from: result.stdout, scheme: scheme, platform: platform)
    }

    package static func builtAppBundle(
        from json: String, scheme: String, platform: CapturePlatform
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let settings = ProjectDetector.selectBuildSettings(entries, scheme: scheme, platform: platform),
              let type = settings["PRODUCT_TYPE"] as? String, type.hasPrefix("com.apple.product-type.application"),
              let directory = settings["TARGET_BUILD_DIR"] as? String, !directory.isEmpty,
              let product = settings["FULL_PRODUCT_NAME"] as? String, product.hasSuffix(".app") else {
            throw CLIError.buildFailed(output: "Could not resolve the application product from Xcode build settings")
        }
        let path = (directory as NSString).appendingPathComponent(product)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError.buildFailed(output: "Built application is missing at \(path)")
        }
        return path
    }
}
