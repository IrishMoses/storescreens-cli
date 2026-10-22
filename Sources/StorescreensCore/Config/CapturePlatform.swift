import Foundation

package enum CapturePlatform: String, Sendable, CaseIterable {
    case iOS, watchOS, macOS

    package init?(configValue: String) {
        guard let value = Self.allCases.first(where: { $0.rawValue.lowercased() == configValue.lowercased() }) else { return nil }
        self = value
    }

    package var destinationName: String {
        self == .macOS ? "macOS" : "\(rawValue) Simulator"
    }

    package func destination(udid: String? = nil) -> String {
        if self == .macOS { return "platform=macOS,arch=arm64" }
        return udid.map { "platform=\(destinationName),id=\($0)" }
            ?? "generic/platform=\(destinationName)"
    }

    package var productsDirectory: String {
        switch self {
        case .iOS: return "Debug-iphonesimulator"
        case .watchOS: return "Debug-watchsimulator"
        case .macOS: return "Debug"
        }
    }

    package var deploymentTargetKey: String {
        switch self {
        case .iOS: return "IPHONEOS_DEPLOYMENT_TARGET"
        case .watchOS: return "WATCHOS_DEPLOYMENT_TARGET"
        case .macOS: return "MACOSX_DEPLOYMENT_TARGET"
        }
    }

    package var buildPlatformName: String {
        switch self {
        case .iOS: return "iphonesimulator"
        case .watchOS: return "watchsimulator"
        case .macOS: return "macosx"
        }
    }

    package var supportsSimulatorAppearance: Bool { self == .iOS }
    package var supportsStatusBarOverride: Bool { self == .iOS }

    package static func detect(in supportedPlatforms: [String]) -> CapturePlatform? {
        if supportedPlatforms.contains(where: { $0.hasPrefix("watch") }) { return .watchOS }
        if supportedPlatforms.contains(where: { $0.hasPrefix("iphone") }) { return .iOS }
        if supportedPlatforms.contains(where: { $0.hasPrefix("macos") }) { return .macOS }
        return nil
    }
}
