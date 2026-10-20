import Foundation

package enum CaptureSelection {
    package static func appearances(config: CaptureConfig) -> [String] {
        var seen = Set<String>()
        return ((config.appearances ?? ["light", "dark"]) + (config.screenshotAppearances ?? [:]).values.sorted())
            .filter { seen.insert($0).inserted }
    }

    package static func screenshots(config: CaptureConfig, appearance: String) -> [String]? {
        guard let names = config.screenshots else { return nil }
        let defaults = config.appearances ?? ["light", "dark"]
        return names.filter { name in
            if let override = config.screenshotAppearances?[name] { return override == appearance }
            return defaults.contains(appearance)
        }
    }
}
