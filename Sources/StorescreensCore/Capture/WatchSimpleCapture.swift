import Foundation

/// A standalone UI-test runner for simple Watch captures. It needs no test target
/// in the user's project and accepts pixels only after XCTest sees the app.
package struct WatchSimpleCapture {
    private let xctestrun: String
    private let buildRunner: XcodeBuildRunner
    private let workspace: URL
    private let resultDirectory: URL?

    package init(workspace: URL, buildRunner: XcodeBuildRunner, resultDirectory: URL? = nil) async throws {
        self.workspace = workspace
        self.buildRunner = buildRunner
        self.resultDirectory = resultDirectory
        let project = try Self.writeProject(to: workspace)
        xctestrun = try await buildRunner.buildForTesting(
            project: project.path, workspace: nil, scheme: "WatchSimpleCapture",
            derivedDataPath: workspace.appendingPathComponent("DerivedData").path, platform: .watchOS
        )
    }

    package func capture(udid: String, bundleID: String, arguments: [String], locale: String?, outputPath: String) async throws {
        // Each attempt has a new directory, so a failed test cannot reuse an old PNG.
        let attempt = workspace.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: attempt, withIntermediateDirectories: true)
        let candidate = attempt.appendingPathComponent("capture.png")
        let settings = try JSONSerialization.data(withJSONObject: [
            "bundleID": bundleID, "arguments": Self.launchArguments(arguments, locale: locale),
        ])
        let (language, region) = CaptureOrchestrator.parseLocale(locale)
        _ = try await buildRunner.testWithoutBuilding(
            xctestrunPath: xctestrun, destinationUDID: udid,
            resultBundlePath: (resultDirectory ?? attempt).appendingPathComponent("\(UUID().uuidString).xcresult").path,
            testLanguage: language, testRegion: region,
            platform: .watchOS,
            environment: [
                "TEST_RUNNER_STORESCREENS_SIMPLE_SETTINGS": settings.base64EncodedString(),
                "TEST_RUNNER_STORESCREENS_SIMPLE_OUTPUT": candidate.path,
            ]
        )
        try Self.requireImage(at: candidate.path)
        try FileManager.default.copyItem(atPath: candidate.path, toPath: outputPath)
    }

    package static func launchArguments(_ arguments: [String], locale: String?) -> [String] {
        guard let locale, let language = CaptureOrchestrator.parseLocale(locale).language else { return arguments }
        return arguments + ["-AppleLanguages", "(\(language))", "-AppleLocale", locale.replacingOccurrences(of: "-", with: "_")]
    }

    package static func requireImage(at path: String) throws {
        guard !SimulatorManager.isBlankImage(atPath: path) else {
            throw CLIError.screenshotFailed(reason: "Watch application capture is missing, unreadable, or blank; no image was accepted.")
        }
    }

    /// Generate a small, independent Xcode project using Apple's project format.
    /// Keeping this in code avoids a dependency on a project generator or on the
    /// application's scheme, build configuration, or UI-test source files.
    package static func writeProject(to directory: URL) throws -> URL {
        let project = directory.appendingPathComponent("WatchSimpleCapture.xcodeproj")
        let schemes = project.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemes, withIntermediateDirectories: true)
        try source.write(to: directory.appendingPathComponent("WatchSimpleCapture.swift"), atomically: true, encoding: .utf8)
        let objects: [String: Any] = [
            "PROJECT": ["isa": "PBXProject", "buildConfigurationList": "PROJECT_CONFIGS", "compatibilityVersion": "Xcode 14.0", "mainGroup": "GROUP", "productRefGroup": "PRODUCTS", "projectDirPath": "", "targets": ["TARGET"]],
            "GROUP": ["isa": "PBXGroup", "children": ["SOURCE", "PRODUCTS"], "sourceTree": "<group>"],
            "PRODUCTS": ["isa": "PBXGroup", "name": "Products", "children": ["PRODUCT"], "sourceTree": "<group>"],
            "SOURCE": ["isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift", "path": "WatchSimpleCapture.swift", "sourceTree": "<group>"],
            "PRODUCT": ["isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "path": "WatchSimpleCapture.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"],
            "BUILD_SOURCE": ["isa": "PBXBuildFile", "fileRef": "SOURCE"],
            "SOURCES": ["isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": ["BUILD_SOURCE"], "runOnlyForDeploymentPostprocessing": 0],
            "TARGET": ["isa": "PBXNativeTarget", "name": "WatchSimpleCapture", "productName": "WatchSimpleCapture", "productType": "com.apple.product-type.bundle.ui-testing", "productReference": "PRODUCT", "buildConfigurationList": "TARGET_CONFIGS", "buildPhases": ["SOURCES"], "buildRules": [], "dependencies": []],
            "PROJECT_CONFIGS": ["isa": "XCConfigurationList", "buildConfigurations": ["PROJECT_DEBUG"], "defaultConfigurationName": "Debug", "defaultConfigurationIsVisible": 0],
            "TARGET_CONFIGS": ["isa": "XCConfigurationList", "buildConfigurations": ["TARGET_DEBUG"], "defaultConfigurationName": "Debug", "defaultConfigurationIsVisible": 0],
            "PROJECT_DEBUG": ["isa": "XCBuildConfiguration", "name": "Debug", "buildSettings": ["SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES"]],
            "TARGET_DEBUG": ["isa": "XCBuildConfiguration", "name": "Debug", "buildSettings": [
                "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.storescreens.simple-capture",
                "GENERATE_INFOPLIST_FILE": "YES", "SDKROOT": "watchos", "SUPPORTED_PLATFORMS": "watchos watchsimulator",
                "TARGETED_DEVICE_FAMILY": "4", "WATCHOS_DEPLOYMENT_TARGET": "9.0",
                "CODE_SIGNING_ALLOWED": "NO", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "archiveVersion": "1", "objectVersion": "56", "classes": [String: String](),
            "objects": objects, "rootObject": "PROJECT",
        ], format: .xml, options: 0)
        try data.write(to: project.appendingPathComponent("project.pbxproj"))
        try scheme.write(to: schemes.appendingPathComponent("WatchSimpleCapture.xcscheme"), atomically: true, encoding: .utf8)
        return project
    }

    private static let scheme = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme version="1.7">
      <BuildAction buildImplicitDependencies="YES">
        <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
          <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="WatchSimpleCapture.xctest" BlueprintName="WatchSimpleCapture" ReferencedContainer="container:WatchSimpleCapture.xcodeproj"/>
        </BuildActionEntry></BuildActionEntries>
      </BuildAction>
      <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES">
        <Testables><TestableReference skipped="NO" parallelizable="NO">
          <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="WatchSimpleCapture.xctest" BlueprintName="WatchSimpleCapture" ReferencedContainer="container:WatchSimpleCapture.xcodeproj"/>
        </TestableReference></Testables>
      </TestAction>
    </Scheme>
    """

    package static let source = #"""
    import XCTest

    final class WatchSimpleCapture: XCTestCase {
        func testCaptureVisibleApplication() throws {
            continueAfterFailure = false
            let environment = ProcessInfo.processInfo.environment
            let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(environment["STORESCREENS_SIMPLE_SETTINGS"])))
            let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let app = XCUIApplication(bundleIdentifier: try XCTUnwrap(settings["bundleID"] as? String))
            app.launchArguments = try XCTUnwrap(settings["arguments"] as? [String])
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Watch app did not reach the foreground; no screenshot was accepted.")

            // A boot logo, watch face, or empty launch window is not app content.
            // Custom-rendered apps without accessible controls need a dedicated
            // XCUITest flow with an application-specific readiness assertion.
            let visibleContent = NSPredicate { _, _ in
                guard app.state == .runningForeground else { return false }
                let statusBars = app.statusBars.allElementsBoundByIndex.map { $0.frame }
                return app.descendants(matching: .any).allElementsBoundByIndex.contains { element in
                    switch element.elementType {
                    case .application, .window, .other, .scrollView, .statusBar: return false
                    default:
                        guard !element.label.isEmpty, element.isHittable else { return false }
                        // The system clock alone is not evidence of app content.
                        return !statusBars.contains { $0.intersects(element.frame) }
                    }
                }
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visibleContent, object: nil)], timeout: 30), .completed,
                           "Watch app has no visible accessible content. Use an XCUITest capture flow with an app-specific readiness assertion; no screenshot was accepted.")
            let screenshot = app.screenshot()
            XCTAssertEqual(app.state, .runningForeground, "Watch app left the foreground during capture; no screenshot was accepted.")
            let output = try XCTUnwrap(environment["STORESCREENS_SIMPLE_OUTPUT"])
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }
    """#
}
