import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let action: String

    var errorDescription: String? {
        let bytes = withUnsafeBytes(of: status.bigEndian) { Array($0) }
        let code = bytes.allSatisfy({ (32...126).contains($0) })
            ? "'\(String(decoding: bytes, as: UTF8.self))'" : "\(status)"
        return "\(action) failed (\(code))"
    }
}

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, action: action) }
}

enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "Reading audio property")
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "Reading audio property")
        return value?.takeRetainedValue() as String? ?? ""
    }

    static func defaultOutputDevice() throws -> AudioObjectID {
        let device = try value(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
        guard device != kAudioObjectUnknown else { throw CoreAudioError(status: -1, action: "Finding the output device") }
        return device
    }

    /// The HAL's object for this process, so the tap can exclude our own output (avoids feedback).
    static func ownProcessObject() throws -> AudioObjectID {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object),
                  "Looking up Railgun's audio process")
        guard object != kAudioObjectUnknown else { throw CoreAudioError(status: -1, action: "Looking up Railgun's audio process") }
        return object
    }

    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
