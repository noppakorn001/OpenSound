import SwiftUI
import AppKit

struct PairedHeadphones: Identifiable {
    let id: String
    let name: String
}

struct HeadphoneSetting: Identifiable {
    struct Option: Identifiable {
        let id: Int
        let label: String
    }
    let id: String
    let title: String
    let section: String
    let kind: String
    let value: Int?
    let displayValue: String
    let options: [Option]
    let enabled: Bool
    let reason: String
    let privateDetails: String?

    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String else { return nil }
        self.id = id
        title = row["title"] as? String ?? id
        section = row["section"] as? String ?? "Device"
        kind = row["kind"] as? String ?? "readonly"
        value = row["value"] as? Int
        options = (row["options"] as? [[String: Any]] ?? []).compactMap {
            guard let value = $0["value"] as? Int, let label = $0["label"] as? String else { return nil }
            return Option(id: value, label: label)
        }
        let selectedValue = row["value"] as? Int
        displayValue = row["value"] as? String ?? options.first(where: { $0.id == selectedValue })?.label ?? "Unavailable"
        enabled = row["enabled"] as? Bool ?? false
        reason = row["reason"] as? String ?? ""
        privateDetails = row["privateDetails"] as? String
    }
}

@MainActor
final class HeadphoneModel: ObservableObject {
    let bridge = WFBridge()
    @Published var devices: [PairedHeadphones] = []
    @Published var selectedAddress = ""
    @Published var state: [AnyHashable: Any] = [:]
    @Published var busy = false
    @Published var message = "Connect your paired Sony headphones to get started."
    @Published var failed = false
    @Published var draftBands = [0.0, 0.0, 0.0, 0.0, 0.0]
    @Published var draftBass = 0.0
    @Published var dirty = false
    @Published var scanning = false
    @Published private(set) var autoReconnect = true
    @Published private(set) var reconnecting = false
    private var retryPolicy = ReconnectPolicy()
    private var sleeping = false
    private var stopping = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastPoll = Date.distantPast
    private var timer: Timer?
    var connected: Bool { state["connected"] as? Bool ?? false }
    var mode: String { state["mode"] as? String ?? "" }
    var level: Int { state["ambientLevel"] as? Int ?? 1 }
    var voice: Bool { state["focusOnVoice"] as? Bool ?? false }
    var maxAmbient: Int { max(1, state["maxAmbient"] as? Int ?? 1) }
    var preset: Int { state["preset"] as? Int ?? 0 }
    var presets: [Int] { state["presets"] as? [Int] ?? [] }
    var ambientAvailable: Bool { connected && (state["supportsAmbient"] as? Bool ?? false) }
    var eqAvailable: Bool { connected && (state["supportsEQ"] as? Bool ?? false) }
    var editorAvailable: Bool { eqAvailable && (state["supportsEditor"] as? Bool ?? false) }
    var ambientReason: String { state["ambientReason"] as? String ?? "Waiting for headphone status." }
    var deviceName: String { connected ? state["name"] as? String ?? "Sony headphones" : devices.first(where: { $0.id == selectedAddress })?.name ?? "OpenSound" }
    var isEarbuds: Bool { deviceName.hasPrefix("WF-") || deviceName.contains("LinkBuds") }
    var settings: [HeadphoneSetting] { (state["settings"] as? [[String: Any]] ?? []).compactMap(HeadphoneSetting.init) }
    var settingSections: [String] { Array(Set(settings.map(\.section))).sorted() }
    var productImageURL: URL? {
        guard let images = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: "Devices") else { return nil }
        let reportedModel = settings.first(where: { $0.id == "modelName" })?.displayValue ?? ""
        let names = [reportedModel, deviceName].map {
            $0.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        }
        return images.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first { url in
            let model = url.deletingPathExtension().lastPathComponent
            return names.contains(where: { $0 == model || $0.contains(model + "-") || $0.hasSuffix("-" + model) })
        }
    }

    init() {
        autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true
        retryPolicy.enabled = autoReconnect
        let remembered = UserDefaults.standard.string(forKey: "lastHeadphoneAddress") ?? ""
        selectedAddress = remembered
        retryPolicy.remember(remembered, wantsConnection: UserDefaults.standard.bool(forKey: "resumeControlConnection"), now: Date())
        scan()
        let notifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        })
        workspaceObservers.append(notifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false; self.retryPolicy.wake(now: Date()); self.scan()
            }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    private func tick() {
        guard !stopping, !sleeping, !busy else { return }
        let now = Date()
        if connected {
            // Draft EQ must not stop connection monitoring in the Menu Bar.
            guard now.timeIntervalSince(lastPoll) >= 5 else { return }
            lastPoll = now
            perform("Refreshing…", announce: false) { bridge.refresh($0) }
        } else if let address = retryPolicy.consumeAttempt(now: now) {
            guard devices.contains(where: { $0.id == address }) else {
                scan(); retryPolicy.disconnected(now: now)
                message = "The previously selected headphones are not paired. Pair them in Bluetooth settings or select another device."
                return
            }
            selectedAddress = address; reconnecting = true
            perform("Reconnecting…") { bridge.connectAddress(address, completion: $0) }
        }
    }
    private func prepareForSleep() {
        sleeping = true; retryPolicy.sleep()
        state = [:]; dirty = false; message = "Mac is sleeping."
        bridge.disconnect { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state = [:]
                if !self.sleeping { self.retryPolicy.disconnected(now: Date()) }
            }
        }
    }
    func setAutoReconnect(_ enabled: Bool) {
        autoReconnect = enabled
        UserDefaults.standard.set(enabled, forKey: "autoReconnect")
        retryPolicy.setEnabled(enabled, now: Date())
    }
    func scan() {
        guard !scanning else { return }
        scanning = true
        bridge.listDevices { [weak self] devices in
            MainActor.assumeIsolated {
            guard let self else { return }
            self.scanning = false
            self.devices = devices.compactMap {
                guard let address = $0["address"] as? String else { return nil }
                return PairedHeadphones(id: address, name: $0["name"] as? String ?? "Sony headphones")
            }
            if self.selectedAddress.isEmpty {
                self.selectedAddress = self.devices.first?.id ?? ""
            }
            if self.devices.isEmpty {
                self.message = "Pair your Sony headphones in System Settings → Bluetooth, then refresh devices."
            }
            }
        }
    }
    func perform(_ text: String, announce: Bool = true, action: (@escaping @Sendable ([AnyHashable: Any]?, String?) -> Void) -> Void) {
        guard !busy else { return }
        busy = true
        if announce { message = text; failed = false }
        action { [weak self] snapshot, error in
            MainActor.assumeIsolated {
            guard let self else { return }
            guard !self.stopping else { return }
            self.busy = false; self.reconnecting = false
            if let snapshot {
                self.state = snapshot
                if !self.dirty {
                    if let bands = snapshot["bands"] as? [Int], bands.count == 5 {
                        self.draftBands = bands.map(Double.init)
                    }
                    if let bass = snapshot["clearBass"] as? Int { self.draftBass = Double(bass) }
                }
            }
            if let error { self.message = error; self.failed = true }
            else if announce { self.message = self.connected ? "Updated on your headphones." : "Disconnected."; self.failed = false }
            if self.sleeping { self.state = [:]; self.retryPolicy.sleep(); return }
            if self.connected {
                self.retryPolicy.succeeded(self.selectedAddress)
                UserDefaults.standard.set(self.selectedAddress, forKey: "lastHeadphoneAddress")
                UserDefaults.standard.set(true, forKey: "resumeControlConnection")
            } else { self.retryPolicy.disconnected(now: Date()) }
            }
        }
    }
    func connect() {
        guard !busy, !sleeping, !selectedAddress.isEmpty else { scan(); return }
        retryPolicy.remember(selectedAddress, wantsConnection: true, now: Date())
        dirty = false
        perform("Connecting…") { bridge.connectAddress(selectedAddress, completion: $0) }
    }
    func disconnect() {
        guard !busy else { return }
        retryPolicy.userDisconnected()
        UserDefaults.standard.set(false, forKey: "resumeControlConnection")
        dirty = false; perform("Disconnecting…") { bridge.disconnect($0) }
    }
    func refresh() { perform("Refreshing…") { bridge.refresh($0) } }
    func setMode(_ mode: String, level: Int? = nil, voice: Bool? = nil) {
        perform("Applying sound mode…") { bridge.setMode(mode, level: level ?? self.level, voice: voice ?? self.voice, completion: $0) }
    }
    func setPreset(_ preset: Int) {
        dirty = false
        perform("Applying equalizer…") { bridge.setPreset(preset, completion: $0) }
    }
    func setSetting(_ setting: HeadphoneSetting, value: Int) {
        perform("Applying \(setting.title.lowercased())…") { bridge.setSetting(setting.id, value: NSNumber(value: value), completion: $0) }
    }
    func applyEQ() {
        let bass = Int(draftBass.rounded())
        let bands = draftBands.map { NSNumber(value: Int($0.rounded())) }
        dirty = false
        perform("Applying manual EQ…") { bridge.setCustomBass(bass, bands: bands, completion: $0) }
    }
    func discardDraft() {
        dirty = false
        if let bands = state["bands"] as? [Int], bands.count == 5 { draftBands = bands.map(Double.init) }
        if let bass = state["clearBass"] as? Int { draftBass = Double(bass) }
    }
    func shutdown() {
        stopping = true; retryPolicy.sleep(); timer?.invalidate()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll(); bridge.shutdown()
    }
}

