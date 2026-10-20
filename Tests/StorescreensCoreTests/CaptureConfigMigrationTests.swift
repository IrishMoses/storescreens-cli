import XCTest
@testable import StorescreensCore

final class CaptureConfigMigrationTests: XCTestCase {
    private func withFile(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("storescreens-migration-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.appendingPathComponent("storescreens.yml"))
    }

    private let original = """
    # Reviewed screenshot workflow
    project: App.xcodeproj
    scheme: App
    devices:
      - simulator: iPhone 17 Pro Max
        tests: [ScreenshotTests/testHome]
    locales: [en-US, el, zh-Hans]
    appearances: [light]
    screenshots: [Home, Search]
    output_dir: ./captures
    render:
      slides:
        Home:
          appearance: dark
          caption: "Reviewed caption"
    app_store_connect:
      credentials: existing-private-credentials.yml
    upload: true
    """

    func testLegacyConfigurationFailsWithMigrationGuidance() throws {
        try withFile { path in
            try original.write(to: path, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try ConfigLoader().load(from: path.path)) { error in
                XCTAssertTrue(error.localizedDescription.contains("migrate-config"))
            }
            XCTAssertEqual(try String(contentsOf: path), original)
        }
    }

    func testMigrationPreservesOriginalAndAllCaptureSelections() throws {
        try withFile { path in
            try original.write(to: path, atomically: true, encoding: .utf8)
            let backup = try ConfigMigration.migrate(path: path.path)
            XCTAssertEqual(try String(contentsOfFile: backup), original)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup)[.posixPermissions] as? Int, 0o600)
            let settings = try ConfigLoader().load(from: path.path)
            XCTAssertEqual(settings.locales, ["en-US", "el", "zh-Hans"])
            XCTAssertEqual(settings.devices[0].tests, ["ScreenshotTests/testHome"])
            XCTAssertEqual(settings.screenshots, ["Home", "Search"])
            XCTAssertEqual(settings.screenshotAppearances, ["Home": "dark"])
            XCTAssertEqual(settings.outputDir, "captures")
            XCTAssertEqual(CaptureSelection.appearances(config: settings), ["light", "dark"])
            XCTAssertEqual(CaptureSelection.screenshots(config: settings, appearance: "light"), ["Search"])
            XCTAssertEqual(CaptureSelection.screenshots(config: settings, appearance: "dark"), ["Home"])
            let migrated = try String(contentsOf: path)
            XCTAssertThrowsError(try ConfigMigration.migrate(path: path.path))
            XCTAssertEqual(try String(contentsOf: path), migrated)
            XCTAssertEqual(try String(contentsOfFile: backup), original)
        }
    }

    func testInvalidAppearanceDoesNotChangeEitherFile() throws {
        try withFile { path in
            let invalid = original.replacingOccurrences(of: "appearance: dark", with: "appearance: sepia")
            try invalid.write(to: path, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try ConfigMigration.migrate(path: path.path))
            XCTAssertEqual(try String(contentsOf: path), invalid)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path + ".v3-backup"))
        }
    }

    func testCaptureLeaseRejectsOverlapAndCanBeReacquired() throws {
        let lock = FileManager.default.temporaryDirectory.appendingPathComponent("storescreens-test-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: lock) }
        let lease = try CaptureLease.acquire(at: lock)
        defer { lease.release() }
        XCTAssertThrowsError(try CaptureLease.acquire(at: lock))
        lease.release()
        let next = try CaptureLease.acquire(at: lock)
        next.release()
    }
}
