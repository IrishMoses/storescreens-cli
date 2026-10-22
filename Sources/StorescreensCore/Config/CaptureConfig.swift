import Foundation

package struct CaptureConfig: Codable {
    package var project: String?
    package var workspace: String?
    package var scheme: String

    package var devices: [DeviceConfig]

    package var locales: [String]?
    package var appearances: [String]?
    package var screenshots: [String]?
    package var outputDir: String
    package var testTarget: String?
    package var testClass: String?
    package var launchArguments: [String]?
    package var keepRuns: Int?

    /// Run the test suite twice per device. The first run is discarded (warmup) and the second captures the real screenshots.
    /// Useful for apps that need one full launch cycle to finish seeding or loading data (e.g. CloudKit, ODR).
    /// Default: false.
    package var warmupRun: Bool?

    /// Override the simulator status bar for clean screenshots.
    /// When true, applies a clean status bar (9:41 AM, full battery/signal).
    /// Default: true. Set to false to disable.
    package var statusBar: Bool?

    /// Custom arguments for `xcrun simctl status_bar override`.
    /// Only used when `statusBar` is true.
    /// Default: "--time 9:41 --dataNetwork lte+ --cellularMode active --cellularBars 4 --batteryState charging --batteryLevel 90 --operatorName TELUS"
    package var statusBarArguments: String?

    /// Run preflight source code check before capture.
    /// Default: true. Set to false to disable auto-check.
    package var preflight: Bool?

    /// Dismiss system alerts (e.g. App Store review prompts) during testing.
    /// Default: true. Set to false to allow review prompts and other system alerts.
    package var dismissSystemAlerts: Bool?

    /// Log level: "quiet", "normal", or "verbose".
    /// Default: "normal". Set to "verbose" to see xcodebuild output, or "quiet" for errors/warnings only.
    package var logLevel: String?

    /// Path to a persistent DerivedData directory for faster incremental builds.
    /// When set, DerivedData is reused across runs and not deleted after capture.
    /// When nil, a temporary directory is used and cleaned up after each run.
    package var derivedDataPath: String?

    /// Keep simulator signing for apps whose Keychain or app-group access requires entitlements.
    /// Default: false, preserving the unsigned capture behavior.
    package var codeSigningAllowed: Bool?

    /// Keep .xcresult bundles here for later collection and failure diagnosis.
    /// Each invocation receives a unique subdirectory. Nil uses temporary bundles.
    package var resultBundleDir: String?

    /// Keep older preview pages on the index card grid under a
    /// "From older runs" heading. Older pages are the `preview_*.html`
    /// files left behind by a previous capture whose device/appearance
    /// combo isn't in the current run.
    /// Default: false. A fresh capture wipes stale preview files so the
    /// index is a clean picture of the latest run. Set to true when you
    /// want the gallery to accumulate history across runs (e.g. you
    /// captured an iPhone-only run yesterday and an iPad-only run today
    /// and want to see both cards at once).
    package var keepOldPreviews: Bool?

    /// Custom locale-to-flag mappings for the HTML preview gallery.
    /// Keys are Xcode locale codes (e.g., "en-GB", "es-419"). Values are either:
    ///   - A filename (without .svg) from ciscoriordan/svg-flags/circle/languages/, e.g. "in-en"
    ///   - A full https:// URL, used as-is
    /// Merged with built-in defaults; user values win over built-in on key collisions.
    package var localeFlags: [String: String]?

    /// Screenshot-specific appearance overrides, independent of rendering.
    /// Requires an explicit screenshots list so captures are reproducible.
    package var screenshotAppearances: [String: String]?

    package init(scheme: String, devices: [DeviceConfig], outputDir: String) {
        self.scheme = scheme
        self.devices = devices
        self.outputDir = outputDir
    }

    package enum CodingKeys: String, CodingKey {
        case project, workspace, scheme, devices, locales, appearances, screenshots
        case outputDir = "output_dir"
        case testTarget = "test_target"
        case testClass = "test_class"
        case launchArguments = "launch_arguments"
        case keepRuns = "keep_runs"
        case warmupRun = "warmup_run"
        case statusBar = "status_bar"
        case statusBarArguments = "status_bar_arguments"
        case preflight
        case dismissSystemAlerts = "dismiss_system_alerts"
        case logLevel = "log_level"
        case derivedDataPath = "derived_data_path"
        case codeSigningAllowed = "code_signing_allowed"
        case resultBundleDir = "result_bundle_dir"
        case keepOldPreviews = "keep_old_previews"
        case localeFlags = "locale_flags"
        case screenshotAppearances = "screenshot_appearances"
    }
}

