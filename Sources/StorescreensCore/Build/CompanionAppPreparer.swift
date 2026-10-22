import Foundation

/// Build a paired iPhone app with its own iOS destination before Watch tests.
package struct CompanionAppPreparer {
    package init() {}

    package func prepare(device: ResolvedDevice, config: CaptureConfig, derivedDataPath: String) async throws {
        guard let phone = device.companion, let scheme = device.companionScheme else { return }
        let runner = XcodeBuildRunner(codeSigningAllowed: config.codeSigningAllowed ?? false)
        let app = try await runner.build(
            project: config.project, workspace: config.workspace, scheme: scheme,
            destinationUDID: phone.udid, derivedDataPath: derivedDataPath, platform: .iOS
        )
        let manager = SimulatorManager()
        try await manager.install(phone.udid, appPath: app)
        let infoURL = URL(fileURLWithPath: app).appendingPathComponent("Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        guard let bundleID = info?["CFBundleIdentifier"] as? String else {
            throw CLIError.configInvalid(reason: "The companion app has no CFBundleIdentifier")
        }
        try await manager.launch(phone.udid, bundleId: bundleID, arguments: config.launchArguments ?? ["--uitesting"])
    }
}
