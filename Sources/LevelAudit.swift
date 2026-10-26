import Foundation
import AVFAudio
import CoreAudio

// Only our own synthetic signal is measured. No other application's audio is sampled.
func runLevelAudit() -> String {
    let engine = AVAudioEngine()
    let state = UnsafeMutablePointer<Double>.allocate(capacity: 2)
    state.initialize(repeating: 0, count: 2)
    defer { engine.stop(); state.deinitialize(count: 2); state.deallocate() }
    let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return "FAIL: no output format" }
    let node = AVAudioSourceNode { _, _, frames, output in
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        for frame in 0..<Int(frames) {
            let v = Float(sin(state[0]) * 0.02)
            state[0] += 2 * .pi * 997 / rate
            if state[0] > 2 * .pi { state[0] -= 2 * .pi }
            for buffer in buffers { if let data = buffer.mData { data.assumingMemoryBound(to: Float.self)[frame] = v } }
        }
        return noErr
    }
    engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
    // Keep playback silent until our tap has muted the original route.
    engine.mainMixerNode.outputVolume = 0
    do { try engine.start() } catch { return "FAIL engine: \(error)" }
    Thread.sleep(forTimeInterval: 0.15)
    let own = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).filter { scalar($0, kAudioProcessPropertyPID, default: pid_t(0)) == getpid() }
    let outID: AudioObjectID = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, default: 0)
    let uid = stringProperty(outID, kAudioDevicePropertyDeviceUID)
    var report = "Level audit; device=\(stringProperty(outID, kAudioObjectPropertyName)); rate=\(rate); source sine peak=0.02 RMS=0.0141421356; ownProcesses=\(own)\n"
    guard !own.isEmpty else { return report + "FAIL no own audio process" }
    for direct in [false, true] {
        var tap: AudioObjectID = 0; var aggregate: AudioObjectID = 0; var proc: AudioDeviceIOProcID?
        let stats = audit_stats_create()!
        defer {
            engine.mainMixerNode.outputVolume = 0
            if let proc { AudioDeviceStop(aggregate, proc); AudioDeviceDestroyIOProcID(aggregate, proc) }
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
            if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
            audit_stats_free(stats)
        }
        let desc = direct ? CATapDescription(processes: own, deviceUID: uid, stream: 0) : CATapDescription(stereoMixdownOfProcesses: own)
        desc.isPrivate = true; desc.muteBehavior = .muted; desc.name = "SoundHoreg local level test"
        do {
            try check(AudioHardwareCreateProcessTap(desc, &tap), "audit tap")
            let config: [String: Any] = [kAudioAggregateDeviceNameKey: "SoundHoreg audit", kAudioAggregateDeviceUIDKey: "suara.audit.\(UUID())", kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceMainSubDeviceKey: uid, kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]], kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "audit aggregate")
            try check(AudioDeviceCreateIOProcID(aggregate, { d,n,i,it,o,ot,c in audit_render(d,n,i,it,o,ot,c) }, UnsafeMutableRawPointer(stats), &proc), "audit callback")
            try check(AudioDeviceStart(aggregate, proc), "audit start")
            engine.mainMixerNode.outputVolume = 1
            Thread.sleep(forTimeInterval: 1)
            engine.mainMixerNode.outputVolume = 0
            report += "\(direct ? "device-stream" : "stereo-mixdown"): peak=\(audit_stats_peak(stats)), rms=\(audit_stats_rms(stats)), frames=\(audit_stats_frames(stats))\n"
        } catch { report += "FAIL \(error)\n" }
    }
    return report
}

func runRoundTripAudit() -> String {
    let task = Process(); let input = Pipe()
    task.executableURL = Bundle.main.resourceURL?.appendingPathComponent("AuditTone")
    task.standardInput = input; task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return "roundtrip FAIL launch: \(error)" }
    defer { try? input.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8)); input.fileHandleForWriting.closeFile(); if task.isRunning { task.terminate() }; task.waitUntilExit() }
    Thread.sleep(forTimeInterval: 0.5)
    let source = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).filter { scalar($0, kAudioProcessPropertyPID, default: pid_t(0)) == task.processIdentifier }
    let outputID: AudioObjectID = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, default: 0)
    guard !source.isEmpty, let device = outputDevices().first(where: { $0.object == outputID }) else { return "roundtrip FAIL no test source or device" }
    var report = "\nRoundtrip measurement: source process → app DSP → parent process tap. Expected peak=0.02 × gain.\n"
    do {
        var settings = ChannelSettings(); settings.controlled = true
        let channel = try AppChannel(processes: source, output: device, settings: settings, gain: 1)
        defer { channel.stop() }
        let own = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).filter { scalar($0, kAudioProcessPropertyPID, default: pid_t(0)) == getpid() }
        for gain in [0.5, 1.0, 2.0] {
            channel.update(settings, gain: gain)
            var tap: AudioObjectID = 0; var aggregate: AudioObjectID = 0; var proc: AudioDeviceIOProcID?
            let stats = audit_stats_create()!
            defer { try? input.fileHandleForWriting.write(contentsOf: Data("pause\n".utf8)); if let proc { AudioDeviceStop(aggregate, proc); AudioDeviceDestroyIOProcID(aggregate, proc) }; if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }; if tap != 0 { AudioHardwareDestroyProcessTap(tap) }; audit_stats_free(stats) }
            let desc = CATapDescription(stereoMixdownOfProcesses: own); desc.isPrivate = true; desc.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(desc, &tap), "roundtrip observer")
            // Observer silences our test's replay. The child is also muted by AppChannel.
            let config: [String: Any] = [kAudioAggregateDeviceNameKey: "SoundHoreg roundtrip audit", kAudioAggregateDeviceUIDKey: "suara.audit.\(UUID())", kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceMainSubDeviceKey: device.id, kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.id]], kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString]]]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "roundtrip aggregate")
            try check(AudioDeviceCreateIOProcID(aggregate, { d,n,i,it,o,ot,c in audit_render(d,n,i,it,o,ot,c) }, UnsafeMutableRawPointer(stats), &proc), "roundtrip callback")
            try check(AudioDeviceStart(aggregate, proc), "roundtrip start")
            try input.fileHandleForWriting.write(contentsOf: Data("start\n".utf8))
            Thread.sleep(forTimeInterval: 0.8)
            report += "gain=\(gain): peak=\(audit_stats_peak(stats)), RMS=\(audit_stats_rms(stats)), frames=\(audit_stats_frames(stats))\n"
        }
    } catch { report += "FAIL \(error)\n" }
    return report
}
