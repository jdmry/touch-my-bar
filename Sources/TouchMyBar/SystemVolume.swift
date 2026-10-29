import CoreAudio
import Foundation

/// Output volume and mute for the current default output device, through
/// CoreAudio rather than synthesised media keys — media keys would need
/// Accessibility permission, this needs none.
///
/// The device is looked up per call: default output changes when headphones
/// go in or a display is plugged, and a cached id would then adjust the
/// volume of something the user is no longer listening to.
enum SystemVolume {

    /// Matches the step macOS itself uses for the volume keys.
    static let step: Float = 1.0 / 16.0

    static func increase() { nudge(by: step) }
    static func decrease() { nudge(by: -step) }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = Self.address(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return false }
        return muted != 0
    }

    /// Returns the state it settled on, so the caller can update its icon.
    @discardableResult
    static func toggleMute() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let target: UInt32 = isMuted ? 0 : 1
        var address = Self.address(kAudioDevicePropertyMute)
        var value = target
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        return target != 0
    }

    static var level: Float {
        guard let device = defaultOutputDevice() else { return 0 }
        var address = Self.address(kAudioDevicePropertyVolumeScalar)
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr
        else { return 0 }
        return volume
    }

    // MARK: - Private

    private static func nudge(by delta: Float) {
        guard let device = defaultOutputDevice() else { return }

        var address = Self.address(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return }

        var volume = Float32(min(1, max(0, level + delta)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)

        // Either volume key unmutes, the way the hardware keys do — asking
        // for a volume at all means wanting to hear something.
        if isMuted {
            var muteAddress = Self.address(kAudioDevicePropertyMute)
            var off: UInt32 = 0
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &off)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }
}
