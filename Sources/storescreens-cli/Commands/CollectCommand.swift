import ArgumentParser
import Foundation
import StorescreensCore

struct CollectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "collect", abstract: "Collect named screenshot attachments from an existing .xcresult bundle.")
    @Option(name: .long, help: "Existing .xcresult bundle.") var resultBundle: String
    @Option(name: .long, help: "Simulator used to run the tests.") var simulator: String
    @Option(name: .long, help: "Output directory for PNGs and manifest.json.") var output = "storescreens-output"
    @Option(name: .long, help: "Scheme recorded in the manifest.") var scheme = "Screenshots"
    @Option(name: .long, help: "Locale used during capture.") var locale: String?
    @Option(name: .long, help: "Appearance used during capture.") var appearance: String?

    mutating func validate() throws {
        guard FileManager.default.fileExists(atPath: resultBundle) else { throw ValidationError("Result bundle does not exist: \(resultBundle)") }
        if let appearance, !["light", "dark"].contains(appearance) { throw ValidationError("--appearance must be light or dark") }
    }

    func run() async throws {
        let lease = try CaptureLease.acquire()
        defer { lease.release() }
        let manager = SimulatorManager()
        guard let device = try await manager.resolveDevices([DeviceConfig(simulator: simulator)]).first else { throw CLIError.noDevicesConfigured }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("storescreens-collect-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let attachments = try await XCResultParser().exportAttachments(resultBundlePath: resultBundle, outputPath: temporary.appendingPathComponent("attachments").path)
        let outputURL = URL(fileURLWithPath: output)
        let history = RunHistoryManager(outputDir: outputURL.path, keepRuns: 1, logger: Logger())
        let destination = try history.prepareCaptureDirectory()
        do {
            let organizer = OutputOrganizer()
            let groups = try await organizer.organize(attachments: attachments, rawExportDir: temporary.appendingPathComponent("attachments").path, outputDir: destination.writeDir, device: device, locale: locale, appearance: appearance, screenshotFilter: nil)
            guard groups.screenshotCount > 0 else { throw CLIError.noScreenshotsFound(device: simulator) }
            let captured = CaptureManifest(version: 2, generatedAt: Date(), generatedBy: "storescreens-cli \(storescreensVersion)", appName: scheme, displayName: nil, scheme: scheme, devices: groups.map {
                CaptureManifest.DeviceCapture(deviceType: $0.size.deviceTypeRawValue, simulatorName: simulator, locale: locale, appearance: appearance, screenshots: $0.screenshots)
            })
            let existing = try CaptureManifest.load(fromOutputDir: outputURL.path)
            let manifest = captured.merged(over: existing, scope: CaptureScope(someScreenshotsOnly: true))
            try organizer.writeManifest(manifest, to: destination.writeDir)
            try history.finalizeCapture(destination)
            try HTMLPreviewGenerator().generate(manifest: manifest, outputDir: outputURL.path)
            print("Collected \(groups.screenshotCount) screenshots. Manifest: \(outputURL.appendingPathComponent("manifest.json").path)")
        } catch {
            history.handleFailure(destination)
            throw error
        }
    }
}
