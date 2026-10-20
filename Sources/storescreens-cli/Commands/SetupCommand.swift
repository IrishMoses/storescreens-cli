import ArgumentParser
import StorescreensCore
import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Interactive wizard to set up screenshot UI tests."
    )

    @Option(name: .long, help: "Xcode project or workspace path.")
    var project: String?

    @Flag(name: .long, help: "Skip interactive prompts and use defaults.")
    var nonInteractive: Bool = false

    @Flag(name: .long, help: "Print the editable XCUITest template without changing a project.")
    var printTemplate: Bool = false

    func run() async throws {
        if printTemplate {
            print(try generateTestFile(screenNames: ["Home", "Search"]))
            return
        }
        let logger = Logger()
        let detector = ProjectDetector()

        // 1. Detect project/workspace
        logger.header("Project Detection")
        let (detectedProject, detectedWorkspace) = detector.detectProjectFile()
        let projectPath = project ?? detectedProject
        let workspacePath = detectedWorkspace

        guard projectPath != nil || workspacePath != nil else {
            logger.log("No .xcodeproj or .xcworkspace found in current directory.", level: .error)
            logger.log("Run this command from your Xcode project directory.", level: .info)
            return
        }

        if let ws = workspacePath {
            logger.log("Found workspace: \(ws)", level: .success)
        } else if let proj = projectPath {
            logger.log("Found project: \(proj)", level: .success)
        }

        // 2. Detect scheme
        let scheme = await detector.detectScheme(
            project: projectPath, workspace: workspacePath
        ) ?? "MyApp"
        logger.log("Detected scheme: \(scheme)", level: .success)

        // 3. Detect deployment target
        let deploymentTarget = await detector.detectDeploymentTarget(
            project: projectPath, workspace: workspacePath, scheme: scheme
        )
        if let target = deploymentTarget {
            logger.log("Deployment target: iOS \(target)", level: .success)
        }

        // 4. Find UI test target
        logger.header("UI Test Target")
        let uiTestTargets = await detector.findUITestTargets(
            project: projectPath, workspace: workspacePath
        )

        let testTargetName: String
        let testTargetDir: String

        if let first = uiTestTargets.first {
            testTargetName = first
            testTargetDir = first
            logger.log("Found UI test target: \(first)", level: .success)
        } else {
            // No UI test target found - guide the user
            let suggestedName = scheme + "UITests"
            logger.log("No UI test target found.", level: .warning)
            logger.log("Create one in Xcode:", level: .info)
            logger.log("  1. Open your project in Xcode", level: .info)
            logger.log("  2. File > New > Target > UI Testing Bundle", level: .info)
            logger.log("  3. Name it \"\(suggestedName)\"", level: .info)
            logger.log("  4. Re-run: storescreens setup", level: .info)

            // Still generate the file in the expected directory so it's ready
            testTargetName = suggestedName
            testTargetDir = suggestedName
            logger.log("", level: .info)
            logger.log("Generating test file anyway so it's ready when you add the target...", level: .info)
        }

        // 5. Scan source for screens, then ask user to confirm/edit
        logger.header("Screenshot Screens")

        let scanner = ScreenScanner()
        let discovered = scanner.scan(directory: ".")

        let screenNames: [String]
        if nonInteractive || !isInteractive() {
            if !discovered.isEmpty {
                screenNames = discovered.map(\.name)
                logger.log("Auto-discovered \(screenNames.count) screens from source:", level: .info)
                for screen in discovered {
                    logger.log("  \(screen.name) (\(screen.source.rawValue))", level: .info)
                }
            } else {
                screenNames = ["Home", "Detail"]
                logger.log("No screens found in source. Using defaults: Home, Detail", level: .info)
            }
        } else if !discovered.isEmpty {
            logger.log("Found \(discovered.count) screens in your source code:", level: .info)
            for (i, screen) in discovered.enumerated() {
                logger.log("  \(i + 1). \(screen.name) (\(screen.source.rawValue))", level: .info)
            }
            print("")
            print("  Press Enter to use these, or type your own (comma-separated)")
            print("  > ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                screenNames = input.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            } else {
                screenNames = discovered.map(\.name)
                logger.log("Using discovered screens.", level: .success)
            }
        } else {
            logger.log("No screens auto-detected from source.", level: .info)
            print("  Enter screenshot names (comma-separated)")
            print("  Example: Home, Settings, Profile, Search Results")
            print("  > ", terminator: "")
            if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
                screenNames = input.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            } else {
                screenNames = ["Home", "Detail"]
                logger.log("No input - using defaults: Home, Detail", level: .info)
            }
        }

        // 6. Generate ScreenshotTests.swift
        logger.header("Generating Test File")
        let testFileContent = try generateTestFile(screenNames: screenNames)
        let fm = FileManager.default

        try fm.createDirectory(atPath: testTargetDir, withIntermediateDirectories: true)
        let testFilePath = (testTargetDir as NSString).appendingPathComponent("ScreenshotTests.swift")

        if fm.fileExists(atPath: testFilePath) {
            if nonInteractive || !isInteractive() {
                logger.log("ScreenshotTests.swift already exists, skipping.", level: .warning)
            } else {
                print("  \(testFilePath) already exists. Overwrite? [y/N] ", terminator: "")
                let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
                if answer == "y" || answer == "yes" {
                    try testFileContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
                    logger.log("Overwrote \(testFilePath) (\(screenNames.count) screenshots)", level: .success)
                } else {
                    logger.log("Skipped - keeping existing file.", level: .info)
                }
            }
        } else {
            try testFileContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
            logger.log("Wrote \(testFilePath) (\(screenNames.count) screenshots)", level: .success)
        }

        // 7. Ensure storescreens.yml exists and has test_target/test_class
        logger.header("Config")
        let configPath = "storescreens.yml"
        if fm.fileExists(atPath: configPath) {
            var contents = try String(contentsOfFile: configPath, encoding: .utf8)
            var updated = false

            // Uncomment or add test_target
            if contents.contains("# test_target:") {
                contents = contents.replacingOccurrences(
                    of: "# test_target: MyAppUITests",
                    with: "test_target: \"\(testTargetName)\""
                )
                updated = true
            } else if !contents.contains("test_target:") {
                contents += "\ntest_target: \"\(testTargetName)\"\n"
                updated = true
            }

            // Uncomment or add test_class
            if contents.contains("# test_class:") {
                contents = contents.replacingOccurrences(
                    of: "# test_class: ScreenshotTests",
                    with: "test_class: \"ScreenshotTests\""
                )
                updated = true
            } else if !contents.contains("test_class:") {
                contents += "test_class: \"ScreenshotTests\"\n"
                updated = true
            }

            // Emit `screenshots:` list so the capture pipeline can stamp
            // mtimes in display order (first in list = newest mtime).
            // Skip if the user already wrote one.
            if !contents.contains("\nscreenshots:") && !contents.hasPrefix("screenshots:") {
                var section = "\n# Screenshot collection order. Drives HTML\n"
                section += "# preview gallery order, and the mtime stamp on output PNGs so\n"
                section += "# `ls -t` / Finder \"Date Created\" sort matches this list.\n"
                section += "screenshots:\n"
                for name in screenNames {
                    let clean = name.replacingOccurrences(of: " ", with: "")
                    section += "  - \"\(clean)\"\n"
                }
                contents += section
                updated = true
            }

            if updated {
                try contents.write(toFile: configPath, atomically: true, encoding: .utf8)
                logger.log("Updated \(configPath) with test_target, test_class, and screenshots list", level: .success)
            } else {
                logger.log("\(configPath) already has test_target, test_class, and screenshots list", level: .success)
            }
        } else {
            logger.log("No storescreens.yml found. Run 'storescreens init' first, then re-run setup.", level: .warning)
        }

        // 8. Check simulator runtimes
        logger.header("Simulator Runtimes")
        let runtimes = await detector.listInstalledRuntimes()
        let availableRuntimes = runtimes.filter(\.isAvailable)

        if availableRuntimes.isEmpty {
            logger.log("No iOS simulator runtimes installed.", level: .error)
            logger.log("Install via: Xcode > Settings > Platforms", level: .info)
        } else {
            for runtime in availableRuntimes {
                logger.log("iOS \(runtime.version) installed", level: .success)
            }

            // Check if deployment target is satisfied
            if let target = deploymentTarget {
                let targetParts = target.split(separator: ".").compactMap { Int($0) }
                let targetMajor = targetParts.first ?? 0

                let hasCompatible = availableRuntimes.contains { runtime in
                    let runtimeParts = runtime.version.split(separator: ".").compactMap { Int($0) }
                    let runtimeMajor = runtimeParts.first ?? 0
                    return runtimeMajor >= targetMajor
                }

                if !hasCompatible {
                    logger.log(
                        "No runtime >= iOS \(target). Install via: Xcode > Settings > Platforms",
                        level: .error
                    )
                }
            }

            // Check required App Store sizes against compatible simulators
            let manager = SimulatorManager()
            let devices = try await manager.listAvailableDevices(minimumRuntime: deploymentTarget)
            var sizeMap: [String: AppStoreScreenSize] = [:]
            for device in devices {
                sizeMap[device.udid] = try await manager.appStoreSize(for: device)
            }
            detector.warnMissingRequiredSizes(sizeMap: sizeMap, logger: logger)
        }

        // Done
        logger.header("Setup Complete")
        logger.log("Next steps:", level: .info)
        logger.log("  1. Edit \(testFilePath) to add navigation logic between screenshots", level: .info)
        if uiTestTargets.isEmpty {
            logger.log("  2. Add the UI test target in Xcode (see instructions above)", level: .info)
            logger.log("  3. Run: storescreens capture", level: .info)
        } else {
            logger.log("  2. Run: storescreens capture", level: .info)
        }
    }

    // MARK: - Private

    private func isInteractive() -> Bool {
        isatty(STDIN_FILENO) != 0
    }

    func generateTestFile(screenNames: [String]) throws -> String {
        guard let url = Bundle.module.url(forResource: "ScreenshotTests.swift", withExtension: "template") else {
            throw CLIError.configInvalid(reason: "Screenshot test template is missing from the installation")
        }
        let template = try String(contentsOf: url, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let calls = try screenNames.enumerated().map { index, name -> String in
            let identifier = name.replacingOccurrences(of: " ", with: "")
            let literal = String(data: try encoder.encode(identifier), encoding: .utf8)!
            let navigation = index == 0 ? "" : "        // Navigate to the next screen before capturing.\n"
            return navigation + "        takeScreenshot(named: \(literal))\n"
        }.joined()
        return template.replacingOccurrences(of: "{{SCREENSHOT_CALLS}}", with: calls)
    }
}
