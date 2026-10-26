import Foundation
import CoreAudio
import AppKit

func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress { .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain) }
func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T) -> T {
    var a = address(selector); var result = value; var size = UInt32(MemoryLayout<T>.size)
    _ = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }; return result
}
func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var a = address(selector); var value: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
    return status == noErr ? value as String : ""
}
func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = address(selector); var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var result = [AudioObjectID](repeating: 0, count: Int(size)/4)
    let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
    return status == noErr ? result : []
}
struct OutputDevice: Identifiable, Hashable { let id: String; let object: AudioObjectID; let name: String }
func outputDevices() -> [OutputDevice] {
    objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id in
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return nil }
        let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
        guard !uid.hasPrefix("suara.") && !uid.hasPrefix("soundhoreg.") else { return nil }
        return OutputDevice(id: uid, object: id, name: stringProperty(id, kAudioObjectPropertyName))
    }
}
struct AudioFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
func check(_ status: OSStatus, _ step: String) throws { if status != noErr { throw AudioFailure(message: "\(step) (\(status)). Periksa izin System Audio Recording di Settings → Privacy & Security.") } }

final class AppChannel {
    var tap: AudioObjectID = 0; var aggregate: AudioObjectID = 0; var proc: AudioDeviceIOProcID?
    let dsp = suara_create()!
    var rate: Float = 48000
    init(processes: [AudioObjectID], output: OutputDevice, source: OutputDevice? = nil, settings: ChannelSettings, gain: Double) throws {
        do {
            let desc = CATapDescription(processes: processes, deviceUID: (source ?? output).id, stream: 0)
            desc.name = "SoundHoreg channel"; desc.isPrivate = true; desc.muteBehavior = gain == 0 ? .muted : .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(desc, &tap), "Membuka audio aplikasi")
            if gain == 0 { return }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "SoundHoreg channel", kAudioAggregateDeviceUIDKey: "soundhoreg.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: output.id,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.id]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: false]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Membuat jalur audio")
            var a = address(kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeOutput)
            var format = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout.size(ofValue: format))
            try check(AudioObjectGetPropertyData(aggregate, &a, 0, nil, &size, &format), "Membaca format output")
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { throw AudioFailure(message: "Format output belum didukung. Pilih speaker atau headphone lain.") }
            rate = Float(format.mSampleRate)
            var tapFormat = AudioStreamBasicDescription(); var ta = address(kAudioTapPropertyFormat); size = UInt32(MemoryLayout.size(ofValue: tapFormat))
            try check(AudioObjectGetPropertyData(tap, &ta, 0, nil, &size, &tapFormat), "Membaca format aplikasi")
            guard (1...2).contains(tapFormat.mChannelsPerFrame), tapFormat.mBitsPerChannel == 32, tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { throw AudioFailure(message: "Format audio aplikasi belum didukung.") }
            suara_input_channels(dsp, tapFormat.mChannelsPerFrame)
            try check(AudioDeviceCreateIOProcID(aggregate, { d, n, i, it, o, ot, c in suara_render(d, n, i, it, o, ot, c) }, UnsafeMutableRawPointer(dsp), &proc), "Menyiapkan pemrosesan audio")
            update(settings, gain: gain)
            try check(AudioDeviceStart(aggregate, proc), "Mengaktifkan audio")
        } catch { stop(); throw error }
    }
    func update(_ settings: ChannelSettings, gain: Double) { suara_set(dsp, Float(gain), Float(settings.pan), Float(settings.bass), Float(settings.treble), settings.mono ? 1 : 0, rate) }
    func stop() { if let p = proc { AudioDeviceStop(aggregate, p); AudioDeviceDestroyIOProcID(aggregate, p); proc = nil }; if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }; if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 } }
    deinit { stop(); suara_free(dsp) }
}
