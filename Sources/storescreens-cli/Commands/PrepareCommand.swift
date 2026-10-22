import ArgumentParser
import Foundation
import StorescreensCore

struct PrepareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "prepare", abstract: "Boot configured simulators, configure their status bars, and optionally install a simulator app.")
    @Option(name: .long, help: "Capture configuration path.") var config = "storescreens.yml"
    @Option(name: .long, help: "Simulator .app bundle to install on each configured simulator.") var app: String?
    @Option(name: .long, help: "Set light or dark appearance.") var appearance: String?

    mutating func validate() throws {
        if let appearance, !["light", "dark"].contains(appearance) { throw ValidationError("--appearance must be light or dark") }
        if let app, !FileManager.default.fileExists(atPath: app) { throw ValidationError("App bundle does not exist: \(app)") }
    }

    func run() async throws {
        let settings = try ConfigLoader().load(from: config)
        guard !settings.devices.isEmpty else { throw CLIError.noDevicesConfigured }
        let manager = SimulatorManager()
        let devices = try await manager.resolveDevices(settings.devices)
        if appearance == "light", devices.contains(where: \.isWatchOS) {
            throw CLIError.configInvalid(reason: "watchOS captures use dark appearance")
        }
        let derivedData = ((settings.derivedDataPath ?? ".storescreens-cache/DerivedData") as NSString).expandingTildeInPath
        for device in devices where !device.isMacOS {
            try await manager.bootForCapture(device)
            if let scheme = device.companionScheme { print("Preparing iPhone companion: \(scheme)") }
            try await CompanionAppPreparer().prepare(
                device: device, config: settings,
                derivedDataPath: (derivedData as NSString).appendingPathComponent("Companion")
            )
            if device.platform == .iOS { try await manager.disableHardwareKeyboard(device.udid) }
            if let appearance, device.platform.supportsSimulatorAppearance { try await manager.setAppearance(appearance, udid: device.udid) }
            if device.platform.supportsStatusBarOverride, let arguments = StatusBarKeeper.arguments(for: settings) { try await manager.overrideStatusBar(device.udid, arguments: arguments) }
            if let app { try await manager.install(device.udid, appPath: URL(fileURLWithPath: app).path) }
            print("Ready: \(device.simulatorName) (\(device.udid))")
        }
    }
}
