import AppKit

/// Feedback when a bar control is used: a tap through the trackpad's Taptic
/// Engine, a click sound, or both.
///
/// The Touch Bar has no actuator of its own, so the tap is felt in the palm
/// rest rather than under the finger. A click sound covers a lot of that
/// distance — hearing the click is most of what makes a press feel real —
/// which is why both are offered and both are switchable.
enum Haptics {

    /// How hard the tap should feel.
    ///
    /// The actuator accepts pattern ids 1-6, 15 and 16, but they are
    /// patterns rather than a volume dial, and nothing in the set lands
    /// harder than 6. Repeating 6 to fake a stronger tap just read as a
    /// rattle, so there are two honest settings and no third.
    ///
    /// Raw values are menu tags and persist in defaults; they are offset so
    /// an older stored actuation id cannot be mistaken for one.
    enum Strength: Int, CaseIterable {
        case light = 101
        case strong = 102

        var title: String {
            switch self {
            case .light: return "Light"
            case .strong: return "Strong"
            }
        }

        var actuationID: Int32 {
            switch self {
            case .light: return 3
            case .strong: return 6
            }
        }
    }

    // MARK: - Settings

    private enum Key {
        static let haptics = "hapticFeedbackEnabled"
        static let sound = "clickSoundEnabled"
        static let strength = "hapticStrength"
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.haptics) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.haptics) }
    }

    static var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.sound) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.sound) }
    }

    static var strength: Strength {
        get {
            let raw = UserDefaults.standard.object(forKey: Key.strength) as? Int
            return raw.flatMap(Strength.init(rawValue:)) ?? .strong
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.strength) }
    }

    // MARK: - Firing

    static func tap() {
        if isEnabled { Actuator.shared.actuate(strength.actuationID) }
        if isSoundEnabled { Click.play() }
    }
}

/// The trackpad's haptic actuator, through MultitouchSupport.
///
/// AppKit's NSHapticFeedbackManager only exposes three fixed patterns and
/// the gentlest of them is easy to miss through the palm rest. This private
/// interface drives the same hardware directly and harder. It is kept open
/// between taps because opening costs milliseconds; the fallback is AppKit
/// if any of it is unavailable.
private final class Actuator {

    static let shared = Actuator()

    private typealias CreateList = @convention(c) () -> CFArray?
    private typealias GetDeviceID = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias Create = @convention(c) (UInt64) -> UnsafeRawPointer?
    private typealias Open = @convention(c) (UnsafeRawPointer) -> Int32
    private typealias IsOpen = @convention(c) (UnsafeRawPointer) -> Bool
    private typealias Actuate = @convention(c) (UnsafeRawPointer, Int32, UInt32, Float, Float) -> Int32

    private var actuator: UnsafeRawPointer?
    private var open: Open?
    private var isOpen: IsOpen?
    private var actuate: Actuate?

    init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let createListSymbol = dlsym(handle, "MTDeviceCreateList"),
              let getIDSymbol = dlsym(handle, "MTDeviceGetDeviceID"),
              let createSymbol = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSymbol = dlsym(handle, "MTActuatorOpen"),
              let isOpenSymbol = dlsym(handle, "MTActuatorIsOpen"),
              let actuateSymbol = dlsym(handle, "MTActuatorActuate")
        else { return }

        let createList = unsafeBitCast(createListSymbol, to: CreateList.self)
        let getDeviceID = unsafeBitCast(getIDSymbol, to: GetDeviceID.self)
        let create = unsafeBitCast(createSymbol, to: Create.self)

        open = unsafeBitCast(openSymbol, to: Open.self)
        isOpen = unsafeBitCast(isOpenSymbol, to: IsOpen.self)
        actuate = unsafeBitCast(actuateSymbol, to: Actuate.self)

        // Several multitouch devices are listed; only the trackpad has an
        // actuator, so take the first that yields one.
        guard let devices = createList() as? [AnyObject] else { return }
        for device in devices {
            var identifier: UInt64 = 0
            guard getDeviceID(Unmanaged.passUnretained(device).toOpaque(), &identifier) == 0 else { continue }
            if let candidate = create(identifier) {
                actuator = candidate
                _ = open?(candidate)
                break
            }
        }
    }

    func actuate(_ actuationID: Int32) {
        guard let actuator, let actuate else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }

        // Sleep and device changes can close it behind our back.
        if isOpen?(actuator) == false { _ = open?(actuator) }

        _ = actuate(actuator, actuationID, 0, 0, 0)
    }
}

/// A short click, played at low volume so it reads as a key press rather
/// than an alert.
private enum Click {

    private static let sound: NSSound? = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.volume = 0.35
        return sound
    }()

    static func play() {
        guard let sound else { return }
        // Restart rather than overlap, so a held repeat does not pile up.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
