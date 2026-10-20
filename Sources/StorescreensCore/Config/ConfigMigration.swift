import Foundation
import Yams

/// Converts configuration without discarding reviewed rendering copy or credentials.
package enum ConfigMigration {
    package static func migrate(path: String) throws -> String {
        let original = try String(contentsOfFile: path, encoding: .utf8)
        guard var mapping = try Yams.load(yaml: original) as? [String: Any] else {
            throw CLIError.configInvalid(reason: "Expected a YAML mapping")
        }
        let backup = path + ".v3-backup"
        guard !FileManager.default.fileExists(atPath: backup) else {
            throw CLIError.configInvalid(reason: "\(backup) already exists; it will not be overwritten")
        }
        if let render = mapping["render"] as? [String: Any],
           let slides = render["slides"] as? [String: [String: Any]] {
            var appearances = mapping["screenshot_appearances"] as? [String: String] ?? [:]
            for (name, slide) in slides where appearances[name] == nil {
                if let appearance = slide["appearance"] as? String { appearances[name] = appearance }
            }
            if !appearances.isEmpty { mapping["screenshot_appearances"] = appearances }
        }
        for key in ["render", "app_store_connect", "search_preview", "upload"] { mapping.removeValue(forKey: key) }
        let yaml = try Yams.dump(object: mapping, sortKeys: true)
        let decoded = try YAMLDecoder().decode(CaptureConfig.self, from: yaml)
        try ConfigLoader.validate(decoded)
        try original.write(toFile: backup, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup)
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        return backup
    }
}