private let accent = Color(red: 0.74, green: 0.76, blue: 0.98)
private let cardColor = Color(white: 0.16)
private let presetNames = [0:"Off", 0x10:"Bright", 0x11:"Excited", 0x12:"Mellow", 0x13:"Relaxed",
                           0x14:"Vocal", 0x15:"Treble Boost", 0x16:"Bass Boost", 0x17:"Speech",
                           0xa0:"Manual", 0xa1:"Custom 1", 0xa2:"Custom 2"]

struct PhoneView: View {
    @ObservedObject var model: HeadphoneModel
    @State private var selectedTab = "Sound"
    @State private var draftAmbient = 1.0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.deviceName).font(.system(size: 19, weight: .bold)).lineLimit(1)
                Spacer()
                Menu {
                    if model.connected {
                        Button("Refresh status") { model.refresh() }
                        Button("Disconnect") { model.disconnect() }
                    } else {
                        ForEach(model.devices) { device in
                            Button(device.name) { model.selectedAddress = device.id; model.connect() }
                        }
                        Button("Refresh devices") { model.scan() }
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)) }
                .menuStyle(.borderlessButton).frame(width: 26)
            }.padding(.horizontal, 19).padding(.vertical, 16).background(Color(white: 0.145))
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 9) {
                        if let url = model.productImageURL, let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(height: 117).padding(.top, 16)
                                .accessibilityLabel("\(model.deviceName) product image")
                        } else {
                            Image(systemName: model.isEarbuds ? "earbuds" : "headphones")
                                .font(.system(size: 84, weight: .light)).foregroundStyle(accent)
                                .frame(height: 117).padding(.top, 16)
                        }
                        HStack(spacing: 14) {
                            if model.state["batterySingle"] is Int {
                                battery("Headphones", key: "batterySingle", charging: "singleCharging")
                            } else {
                                battery("L", key: "batteryLeft", charging: "leftCharging")
                                battery("R", key: "batteryRight", charging: "rightCharging")
                                battery("Case", key: "batteryCase", charging: "caseCharging")
                            }
                        }.padding(.top, 5)
                        HStack(spacing: 5) {
                            Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 5, height: 5)
                            Text(model.connected ? "Connected" : "Not connected").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.bottom, 11)
                    }.frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        tab("Status"); tab("Sound"); tab("System")
                    }.padding(.horizontal, 18)
                    Divider()
                    if selectedTab == "Sound" {
                        VStack(alignment: .leading, spacing: 15) {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Ambient Sound Control").font(.system(size: 17, weight: .semibold))
                                HStack(spacing: 7) {
                                    modeButton("anc", title: "Noise Cancelling", icon: "waveform.slash")
                                    modeButton("ambient", title: "Ambient Sound", icon: "waveform")
                                    modeButton("off", title: "Off", icon: "speaker.slash")
                                }
                                if model.ambientAvailable && model.mode == "ambient" {
                                    HStack { Text("Ambient Sound"); Spacer(); Text("\(Int(draftAmbient.rounded()))").foregroundStyle(accent) }.font(.system(size: 12))
                                    Slider(value: $draftAmbient, in: 1...Double(max(2, model.maxAmbient)), step: 1, onEditingChanged: { editing in if !editing { model.setMode("ambient", level: Int(draftAmbient.rounded())) } }).tint(accent).disabled(model.busy)
                                    Toggle("Focus on Voice", isOn: Binding(get: { model.voice }, set: { model.setMode("ambient", voice: $0) })).font(.system(size: 12)).toggleStyle(.switch).disabled(model.busy)
                                }
                                if !model.ambientAvailable { Text(model.ambientReason).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Text("Equalizer").font(.system(size: 17, weight: .semibold)); Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(accent) }
                                Picker("Preset", selection: Binding(get: { model.preset }, set: { model.setPreset($0) })) {
                                    ForEach(model.presets, id: \.self) { preset in Text(presetNames[preset] ?? "Preset \(preset)").tag(preset) }
                                }.disabled(!model.eqAvailable || model.busy)
                                if model.editorAvailable {
                                    HStack(spacing: 4) {
                                        ForEach(0..<5, id: \.self) { i in
                                            VStack(spacing: 5) {
                                                Text(String(format: "%+.0f", model.draftBands[i])).font(.system(size: 11)).foregroundStyle(accent).monospacedDigit()
                                                Slider(value: Binding(get: { model.draftBands[i] }, set: { model.draftBands[i] = $0; model.dirty = true }), in: -10...10, step: 1)
                                                    .frame(width: 92).rotationEffect(.degrees(-90)).frame(width: 40, height: 99)
                                                Text(["400", "1k", "2.5k", "6.3k", "16k"][i]).font(.system(size: 10)).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity)
                                        }
                                    }.tint(accent).disabled(model.busy)
                                    HStack { Text("CLEAR BASS").font(.system(size: 10, weight: .semibold)); Spacer(); Text(String(format: "%+.0f", model.draftBass)).font(.system(size: 12)).foregroundStyle(accent) }
                                    Slider(value: Binding(get: { model.draftBass }, set: { model.draftBass = $0; model.dirty = true }), in: -10...10, step: 1).tint(accent).disabled(model.busy)
                                    if model.dirty {
                                        HStack { Button("Cancel") { model.discardDraft() }; Spacer(); Button("Apply EQ") { model.applyEQ() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black) }.font(.system(size: 12)).disabled(model.busy)
                                    }
                                }
                            }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 7))
                        }.padding(14)
                    } else if selectedTab == "System" {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Automatically reconnect", isOn: Binding(get: { model.autoReconnect }, set: { model.setAutoReconnect($0) }))
                                .toggleStyle(.switch).font(.system(size: 12))
                            if !model.connected {
                                Text("Connect your headphones to see available controls.").font(.system(size: 12)).foregroundStyle(.secondary)
                            } else if model.settings.isEmpty {
                                Text("No additional controls are available for this protocol profile.").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            ForEach(model.settingSections, id: \.self) { section in
                                VStack(alignment: .leading, spacing: 15) {
                                    Text(section).font(.system(size: 17, weight: .semibold))
                                    ForEach(model.settings.filter { $0.section == section }) { setting in
                                        settingRow(setting)
                                    }
                                }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 7))
                            }
                            Text("Controls appear when the connected device advertises a supported format. Model compatibility and feature coverage are included in the project documentation.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(14)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Connection status").font(.system(size: 17, weight: .semibold))
                            LabeledContent("Device", value: model.deviceName)
                            LabeledContent("Connection", value: model.connected ? "Bluetooth" : "Not connected")
                            Text("Battery readings are reported by the headphones. Case data may be unavailable while the case is closed.").font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Refresh status") { model.refresh() }.disabled(!model.connected || model.busy)
                        }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 7)).padding(14)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        if model.busy { ProgressView().controlSize(.mini) }
                        else if model.failed { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                        Text(model.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 19).padding(.bottom, 13)
                }
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                VStack(spacing: 3) { Image(systemName: "earbuds").font(.system(size: 20)); Text("My Device").font(.system(size: 10)) }.foregroundStyle(accent)
                Spacer()
                HStack(spacing: 5) {
                    if let url = Bundle.main.url(forResource: "OpenSound", withExtension: "png"), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityLabel("OpenSound logo")
                    }
                    Text("OpenSound").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.connected ? "Disconnect" : "Connect") {
                    if model.connected { model.disconnect() } else { model.connect() }
                }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12, weight: .semibold)).disabled(model.busy || (!model.connected && model.selectedAddress.isEmpty))
            }.padding(.horizontal, 21).padding(.vertical, 11).background(Color(white: 0.145))
        }.background(Color(white: 0.125)).preferredColorScheme(.dark)
        .onAppear { draftAmbient = Double(model.level) }
        .onChange(of: model.level) { draftAmbient = Double(model.level) }
    }
    private func tab(_ name: String) -> some View {
        Button { selectedTab = name } label: {
            VStack(spacing: 10) {
                Text(name).font(.system(size: 13, weight: selectedTab == name ? .semibold : .regular))
                Rectangle().fill(selectedTab == name ? accent : .clear).frame(height: 3)
            }.frame(maxWidth: .infinity).padding(.top, 9).foregroundStyle(selectedTab == name ? accent : .secondary)
        }.buttonStyle(.plain)
    }
    private func battery(_ title: String, key: String, charging: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 10))
            Image(systemName: model.state[charging] as? Bool == true ? "battery.100percent.bolt" : "battery.100percent").foregroundStyle(accent).font(.system(size: 17))
            Text((model.state[key] as? Int).map { "\($0)%" } ?? "Unavailable").font(.system(size: 10)).monospacedDigit()
        }
    }
    @ViewBuilder
    private func settingRow(_ setting: HeadphoneSetting) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if setting.kind == "choice" && setting.enabled && !setting.options.isEmpty, let value = setting.value {
                Picker(setting.title, selection: Binding(get: { value }, set: { model.setSetting(setting, value: $0) })) {
                    ForEach(setting.options) { option in Text(option.label).tag(option.id) }
                }.disabled(model.busy || !model.connected)
            } else {
                LabeledContent(setting.title, value: setting.displayValue).font(.system(size: 12))
                if let details = setting.privateDetails {
                    DisclosureGroup("Show device names") {
                        Text(details).font(.system(size: 11)).textSelection(.enabled)
                    }.font(.system(size: 11))
                }
                if setting.kind != "readonly" || setting.displayValue == "Unavailable" {
                    Text(setting.reason).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func modeButton(_ value: String, title: String, icon: String) -> some View {
        Button { model.setMode(value) } label: {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 21))
                Text(title).font(.system(size: 10)).multilineTextAlignment(.center).frame(height: 25)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(model.mode == value ? accent.opacity(0.13) : Color(white: 0.2), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(model.mode == value ? accent : .clear, lineWidth: 1))
                .foregroundStyle(model.mode == value ? accent : .white)
        }.buttonStyle(.plain).accessibilityValue(model.mode == value ? "Selected" : "Not selected").disabled(!model.ambientAvailable || model.busy)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: HeadphoneModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.contentAspectRatio = NSSize(width: 390, height: 780)
            window.contentMinSize = NSSize(width: 360, height: 720)
            window.contentMaxSize = NSSize(width: 480, height: 960)
            window.setContentSize(NSSize(width: 390, height: 780))
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "OpenSound" })?.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

