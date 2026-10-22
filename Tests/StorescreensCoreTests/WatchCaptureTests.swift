import XCTest
@testable import StorescreensCore

final class WatchCaptureTests: XCTestCase {
    private func watch() -> ResolvedDevice {
        ResolvedDevice(simulatorName: "Test Watch", udid: "watch", deviceTypeIdentifier: "watch",
                       appStoreSize: AppStoreScreenSize(width: 416, height: 496, productFamily: 4))
    }

    func testWatchUsesWatchOSDestinationsAndProducts() {
        XCTAssertEqual(watch().platform, .watchOS)
        XCTAssertEqual(watch().platform.destination(udid: "watch"), "platform=watchOS Simulator,id=watch")
        XCTAssertEqual(CapturePlatform.watchOS.destination(), "generic/platform=watchOS Simulator")
        XCTAssertEqual(CapturePlatform.watchOS.productsDirectory, "Debug-watchsimulator")
        XCTAssertEqual(CapturePlatform.watchOS.deploymentTargetKey, "WATCHOS_DEPLOYMENT_TARGET")
        XCTAssertFalse(CapturePlatform.watchOS.supportsStatusBarOverride)
        XCTAssertFalse(CapturePlatform.watchOS.supportsSimulatorAppearance)
    }

    func testExistingPlatformsKeepTheirDestinations() {
        XCTAssertEqual(CapturePlatform.iOS.destination(udid: "phone"), "platform=iOS Simulator,id=phone")
        XCTAssertEqual(CapturePlatform.macOS.destination(udid: "unused"), "platform=macOS,arch=arm64")
    }

    func testWatchDefaultsToOneDarkCapture() throws {
        var config = CaptureConfig(scheme: "WatchApp", devices: [], outputDir: "output")
        try CaptureOrchestrator.configurePlatform(&config, devices: [watch()])
        XCTAssertEqual(config.appearances, ["dark"])
    }

    func testLightOnlyWatchCaptureIsRejected() {
        var config = CaptureConfig(scheme: "WatchApp", devices: [], outputDir: "output")
        config.appearances = ["light"]
        XCTAssertThrowsError(try CaptureOrchestrator.configurePlatform(&config, devices: [watch()]))
    }

    func testWatchRejectsLightScreenshotOverrides() {
        var config = CaptureConfig(scheme: "WatchApp", devices: [], outputDir: "output")
        config.screenshotAppearances = ["Home": "light"]
        XCTAssertThrowsError(try CaptureOrchestrator.configurePlatform(&config, devices: [watch()]))
    }

    func testWatchAndPhoneNeedSeparateCaptureSchemes() {
        var config = CaptureConfig(scheme: "WatchApp", devices: [], outputDir: "output")
        let phone = ResolvedDevice(simulatorName: "Phone", udid: "phone", deviceTypeIdentifier: "phone",
                                   appStoreSize: AppStoreScreenSize(width: 1320, height: 2868, productFamily: 1))
        XCTAssertThrowsError(try CaptureOrchestrator.configurePlatform(&config, devices: [watch(), phone]))
    }

    func testCompanionConfigurationRoundTrips() throws {
        let config = CaptureConfig(scheme: "WatchApp", devices: [DeviceConfig(simulator: "Watch", platform: "watchOS", companion: "Phone", companionScheme: "PhoneApp")], outputDir: "output")
        let decoded = try JSONDecoder().decode(CaptureConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.devices.first?.companion, "Phone")
        XCTAssertEqual(decoded.devices.first?.platform, "watchOS")
        XCTAssertEqual(decoded.devices.first?.companionScheme, "PhoneApp")
        try ConfigLoader.validate(decoded)
    }

    func testUnknownPlatformIsRejected() {
        let config = CaptureConfig(scheme: "App", devices: [DeviceConfig(simulator: "Watch", platform: "watcOS")], outputDir: "output")
        XCTAssertThrowsError(try ConfigLoader.validate(config))
    }

    func testCompanionRequiresWatchPlatform() {
        for platform in ["iOS", "macOS"] {
            let config = CaptureConfig(scheme: "App", devices: [DeviceConfig(simulator: "Device", platform: platform, companion: "Phone")], outputDir: "output")
            XCTAssertThrowsError(try ConfigLoader.validate(config))
        }
    }

    func testCompanionSchemeRequiresCompanion() {
        let config = CaptureConfig(scheme: "WatchApp", devices: [DeviceConfig(simulator: "Watch", platform: "watchOS", companionScheme: "PhoneApp")], outputDir: "output")
        XCTAssertThrowsError(try ConfigLoader.validate(config))
    }

    func testWatchSettingsWinOverCompanionDependency() {
        let entries: [[String: Any]] = [
            ["target": "Phone", "buildSettings": ["PRODUCT_TYPE": "com.apple.product-type.application", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "1,2"]],
            ["target": "WatchApp", "buildSettings": ["PRODUCT_TYPE": "com.apple.product-type.application", "SUPPORTED_PLATFORMS": "watchos watchsimulator", "TARGETED_DEVICE_FAMILY": "4"]],
        ]
        XCTAssertEqual(ProjectDetector.selectBuildSettings(entries, scheme: "WatchApp")?["TARGETED_DEVICE_FAMILY"] as? String, "4")
        XCTAssertEqual(ProjectDetector.selectBuildSettings(entries, scheme: "Capture", platform: .watchOS)?["TARGETED_DEVICE_FAMILY"] as? String, "4")
    }

    func testExistingCompanionPairCanBeReusedButNotReplaced() throws {
        let json = #"{"pairs":{"existing":{"watch":{"udid":"watch"},"phone":{"udid":"phone"}}}}"#
        let pairs = try JSONDecoder().decode(SimulatorPairList.self, from: Data(json.utf8)).pairs
        XCTAssertEqual(try SimulatorManager.matchingPair(watch: "watch", phone: "phone", pairs: pairs), "existing")
        XCTAssertThrowsError(try SimulatorManager.matchingPair(watch: "watch", phone: "another-phone", pairs: pairs))
        XCTAssertNil(try SimulatorManager.matchingPair(watch: "another-watch", phone: "phone", pairs: pairs))
    }

    func testWatchAppLookupIgnoresPhoneBuildProducts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = root.appendingPathComponent("Build/Products/Debug-iphonesimulator/Phone.app")
        let watch = root.appendingPathComponent("Build/Products/Debug-watchsimulator/Watch.app")
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        let found = try await XcodeBuildRunner().findAppBundle(in: root.path, platform: .watchOS)
        XCTAssertEqual(found, watch.path)
    }
}
