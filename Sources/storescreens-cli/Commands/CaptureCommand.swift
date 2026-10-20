import ArgumentParser
import Foundation
import StorescreensCore

extension CaptureMode: ExpressibleByArgument {}

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "capture", abstract: "Run XCUITests and collect raw screenshots across configured devices and locales.")
    @Option(name: .long, help: "Capture mode: xctest or simple.") var mode: CaptureMode = .xctest
    @Option(name: .long, help: "Capture configuration path.") var config = "storescreens.yml"
    @Option(name: .long, help: "Override output directory.") var output: String?
    @Option(name: .long, help: "Override Xcode project path.") var project: String?
    @Option(name: .long, help: "Override Xcode workspace path.") var workspace: String?
    @Option(name: .long, help: "Override Xcode scheme.") var scheme: String?
    @Option(name: .long, help: "Limit locales; repeat for multiple locales.") var locale: [String] = []
    @Option(name: .long, help: "Limit appearances; repeat for light and dark.") var appearance: [String] = []
    @Option(name: .long, help: "Retries after a failed device run.") var retries = 1
    @Option(name: .long, help: "Only collect names matching comma-separated prefixes.") var only: String?
    @Option(name: .long, help: "Reuse this DerivedData directory.") var derivedDataPath: String?
    @Option(name: .long, help: "Keep .xcresult bundles for later collection and diagnosis.") var resultBundleDir: String?
    @Flag(name: .long, help: "Run one device at a time.") var noParallel = false
    @Flag(name: .long, help: "Keep simulators booted after simple capture.") var keepAlive = false
    @Flag(name: .long, help: "Export XCTAttachments instead of collecting filesystem PNGs.") var xcresult = false
    @Flag(name: .long, help: "Skip capture source checks.") var skipCheck = false
    @Flag(name: .long, help: "Stream xcodebuild output.") var verbose = false

    mutating func validate() throws {
        guard retries >= 0 else { throw ValidationError("--retries must be nonnegative") }
        guard only.map({ !$0.split(separator: ",").isEmpty }) ?? true else { throw ValidationError("--only requires a screenshot prefix") }
    }

    func run() async throws {
        var settings = try ConfigLoader().load(from: config)
        if let output { settings.outputDir = output }
        if let project { settings.project = project; settings.workspace = nil }
        if let workspace { settings.workspace = workspace; settings.project = nil }
        if let scheme { settings.scheme = scheme }
        if !locale.isEmpty { settings.locales = locale }
        if !appearance.isEmpty { settings.appearances = appearance }
        if let derivedDataPath { settings.derivedDataPath = derivedDataPath }
        if let resultBundleDir { settings.resultBundleDir = resultBundleDir }
        if verbose { settings.logLevel = "verbose" }
        if skipCheck { settings.preflight = false }
        let scope = CaptureScope(locales: locale, appearances: appearance, someScreenshotsOnly: only != nil)
        let result = try await CaptureOrchestrator().run(config: settings, mode: mode, xcresult: xcresult, noParallel: noParallel, retries: retries, keepAlive: keepAlive, only: only, scope: scope) { event in
            switch event {
            case .phase(let message): if !message.hasPrefix("logDir:") { print(message) }
            case .deviceLog(let device, let message): print("[\(device)] \(message)")
            case .screenshotCaptured(let device, _, let name, _): print("[\(device)] Captured \(name)")
            case .deviceCompleted(let device, let count): print("[\(device)] Collected \(count) screenshots")
            case .deviceFailed(let device, let error): print("[\(device)] Failed: \(error)")
            case .preflightFinding(let rule, _, let message): print("[\(rule)] \(message)")
            }
        }
        print("Manifest: \(result.outputDir.appendingPathComponent("manifest.json").path)")
        print("Use raw PNGs with 'kou generate'; use 'asc screenshots upload' for App Store Connect.")
    }
}
