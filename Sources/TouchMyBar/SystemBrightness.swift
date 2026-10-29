import CoreGraphics
import Foundation

/// Built-in display brightness via DisplayServices, another private
/// framework. Resolved with dlsym rather than linked, so a macOS that drops
/// these symbols leaves the buttons inert instead of refusing to launch.
///
/// IOKit's `IODisplaySetFloatParameter` is the public-ish alternative, but
/// it does not drive the internal panel on Apple silicon.
enum SystemBrightness {

    /// Matches the step macOS itself uses for the brightness keys.
    static let step: Float = 1.0 / 16.0

    static var isAvailable: Bool { symbols != nil }

    static func increase() { nudge(by: step) }
    static func decrease() { nudge(by: -step) }

    static var level: Float {
        guard let symbols else { return 0 }
        var value: Float = 0
        guard symbols.get(CGMainDisplayID(), &value) == 0 else { return 0 }
        return value
    }

    // MARK: - Private

    private static func nudge(by delta: Float) {
        guard let symbols else { return }
        let target = min(1, max(0, level + delta))
        _ = symbols.set(CGMainDisplayID(), target)
    }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols {
        let get: GetBrightness
        let set: SetBrightness
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            NSLog("[TouchMyBar] DisplayServices brightness unavailable; buttons disabled.")
            return nil
        }
        return Symbols(get: unsafeBitCast(get, to: GetBrightness.self),
                       set: unsafeBitCast(set, to: SetBrightness.self))
    }()
}
