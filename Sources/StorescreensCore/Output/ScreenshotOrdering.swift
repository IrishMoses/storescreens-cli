import Foundation

package enum ScreenshotOrdering {
    package static func apply(_ shots: [CaptureManifest.Screenshot], order: [String]?) -> [CaptureManifest.Screenshot] {
        guard let order, !order.isEmpty else { return shots }
        let byName = Dictionary(shots.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var taken = Set<String>()
        var result: [CaptureManifest.Screenshot] = []
        for name in order where taken.insert(name).inserted {
            if let shot = byName[name] { result.append(shot) }
        }
        result.append(contentsOf: shots.filter { !taken.contains($0.name) })
        return result
    }
}
