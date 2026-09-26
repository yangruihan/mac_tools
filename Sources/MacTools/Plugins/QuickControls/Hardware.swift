import CoreAudio
import AudioToolbox
import CoreGraphics
import Darwin

enum Hardware {
    static func read(audio: Bool) throws -> Double {
        if audio {
            var device = AudioDeviceID(0)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { throw Failure.message("无法读取输出设备") }
            address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value: Float32 = 0
            size = UInt32(MemoryLayout.size(ofValue: value))
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { throw Failure.message("无法读取音量") }
            return Double(value) * 100
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success,
              let display = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { throw Failure.message("无法读取内置屏幕亮度") }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { throw Failure.message("亮度读取接口不可用") }
        typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        var value: Float = 0
        guard unsafeBitCast(symbol, to: Getter.self)(display, &value) == 0 else { throw Failure.message("亮度读取失败") }
        return Double(value) * 100
    }

    static func apply(_ value: Double, audio: Bool) throws {
        if audio {
            var device = AudioDeviceID(0)
            var size = UInt32(MemoryLayout.size(ofValue: device))
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { throw Failure.message("找不到默认音频输出设备") }
            address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { throw Failure.message("此输出设备不支持系统音量控制，请使用设备旋钮") }
            var scalar = Float32(value / 100)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: scalar)), &scalar)
            guard status == noErr else { throw Failure.message("音量设置失败：\(status)") }
        } else {
            var displays = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            guard CGGetActiveDisplayList(16, &displays, &count) == .success,
                  let display = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { throw Failure.message("没有内置显示器；暂不支持外接屏亮度") }
            guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { throw Failure.message("系统亮度接口不可用") }
            defer { dlclose(handle) }
            guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { throw Failure.message("系统亮度接口不可用") }
            typealias Setter = @convention(c) (UInt32, Float) -> Int32
            let status = unsafeBitCast(symbol, to: Setter.self)(display, Float(value / 100))
            guard status == 0 else { throw Failure.message("亮度设置失败：\(status)") }
        }
    }
}

