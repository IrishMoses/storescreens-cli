import Foundation

/// Runs `xcodebuild archive` and `xcodebuild -exportArchive` against a
/// user-pinned `DEVELOPER_DIR` (so a beta-selected xcode-select doesn't
/// leak into the build).
package actor ArchiveRunner {
    package let xcode: XcodeInstall
    package let logLevel: Logger.LogLevel
    package typealias RunXcodebuild = @Sendable (
        [String], [String: String], (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult
    private let runXcodebuild: RunXcodebuild

    package init(
        xcode: XcodeInstall,
        logLevel: Logger.LogLevel = .normal,
        runXcodebuild: @escaping RunXcodebuild = { args, env, handler in
            try await ShellRunner().run(
                "/usr/bin/xcodebuild", arguments: args,
                environment: env, stdoutLineHandler: handler
            )
        }
    ) {
        self.xcode = xcode
        self.logLevel = logLevel
        self.runXcodebuild = runXcodebuild
    }

    /// Runs `xcodebuild archive`.
    ///
    /// - Parameter destination: defaults to `generic/platform=iOS` (fastlane's default).
    /// - Parameter buildSettings: extra `KEY=VALUE` pairs appended after the
    ///   subcommand args. Used for things like
    ///   `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption=NO` to bake an export
    ///   compliance answer into the archived Info.plist.
    package func archive(
        project: String?,
        workspace: String?,
        scheme: String,
        configuration: String,
        destination: String,
        archivePath: String,
        derivedDataPath: String?,
        allowProvisioningUpdates: Bool,
        credentials: ASCCredentials? = nil,
        buildSettings: [String: String] = [:],
        lineHandler: (@Sendable (String) -> Void)? = nil
    ) async throws {
        var args: [String] = ["archive"]
        if let workspace {
            args += ["-workspace", workspace]
        } else if let project {
            args += ["-project", project]
        }
        args += ["-scheme", scheme]
        args += ["-configuration", configuration]
        args += ["-destination", destination]
        args += ["-archivePath", archivePath]
        if let derivedDataPath {
            args += ["-derivedDataPath", derivedDataPath]
        }
        let result = try await run(
            arguments: args,
            allowProvisioningUpdates: allowProvisioningUpdates,
            credentials: credentials,
            buildSettings: buildSettings,
            lineHandler: lineHandler
        )
        if logLevel == .verbose {
            print(result.stdout)
        }
        guard result.succeeded else {
            throw CLIError.archiveFailed(
                output: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
    }

    /// Runs `xcodebuild -exportArchive`, then returns the path to the
    /// produced `.ipa` inside `exportPath`.
    package func export(
        archivePath: String,
        exportPath: String,
        exportOptionsPlistPath: String,
        allowProvisioningUpdates: Bool,
        credentials: ASCCredentials? = nil,
        lineHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let args: [String] = [
            "-exportArchive",
            "-archivePath", archivePath,
            "-exportPath", exportPath,
            "-exportOptionsPlist", exportOptionsPlistPath,
        ]
        let result = try await run(
            arguments: args,
            allowProvisioningUpdates: allowProvisioningUpdates,
            credentials: credentials,
            lineHandler: lineHandler
        )
        if logLevel == .verbose {
            print(result.stdout)
        }
        guard result.succeeded else {
            throw CLIError.exportFailed(
                reason: result.stderr.isEmpty
                    ? String(result.stdout.suffix(500))
                    : String(result.stderr.suffix(500))
            )
        }

        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: exportPath)) ?? []
        guard let ipa = entries.first(where: { $0.hasSuffix(".ipa") }) else {
            throw CLIError.exportFailed(reason: "no .ipa produced in \(exportPath)")
        }
        return "\(exportPath)/\(ipa)"
    }

    /// Keep the resolved key available for the entire Xcode process, then
    /// remove it even when launching or running Xcode fails.
    private func run(
        arguments: [String],
        allowProvisioningUpdates: Bool,
        credentials: ASCCredentials?,
        buildSettings: [String: String] = [:],
        lineHandler: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        var args = arguments
        let fm = FileManager.default
        var keyDirectory: URL?
        defer {
            if let keyDirectory { try? fm.removeItem(at: keyDirectory) }
        }
        if allowProvisioningUpdates {
            args.append("-allowProvisioningUpdates")
            if let credentials {
                let dir = fm.temporaryDirectory
                    .appendingPathComponent("storescreens-xcode-\(UUID().uuidString)")
                keyDirectory = dir
                try fm.createDirectory(
                    at: dir, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let key = dir.appendingPathComponent("AuthKey.p8")
                try Data(credentials.privateKeyPEM.utf8).write(to: key, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
                args += [
                    "-authenticationKeyPath", key.path,
                    "-authenticationKeyID", credentials.keyID,
                    "-authenticationKeyIssuerID", credentials.issuerID,
                ]
            }
        }
        // Build settings come last so they override project defaults.
        for (key, value) in buildSettings.sorted(by: { $0.key < $1.key }) {
            args.append("\(key)=\(value)")
        }
        return try await runXcodebuild(args, ["DEVELOPER_DIR": xcode.developerDir], lineHandler)
    }
}
