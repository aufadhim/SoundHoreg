import SwiftUI
import AppKit

@main struct SoundHoregApp: App {
    @StateObject private var mixer = Mixer()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("SoundHoreg", id: "mixer") { MixerView().environmentObject(mixer).onAppear { delegate.attach(mixer) }.frame(minWidth: 760, minHeight: 620) }
            .defaultSize(width: 920, height: 760)
        MenuBarExtra("SoundHoreg", systemImage: "waveform") { MenuControls().environmentObject(mixer) }
        .commands { CommandGroup(after: .appInfo) { Button("Bypass audio") { mixer.bypass.toggle() }.keyboardShortcut("b", modifiers: [.command, .shift]) } }
    }
}
struct MenuControls: View {
    @EnvironmentObject var mixer: Mixer
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Buka SoundHoreg") { openWindow(id: "mixer"); NSApp.activate(ignoringOtherApps: true) }
        Toggle("Bypass — audio normal", isOn: $mixer.bypass)
        Button("Nonton + Telepon") { mixer.callPreset() }
        Divider()
        Button("Keluar SoundHoreg") { mixer.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var mixer: Mixer?
    private var tokens: [NSObjectProtocol] = []
    func attach(_ mixer: Mixer) {
        self.mixer = mixer
        if tokens.isEmpty {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in DispatchQueue.main.async { self?.syncVisibility() } })
            }
        }
        DispatchQueue.main.async { self.syncVisibility() }
    }
    func syncVisibility() { mixer?.setMeterVisible(!NSApp.isHidden && NSApp.windows.contains { $0.title == "SoundHoreg" && $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }) }
    func applicationWillTerminate(_ notification: Notification) { mixer?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct LevelMeter: View {
    @ObservedObject var levels: MeterLevels
    let id: String
    var body: some View {
        GeometryReader { g in RoundedRectangle(cornerRadius: 2).fill(Color.mint.opacity(0.7)).frame(width: g.size.width * CGFloat(min(1, levels.peaks[id] ?? 0))) }.frame(height: 3).background(.white.opacity(0.04))
    }
}
struct MixerView: View {
    @EnvironmentObject var mixer: Mixer
    @State private var sceneName = ""
    private let accent = Color(red: 0.47, green: 0.85, blue: 0.70)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.path").font(.system(size: 29, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) { Text("SoundHoreg").font(.system(size: 28, weight: .bold, design: .rounded)); Text("Your sound. Your balance.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Circle().fill(mixer.bypass ? .orange : accent).frame(width: 7, height: 7)
                Text(mixer.bypass ? "Bypass aktif" : "\(mixer.controlledCount) aplikasi diatur").font(.caption).foregroundStyle(.secondary)
                Toggle("Bypass", isOn: $mixer.bypass).toggleStyle(.switch).tint(accent).fixedSize()
            }.padding(26)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("MASTER MIX", systemImage: "slider.horizontal.3").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack { Image(systemName: "speaker.wave.2"); Slider(value: $mixer.master, in: 0...1, step: 0.01); Text("\(Int(mixer.master * 100))%").monospacedDigit().frame(width: 42) }
                    Text("Mengatur aplikasi yang tombol Atur-nya aktif.").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 65)
                VStack(alignment: .leading, spacing: 9) {
                    Text("QUICK SCENE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Button { mixer.callPreset() } label: { Label("Nonton + Telepon", systemImage: "play.rectangle.on.rectangle").padding(.vertical, 5) }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 5).background(accent, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.black)
                    Text("Panggilan 22% · Video 100%").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 26)
            HStack {
                Text("APPLICATIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Toggle("Proses latar", isOn: $mixer.showBackground).font(.caption).toggleStyle(.checkbox)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cari aplikasi", text: $mixer.search).textFieldStyle(.plain).frame(width: 145)
                Button { mixer.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Perbarui daftar")
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if mixer.visible.isEmpty { ContentUnavailableView("Belum ada audio", systemImage: "waveform", description: Text("Putar video atau buka aplikasi panggilan, lalu daftar akan muncul otomatis.")) }
                    ForEach(mixer.visible) { app in ChannelView(app: app) }
                }.padding(.horizontal, 26).padding(.bottom, 20)
            }
            Divider().opacity(0.4)
            HStack {
                Menu { ForEach(mixer.scenes) { scene in Button(scene.name) { mixer.loadScene(scene) } }; if mixer.scenes.isEmpty { Text("Belum ada preset") } } label: { Label("Preset tersimpan", systemImage: "bookmark") }
                TextField("Nama preset baru", text: $sceneName).textFieldStyle(.roundedBorder).frame(width: 160)
                Button("Simpan") { mixer.saveScene(sceneName.trimmingCharacters(in: .whitespaces)); sceneName = "" }.disabled(sceneName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Menu { Button("Audit efisiensi 10 detik") { mixer.auditEnergy() }; Button("Audit level audio") { Task.detached { let result = runLevelAudit() + runRoundTripAudit(); try? result.write(toFile: NSTemporaryDirectory() + "soundhoreg-level-audit.txt", atomically: true, encoding: .utf8) } }; Button("Simpan diagnostik lokal") { mixer.diagnostics() }; ForEach(mixer.scenes) { scene in Button("Hapus \(scene.name)", role: .destructive) { mixer.deleteScene(scene.id) } }; Button("Pengaturan izin audio") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) } } label: { Image(systemName: "gearshape") }
            }.padding(18)
        }
        .tint(accent).background(Color(red: 0.065, green: 0.085, blue: 0.10)).preferredColorScheme(.dark)
    }
}
struct ChannelView: View {
    @EnvironmentObject var mixer: Mixer
    let app: AppAudio
    @State private var expanded = false
    var settings: ChannelSettings { mixer.value(app.id) }
    func binding<T>(_ key: WritableKeyPath<ChannelSettings,T>) -> Binding<T> { Binding(get: { mixer.value(app.id)[keyPath: key] }, set: { v in mixer.edit(app.id) { $0[keyPath: key] = v } }) }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Group { if let icon = app.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.fill").resizable() } }.frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(mixer.bypass ? "Bypass" : mixer.isNative(app.id) ? "Level asli · hemat daya" : mixer.isLive(app.id) ? "Diatur SoundHoreg" : app.active ? "Jalur audio aktif" : "Siap memutar audio").font(.caption2).foregroundStyle(.secondary)
                }.frame(width: 145, alignment: .leading)
                Toggle("Atur", isOn: binding(\.controlled)).toggleStyle(.switch).controlSize(.small).fixedSize()
                Button { mixer.edit(app.id) { $0.muted.toggle() } } label: { Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 20) }.buttonStyle(.borderless).disabled(!settings.controlled)
                Slider(value: binding(\.volume), in: 0...2, step: 0.01).help("100% = level asli; 200% = gain +6 dB, bukan dua kali persepsi keras suara").disabled(!settings.controlled || mixer.bypass)
                Text("\(Int((settings.volume * 100).rounded()))%").font(.system(.body, design: .monospaced)).frame(width: 47).foregroundStyle(settings.volume > 1 ? .orange : .primary)
                Button { mixer.solo = mixer.solo == app.id ? nil : app.id } label: { Text("S").fontWeight(.bold).foregroundStyle(mixer.solo == app.id ? .black : .secondary).padding(6).background(mixer.solo == app.id ? Color.mint : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).help("Solo di antara aplikasi yang diatur").disabled(!settings.controlled)
                Button { expanded.toggle() } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help("Balance, EQ, mono, dan output")
            }
            LevelMeter(levels: mixer.levels, id: app.id)
            if let error = mixer.errors[app.id] { HStack { Text(error).font(.caption).foregroundStyle(.orange); Spacer(); Button("Coba lagi") { mixer.retry(app.id) } } }
            if expanded {
                Divider()
                Text(settings.volume == 0 ? "Mute" : String(format: "Gain %+.1f dB · 100%% = level asli", 20 * log10(settings.volume))).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 24) {
                    VStack(alignment: .leading) { Text("Balance  L ↔ R").font(.caption); Slider(value: binding(\.pan), in: -1...1) }
                    VStack(alignment: .leading) { Text("Bass  \(Int(settings.bass)) dB").font(.caption); Slider(value: binding(\.bass), in: -12...12, step: 1) }
                    VStack(alignment: .leading) { Text("Treble  \(Int(settings.treble)) dB").font(.caption); Slider(value: binding(\.treble), in: -12...12, step: 1) }
                    Toggle("Mono", isOn: binding(\.mono)).fixedSize()
                }.disabled(!settings.controlled)
                HStack {
                    Image(systemName: "hifispeaker")
                    Picker("Output", selection: binding(\.output)) { Text("Ikuti output Mac").tag(""); ForEach(mixer.devices) { Text($0.name).tag($0.id) }; if !settings.output.isEmpty && !mixer.devices.contains(where: { $0.id == settings.output }) { Text("Perangkat tidak tersambung").tag(settings.output) } }.frame(maxWidth: 350)
                    Menu {
                        ForEach([15, 30, 60], id: \.self) { minutes in Button("Mute setelah \(minutes) menit") { mixer.scheduleMute(app.id, minutes: minutes) } }
                        if mixer.sleepTimers[app.id] != nil { Button("Batalkan timer") { mixer.cancelSleep(app.id) } }
                    } label: { Label(mixer.sleepTimers[app.id] == nil ? "Sleep timer" : "Timer aktif", systemImage: "moon.zzz") }.disabled(!settings.controlled)
                    Spacer()
                    Button("Reset aplikasi") { mixer.reset(app.id) }
                }
            }
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.055)))
    }
}
