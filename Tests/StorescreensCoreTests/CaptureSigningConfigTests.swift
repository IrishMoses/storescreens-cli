import XCTest
@testable import StorescreensCore

final class CaptureSigningConfigTests: XCTestCase {
    private let base = """
    project: App.xcodeproj
    scheme: App
    devices: [{simulator: iPhone 17 Pro Max}]
    output_dir: captures
    """

    private func withConfig(_ contents: String, _ check: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("capture.yml")
        try contents.write(to: path, atomically: true, encoding: .utf8)
        try check(path)
    }

    func testSigningOptInSurvivesConfigurationReadAndWrite() throws {
        try withConfig(base + "\ncode_signing_allowed: true\n") { path in
            let config = try ConfigLoader().load(from: path.path)
            XCTAssertEqual(config.codeSigningAllowed, true)
            try ConfigLoader().write(config, to: path.path)
            XCTAssertEqual(try ConfigLoader().load(from: path.path).codeSigningAllowed, true)
        }
    }

    func testExistingCaptureConfigurationsKeepTheirDefault() throws {
        try withConfig(base) { path in
            XCTAssertNil(try ConfigLoader().load(from: path.path).codeSigningAllowed)
        }
    }

    func testAnInvalidSigningValueDoesNotSilentlyDisableEntitlements() throws {
        try withConfig(base + "\ncode_signing_allowed: inherited\n") { path in
            XCTAssertThrowsError(try ConfigLoader().load(from: path.path))
        }
    }
}
