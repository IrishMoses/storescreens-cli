import Foundation
import Darwin

/// The test harness uses shared breadcrumb and locale files in the user's home.
/// Refuse overlapping capture runs rather than mix their screenshots or settings.
package final class CaptureLease {
    private var descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    package static func acquire(at lockURL: URL? = nil) throws -> CaptureLease {
        let path = (lockURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".storescreens-capture.lock")).path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CLIError.configInvalid(reason: "Cannot open capture lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw CLIError.configInvalid(reason: "Another StoreScreens capture is running. Wait for it to finish before starting another.")
        }
        return CaptureLease(descriptor: descriptor)
    }

    package func release() {
        if descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            descriptor = -1
        }
    }
    deinit { release() }
}