package struct DeviceConfig: Codable, Sendable {
    package var simulator: String
    package var size: String?
    /// Platform for this device: "iOS", "watchOS", or "macOS".
    /// Simulator platforms are inferred from the device when omitted.
    /// When "macOS", tests run natively on the Mac instead of in a simulator.
    package var platform: String?
    /// iPhone simulator to pair with a watchOS device that needs a companion.
    package var companion: String?
    /// Optional iOS scheme to build, install, and launch on the companion.
    package var companionScheme: String?
    /// Per-device test selection. When non-nil, xcodebuild runs only these
    /// tests on this device, overriding the top-level `test_class` filter.
    ///
    /// Each entry is interpreted relative to the top-level `test_target`:
    ///   - "testFoo"         -> `test_target/test_class/testFoo` (needs test_class set)
    ///   - "ClassName/test"  -> `test_target/ClassName/test` (explicit class override)
    ///   - "ClassName"       -> `test_target/ClassName` (whole class)
    ///   - "Target/Cls/test" -> passed through verbatim (fully qualified)
    ///
    /// Use this to restrict iPad-only or iPhone-only test methods to their
    /// platform, so a test that only renders meaningfully on one form factor
    /// doesn't run on the other and produce a degraded screenshot. When nil,
    /// the device inherits the top-level test_target/test_class behavior.
    package var tests: [String]?

    package init(
        simulator: String,
        size: String? = nil,
        platform: String? = nil,
        companion: String? = nil,
        companionScheme: String? = nil,
        tests: [String]? = nil
    ) {
        self.simulator = simulator
        self.size = size
        self.platform = platform
        self.companion = companion
        self.companionScheme = companionScheme
        self.tests = tests
    }

    package var isMacOS: Bool {
        platform?.lowercased() == "macos"
    }

    package enum CodingKeys: String, CodingKey {
        case simulator, size, platform, companion, tests
        case companionScheme = "companion_scheme"
    }
}

/// Turn a per-device `tests:` list into fully-qualified xcodebuild
/// `-only-testing` selectors, using the top-level test_target/test_class as
/// defaults for short-form entries. Shared by the CLI and the core
/// orchestrator so both capture paths resolve the same way.
///
/// Entry forms:
///   - "testFoo"          -> `<target>/<class>/testFoo` (both defaults required)
///   - "Class/test"       -> `<target>/Class/test`
///   - "Class"            -> `<target>/Class`
///   - "Target/Cls/test"  -> passed through verbatim
///
/// Returns nil when `entries` is nil or empty, so callers fall back to the
/// top-level target/class collapse.
package func resolvedTestSelectors(
    entries: [String]?,
    testTarget: String?,
    testClass: String?
) -> [String]? {
    guard let entries, !entries.isEmpty else { return nil }
    return entries.map { entry in
        let slashCount = entry.filter { $0 == "/" }.count
        switch slashCount {
        case 0:
            if let target = testTarget, let cls = testClass {
                return "\(target)/\(cls)/\(entry)"
            } else if let target = testTarget {
                return "\(target)/\(entry)"
            }
            return entry
        case 1:
            if let target = testTarget {
                return "\(target)/\(entry)"
            }
            return entry
        default:
            return entry
        }
    }
}
