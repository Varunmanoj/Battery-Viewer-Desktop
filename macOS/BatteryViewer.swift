import SwiftUI
import Combine
import AVFoundation

private enum PercentageSize {
    static let range = 48.0...180.0
    static let initial: Double = {
        switch UserDefaults.standard.string(forKey: "size") {
        case "Large": return 82
        case "Maximum": return 158
        default: return 116
        }
    }()
}

private enum LowBatteryThreshold {
    static let range = 1.0...100.0
    static let defaultValue = 20
    static let key = "lowBatteryThreshold"
}

private final class Monitor: ObservableObject {
    @Published private(set) var reading = Reading.current()
    @Published var settingsOpen = false
    private let synth = AVSpeechSynthesizer()
    private var polling: AnyCancellable?

    init() {
        polling = Timer.publish(every: 5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refresh(automatic: true)
        }
    }

    func refresh(automatic: Bool = false) {
        let next = Reading.current()
        guard next != reading else { return }
        let defaults = UserDefaults.standard
        let threshold = defaults.object(forKey: LowBatteryThreshold.key) as? Int ?? LowBatteryThreshold.defaultValue
        let announce = automatic && next.shouldAnnounce(after: reading,
            power: defaults.bool(forKey: "announcePower"),
            lowThreshold: defaults.bool(forKey: "announceLow") ? threshold : nil)
        reading = next
        if announce { speak(next.summary) }
    }

    func announce(statusOnly: Bool = false) {
        refresh()
        speak(statusOnly ? reading.status : reading.summary)
    }

    func announceBatteryLevel() {
        refresh()
        speak(reading.levelDescription)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let id = UserDefaults.standard.string(forKey: "voice"), !id.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
        }
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
}

private struct SettingsView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var delegate: Delegate
    @AppStorage("percentageFontSize") private var size = PercentageSize.initial
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("voice") private var voice = ""
    @AppStorage("announcePower") private var power = false
    @AppStorage("announceLow") private var low = false
    @AppStorage(LowBatteryThreshold.key) private var lowThreshold = LowBatteryThreshold.defaultValue
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @FocusState private var sizeFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader).padding(24)
            Form {
                Section("Display") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Battery percentage size")
                            Spacer()
                            Text("\(Int(size)) pt").monospacedDigit()
                        }.accessibilityHidden(true)
                        Slider(value: $size, in: PercentageSize.range, step: 1) {
                            Text("Battery percentage size")
                        }
                        .labelsHidden()
                        .accessibilityValue("\(Int(size)) points")
                        .focused($sizeFocused)
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Speech") {
                    Picker("Speech voice", selection: $voice) {
                        Text("System default").tag("")
                        ForEach(voices, id: \.identifier) { v in
                            Text("\(v.name) · \(v.language)").tag(v.identifier)
                        }
                    }
                    Button("Preview voice") { monitor.announce() }
                }
                Section("Automatic announcements") {
                    Toggle("When power is connected or disconnected", isOn: $power)
                    Toggle("Announce low battery", isOn: $low)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Low battery threshold")
                            Spacer()
                            Text("\(lowThreshold)%").monospacedDigit()
                        }.accessibilityHidden(true)
                        Slider(value: Binding(get: { Double(lowThreshold) }, set: { lowThreshold = Int($0.rounded()) }),
                               in: LowBatteryThreshold.range, step: 1) {
                            Text("Low battery threshold")
                        }
                        .labelsHidden()
                        .accessibilityValue("\(lowThreshold) percent")
                        .disabled(!low)
                    }
                }
                Section("Background") {
                    Toggle("Keep running when the window closes", isOn: $delegate.runInBackground)
                    Text("Use the Battery % Viewer menu bar icon to reopen or quit.")
                }
                Section("About") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                    Text(verbatim: "Battery % Viewer, version " + version)
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Done") { monitor.settingsOpen = false }.keyboardShortcut(.defaultAction) }.padding(16)
        }
        .frame(minWidth: 460, idealWidth: 490, minHeight: 500)
        .defaultFocus($sizeFocused, true)
        .onExitCommand { monitor.settingsOpen = false }
        .onAppear {
            voices = AVSpeechSynthesisVoice.speechVoices().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if !voice.isEmpty && !voices.contains(where: { $0.identifier == voice }) { voice = "" }
        }
    }
}

private struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var delegate: Delegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("percentageFontSize") private var size = PercentageSize.initial
    @AppStorage("appearance") private var appearance = "System"
    @FocusState private var focus: Focus?
    private enum Focus { case speak, settings }

    private var ink: Color { scheme == .dark ? Color(red: 0.75, green: 0.96, blue: 0.81) : Color(red: 0.06, green: 0.24, blue: 0.17) }
    private var panel: Color { scheme == .dark ? Color(red: 0.09, green: 0.17, blue: 0.14) : Color(red: 0.90, green: 0.95, blue: 0.90) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Battery level").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Image(systemName: "battery.100").font(.title2).accessibilityHidden(true)
                }
                Text(monitor.reading.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel(monitor.reading.percent.map { "Battery level, \($0) percent" } ?? "Battery level unavailable")
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { n in
                        RoundedRectangle(cornerRadius: 2).fill(n * 5 < (monitor.reading.percent ?? 0) ? ink : ink.opacity(contrast == .increased ? 0.35 : 0.16))
                    }
                }.frame(height: 12).accessibilityHidden(true)
                HStack(spacing: 8) {
                    Image(systemName: monitor.reading.onBattery == false ? "powerplug" : "bolt.circle").accessibilityHidden(true)
                    Text(monitor.reading.status)
                }.font(.title3.weight(.medium)).padding(.top, 8)
            }
            .padding(24).foregroundStyle(ink).background(panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(contrast == .increased ? 1 : 0.25)))
            HStack(spacing: 12) {
                Button { monitor.announce() } label: { Label("Speak battery", systemImage: "speaker.wave.2") }
                    .buttonStyle(.borderedProminent).focused($focus, equals: .speak)
                Spacer()
                Button { monitor.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    .focused($focus, equals: .settings)
            }.controlSize(.large)
        }
        .padding(20).frame(minWidth: 360, minHeight: 360)
        .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        .onAppear {
            delegate.monitor = monitor
            delegate.openViewerWindow = { [openWindow] in openWindow(id: "battery") }
            focus = .speak
        }
        .sheet(isPresented: $monitor.settingsOpen, onDismiss: { focus = .settings }) {
            SettingsView(monitor: monitor, delegate: delegate)
                .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        }
    }
}

private final class Delegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var runInBackground = UserDefaults.standard.bool(forKey: "runInBackground") {
        didSet {
            UserDefaults.standard.set(runInBackground, forKey: "runInBackground")
            updateStatusItem()
        }
    }
    weak var monitor: Monitor?
    var openViewerWindow: (() -> Void)?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard openViewerWindow != nil else { return true }
        showViewer()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard runInBackground else { return true }
        sender.setActivationPolicy(.accessory)
        return false
    }

    private func updateStatusItem() {
        guard runInBackground else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: "Battery % Viewer")
        item.button?.setAccessibilityLabel("Battery % Viewer")
        item.button?.toolTip = "Battery % Viewer"
        let menu = NSMenu()
        addItem("Open Battery % Viewer", action: #selector(showViewer), to: menu)
        menu.addItem(.separator())
        addItem("Speak battery level", action: #selector(speakBattery), to: menu)
        addItem("Speak charging status", action: #selector(speakChargingStatus), to: menu)
        menu.addItem(.separator())
        addItem("Quit Battery % Viewer", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }

    @objc private func showViewer() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "battery" && ($0.isVisible || $0.isMiniaturized)
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            (window.attachedSheet ?? window).makeKeyAndOrderFront(nil)
        } else {
            openViewerWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func speakBattery() { monitor?.announceBatteryLevel() }
    @objc private func speakChargingStatus() { monitor?.announce(statusOnly: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct BatteryViewer: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @StateObject private var monitor = Monitor()
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        Window("Battery % Viewer", id: "battery") { Dashboard(monitor: monitor, delegate: delegate) }
            .defaultSize(width: 580, height: 430)
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Settings…") { monitor.settingsOpen = true }.keyboardShortcut(",")
                }
                CommandGroup(after: .toolbar) {
                    Button("Battery Percentage Size…") { monitor.settingsOpen = true }
                }
                CommandMenu("Battery") {
                    Button("Speak battery") { monitor.announce() }.keyboardShortcut("s")
                    Button("Speak power status") { monitor.announce(statusOnly: true) }.keyboardShortcut("c")
                    Divider()
                    Button("System default appearance") { appearance = "System" }
                    Button("Light appearance") { appearance = "Light" }.keyboardShortcut("l")
                    Button("Dark appearance") { appearance = "Dark" }.keyboardShortcut("d")
                }
            }
    }
}
