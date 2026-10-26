import AppKit
import SwiftUI
import CoreAudio

struct ChannelSettings: Codable, Equatable {
    var volume = 1.0; var muted = false; var pan = 0.0; var bass = 0.0; var treble = 0.0
    var mono = false; var controlled = false; var output = ""
}
struct SavedScene: Codable, Identifiable { var id = UUID(); var name: String; var settings: [String: ChannelSettings] }
@MainActor final class MeterLevels: ObservableObject { @Published var peaks: [String: Float] = [:] }
struct AppAudio: Identifiable { let id: String; let name: String; let icon: NSImage?; var processes: [AudioObjectID]; var active: Bool; var isApplication: Bool }
@MainActor final class Mixer: ObservableObject {
    @Published var apps: [AppAudio] = []
    @Published var devices: [OutputDevice] = []
    @Published var settings: [String: ChannelSettings] = [:]
    @Published var scenes: [SavedScene] = []
    @Published var bypass = false { didSet { reconcile() } }
    @Published var solo: String? { didSet { reconcile() } }
    @Published var master = 1.0 { didSet { reconcile() } }
    @Published var errors: [String: String] = [:]
    let levels = MeterLevels()
    @Published var search = ""
    @Published var showBackground = false
    @Published var sleepTimers: [String: Date] = [:]
    private var channels: [String: AppChannel] = [:]
    private var signatures: [String: String] = [:]
    private var failedSignatures: [String: String] = [:]
    private var timer: Timer?
    private var sleepTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var refreshWork: DispatchWorkItem?
    private let events = AudioEvents()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var meterVisible = false
    private var shuttingDown = false
    private var refreshCount = 0
    init() {
        if let d = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode([String: ChannelSettings].self, from: d) { settings = s }
        if let d = UserDefaults.standard.data(forKey: "scenes"), let s = try? JSONDecoder().decode([SavedScene].self, from: d) { scenes = s }
        // Old continuous sliders could display 100% while retaining a fractional gain.
        for id in Array(settings.keys) { settings[id]!.volume = normalizedVolume(settings[id]!.volume) }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRefresh() } })
        }
        refresh()
    }
    func normalizedVolume(_ volume: Double) -> Double { min(2, max(0, (volume * 100).rounded() / 100)) }
    func scheduleRefresh() {
        guard !shuttingDown else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }; refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func setMeterVisible(_ visible: Bool) { meterVisible = visible; updateMeterTimer() }
    private func updateMeterTimer() {
        for channel in channels.values { suara_enable_meter(channel.dsp, meterVisible ? 1 : 0) }
        let needed = meterVisible && channels.values.contains(where: { $0.proc != nil }) && !bypass
        if !needed { timer?.invalidate(); timer = nil; if !levels.peaks.isEmpty { levels.peaks = [:] }; return }
        guard timer == nil else { return }
        let meter = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.meter() } }
        meter.tolerance = 0.05; RunLoop.main.add(meter, forMode: .common); timer = meter
    }
    func meter() {
        let next = channels.mapValues { suara_peak($0.dsp) }
        if next != levels.peaks { levels.peaks = next }
    }
    func scheduleMute(_ id: String, minutes: Int) { sleepTimers[id] = Date().addingTimeInterval(Double(minutes * 60)); armSleepTimer() }
    func cancelSleep(_ id: String) { sleepTimers[id] = nil; armSleepTimer() }
    private func armSleepTimer() {
        sleepTimer?.invalidate(); sleepTimer = nil
        guard let deadline = sleepTimers.values.min() else { return }
        let t = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated {
            guard let self else { return }
            for (id, deadline) in self.sleepTimers where deadline <= Date() { self.sleepTimers[id] = nil; self.edit(id) { $0.muted = true } }
            self.armSleepTimer()
        } }; t.tolerance = 0.5; RunLoop.main.add(t, forMode: .common); sleepTimer = t
    }
    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
    }
    func auditEnergy() {
        Task { [weak self] in
            // Exclude menu dismissal, window minimization, and accessibility inspection from the idle sample.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            let start = ProcessInfo.processInfo.systemUptime, cpu = soundhoreg_cpu_seconds(), scans = self.refreshCount
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            let wall = ProcessInfo.processInfo.systemUptime - start
            let used = soundhoreg_cpu_seconds() - cpu
            let text = "SoundHoreg 0.2.0 process observation\nwallSeconds=\(wall)\ncpuSeconds=\(used)\ncpuPercentOfOneCore=\(100 * used / wall)\nrefreshEvents=\(self.refreshCount - scans)\nmeterTimer=\(self.timer != nil)\nwindowVisible=\(self.meterVisible)\ndspChannels=\(self.channels.values.filter { $0.proc != nil }.count)\nThis is a short process CPU sample, not a battery-life measurement.\n"
            try? text.write(toFile: NSTemporaryDirectory() + "soundhoreg-energy-audit.txt", atomically: true, encoding: .utf8)
        }
    }
    func diagnostics() {
        let rows = apps.map { app -> String in
            let channel = channels[app.id]
            return "\(app.name) | \(app.id) | processes=\(app.processes) | controlled=\(value(app.id).controlled) | callbacks=\(channel.map { suara_callbacks($0.dsp) } ?? 0) | error=\(errors[app.id] ?? "none")"
        }
        let report = "SoundHoreg 0.2.0; refreshes=\(refreshCount); meterTimer=\(timer != nil); windowVisible=\(meterVisible)\n" + rows.joined(separator: "\n") + "\nOutputs: " + devices.map(\.name).joined(separator: ", ")
        try? report.write(toFile: NSTemporaryDirectory() + "suara-diagnostics.txt", atomically: true, encoding: .utf8)
    }
    func value(_ id: String) -> ChannelSettings { settings[id] ?? ChannelSettings() }
    func edit(_ id: String, _ update: (inout ChannelSettings) -> Void) {
        var s = value(id); update(&s); s.volume = normalizedVolume(s.volume); settings[id] = s; errors[id] = nil
        saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.persistSettings() }; saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        reconcile()
    }
    func refresh() {
        guard !shuttingDown else { return }; refreshCount += 1
        devices = outputDevices()
        let running = NSWorkspace.shared.runningApplications
        var groups: [String: AppAudio] = [:]
        for object in objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = scalar(object, kAudioProcessPropertyPID, default: 0)
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let raw = stringProperty(object, kAudioProcessPropertyBundleID)
            var owner = running.filter { app in guard let b = app.bundleIdentifier else { return false }; return b == raw || raw.hasPrefix(b + ".") }.max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? NSRunningApplication(processIdentifier: pid)
            if let helperName = owner?.localizedName, owner?.activationPolicy != .regular,
               let host = running.first(where: { $0.activationPolicy == .regular && !($0.localizedName ?? "").isEmpty && helperName.hasPrefix(($0.localizedName ?? "") + " ") }) { owner = host }
            let key = owner?.bundleIdentifier ?? (raw.isEmpty ? "process.\(pid)" : raw)
            guard !key.hasPrefix("id.auf.Suara") else { continue }
            let active: UInt32 = scalar(object, kAudioProcessPropertyIsRunningOutput, default: 0)
            if groups[key] != nil { groups[key]!.processes.append(object); groups[key]!.active = groups[key]!.active || active != 0 }
            else { groups[key] = AppAudio(id: key, name: [owner?.localizedName ?? "", raw.components(separatedBy: ".").last ?? ""].first(where: { !$0.isEmpty }) ?? "Process \(pid)", icon: owner?.icon, processes: [object], active: active != 0, isApplication: owner?.activationPolicy == .regular) }
        }
        apps = groups.values.sorted { a,b in if a.active != b.active { return a.active }; return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var properties: [(AudioObjectID, AudioObjectPropertySelector)] = [(system, kAudioHardwarePropertyProcessObjectList), (system, kAudioHardwarePropertyDevices), (system, kAudioHardwarePropertyDefaultOutputDevice)]
        for app in apps { for process in app.processes { properties.append((process, kAudioProcessPropertyIsRunningOutput)); properties.append((process, kAudioProcessPropertyDevices)) } }
        for device in devices { properties.append((device.object, kAudioDevicePropertyNominalSampleRate)) }
        events.replace(properties) { [weak self] in MainActor.assumeIsolated { self?.scheduleRefresh() } }
        reconcile()
    }
    func reconcile() {
        guard !shuttingDown else { return }
        defer { updateMeterTimer() }
        let live = Set(apps.map(\.id))
        for key in Array(channels.keys) where bypass || !live.contains(key) || !value(key).controlled { channels[key] = nil; signatures[key] = nil }
        guard !bypass else { return }
        let defaultID: AudioObjectID = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, default: 0)
        for app in apps {
            let s = value(app.id); guard s.controlled else { continue }
            let output = s.output.isEmpty ? devices.first(where: { $0.object == defaultID }) : devices.first(where: { $0.id == s.output })
            guard let output else { channels[app.id] = nil; signatures[app.id] = nil; errors[app.id] = "Output tidak tersedia. Pilih perangkat lain."; continue }
            let gain = s.muted || (solo != nil && solo != app.id) ? 0 : s.volume * master
            // A neutral channel is the original path: sample-exact 100%, no extra audio callback.
            if gain == 1 && s.pan == 0 && s.bass == 0 && s.treble == 0 && !s.mono && (s.output.isEmpty || output.object == defaultID) {
                channels[app.id] = nil; signatures[app.id] = nil; if errors[app.id] != nil { errors[app.id] = nil }; continue
            }
            let sourceIDs = Set(app.processes.flatMap { objectList($0, kAudioProcessPropertyDevices) })
            let source = devices.first(where: { $0.object == defaultID && sourceIDs.contains($0.object) }) ?? devices.first(where: { sourceIDs.contains($0.object) }) ?? output
            let sampleRate: Float64 = scalar(output.object, kAudioDevicePropertyNominalSampleRate, default: 48000)
            let signature = "\(app.processes.sorted())-\(source.id)-\(output.id)-\(sampleRate)-\(gain == 0 ? "mute" : "dsp")"
            if errors[app.id] != nil && failedSignatures[app.id] != signature { errors[app.id] = nil }
            if signatures[app.id] != signature { channels[app.id] = nil; signatures[app.id] = nil }
            if channels[app.id] == nil, errors[app.id] == nil {
                do { channels[app.id] = try AppChannel(processes: app.processes, output: output, source: source, settings: s, gain: s.muted || (solo != nil && solo != app.id) ? 0 : s.volume * master); signatures[app.id] = signature }
                catch { errors[app.id] = error.localizedDescription; failedSignatures[app.id] = signature }
            }
            channels[app.id]?.update(s, gain: s.muted || (solo != nil && solo != app.id) ? 0 : s.volume * master)
        }
    }
    func isLive(_ id: String) -> Bool { value(id).controlled && !bypass && errors[id] == nil && apps.contains(where: { $0.id == id }) }
    func isNative(_ id: String) -> Bool { isLive(id) && channels[id] == nil }
    func retry(_ id: String) { errors[id] = nil; reconcile() }
    func reset(_ id: String) { cancelSleep(id); edit(id) { $0 = ChannelSettings() }; if solo == id { solo = nil } }
    func callPreset() {
        for app in apps {
            let call = ["whatsapp", "telegram", "facetime", "telephonyutilities", "avconferenced", "zoom", "discord"].contains { app.id.lowercased().contains($0) }
            let video = ["safari", "chrome", "firefox", "vlc", "iina", "brave"].contains { app.id.lowercased().contains($0) }
            if call || video { edit(app.id) { $0.controlled = true; $0.volume = call ? 0.22 : 1; $0.muted = false } }
        }
        bypass = false; solo = nil
    }
    func saveScene(_ name: String) { scenes.append(SavedScene(name: name, settings: settings)); persistScenes() }
    func loadScene(_ scene: SavedScene) { settings = scene.settings.mapValues { var s = $0; s.volume = normalizedVolume(s.volume); return s }; errors = [:]; solo = nil; if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "settings") }; reconcile() }
    func deleteScene(_ id: UUID) { scenes.removeAll { $0.id == id }; persistScenes() }
    private func persistScenes() { if let d = try? JSONEncoder().encode(scenes) { UserDefaults.standard.set(d, forKey: "scenes") } }
    func stop() { shuttingDown = true; refreshWork?.cancel(); saveWork?.cancel(); persistSettings(); timer?.invalidate(); sleepTimer?.invalidate(); events.cancel(); channels.removeAll(); signatures.removeAll() }
    var visible: [AppAudio] { apps.filter { (showBackground || $0.isApplication || value($0.id).controlled) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    var controlledCount: Int { apps.filter { isLive($0.id) }.count }
}
