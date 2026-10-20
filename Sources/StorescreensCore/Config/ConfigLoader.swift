import Foundation
import Yams

package struct ConfigLoader {
    package init() {}

    package func load(from path: String) throws -> CaptureConfig {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.configNotFound(path: path)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()

        do {
            if let mapping = try Yams.load(yaml: contents) as? [String: Any] {
                let obsolete = ["render", "app_store_connect", "search_preview", "upload"].filter { mapping[$0] != nil }
                guard obsolete.isEmpty else {
                    throw CLIError.configInvalid(reason: "StoreScreens 4 only captures screenshots. Move \(obsolete.joined(separator: ", ")) to Koubou / ASC CLI configuration. Run 'storescreens migrate-config --config \(path)' to preserve the original configuration and write a capture-only file.")
                }
            }
            var config = try decoder.decode(CaptureConfig.self, from: contents)
            try Self.validate(config)
            // Normalize output_dir: strip leading "./" so relative paths like
            // "./storescreens-output" don't cause path resolution failures downstream.
            if config.outputDir.hasPrefix("./") {
                config.outputDir = String(config.outputDir.dropFirst(2))
            }
            return config
        } catch {
            throw CLIError.configInvalid(reason: error.localizedDescription)
        }
    }

    package func write(_ config: CaptureConfig, to path: String) throws {
        try Self.validate(config)
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
    }

    package static func validate(_ config: CaptureConfig) throws {
        guard !config.scheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.configInvalid(reason: "scheme must not be empty")
        }
        guard !config.outputDir.isEmpty, config.keepRuns.map({ $0 >= 0 }) ?? true else {
            throw CLIError.configInvalid(reason: "output_dir must not be empty and keep_runs must be nonnegative")
        }
        let appearances = config.appearances ?? ["light", "dark"]
        guard !appearances.isEmpty, appearances.allSatisfy({ ["light", "dark"].contains($0) }) else {
            throw CLIError.configInvalid(reason: "appearances must contain light and/or dark")
        }
        if let overrides = config.screenshotAppearances, !overrides.isEmpty {
            guard let names = config.screenshots, !names.isEmpty,
                  overrides.keys.allSatisfy({ names.contains($0) }),
                  overrides.values.allSatisfy({ ["light", "dark"].contains($0) }) else {
                throw CLIError.configInvalid(reason: "screenshot_appearances requires an explicit screenshots list, matching names, and light/dark values")
            }
        }
    }
}