@main
struct OpenSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = HeadphoneModel()
    var body: some Scene {
        Window("OpenSound", id: "main") {
            PhoneView(model: model).onAppear { delegate.model = model }
                .frame(minWidth: 360, minHeight: 720)
        }.defaultSize(width: 390, height: 780)
        .commands {
            CommandMenu("Controls") { QuickControls(model: model) }
        }
        MenuBarExtra("OpenSound", systemImage: "headphones") {
            QuickControls(model: model)
        }.menuBarExtraStyle(.menu)
    }
}

struct QuickControls: View {
    @ObservedObject var model: HeadphoneModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.deviceName)
        Text(model.connected ? "Connected" : "Not connected")
        if model.connected {
            if let single = model.state["batterySingle"] as? Int {
                Text("Battery: \(single)%")
            } else {
                Text("L: \(battery("batteryLeft"))   R: \(battery("batteryRight"))   Case: \(battery("batteryCase"))")
            }
            Divider()
            Menu("Ambient Sound Control") {
                Button("Noise Cancelling\(model.mode == "anc" ? " ✓" : "")") { model.setMode("anc") }
                Button("Ambient Sound\(model.mode == "ambient" ? " ✓" : "")") { model.setMode("ambient") }
                Button("Off\(model.mode == "off" ? " ✓" : "")") { model.setMode("off") }
            }.disabled(!model.ambientAvailable || model.busy)
            Menu("Equalizer") {
                ForEach(model.presets, id: \.self) { preset in
                    Button("\(presetNames[preset] ?? "Preset \(preset)")\(model.preset == preset ? " ✓" : "")") { model.setPreset(preset) }
                }
            }.disabled(!model.eqAvailable || model.busy)
            Button("Refresh Status") { model.refresh() }.disabled(model.busy)
            Button("Disconnect") { model.disconnect() }.disabled(model.busy)
        } else {
            ForEach(model.devices) { device in
                Button("Connect \(device.name)") { model.selectedAddress = device.id; model.connect() }.disabled(model.busy)
            }
            Button("Refresh Devices") { model.scan() }.disabled(model.scanning || model.busy)
        }
        if model.busy { Text("Working…") }
        if model.failed { Text(model.message) }
        Divider()
        Toggle("Automatically Reconnect", isOn: Binding(get: { model.autoReconnect }, set: { model.setAutoReconnect($0) }))
        Button("Show OpenSound") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut("o")
        Button("Quit OpenSound") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func battery(_ key: String) -> String {
        (model.state[key] as? Int).map { "\($0)%" } ?? "Unavailable"
    }
}
