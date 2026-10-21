import SwiftUI
import AppKit

struct Reply: Decodable { let ok: Bool; let error: String?; let recording: Recording?; let output: String?; let report: String? }
struct Request: Encodable, Sendable {
    let action: String; let path: String
    var cameras: [Int] = []; var soundtrack = ""; var extras: [String] = []; var replace = false
}
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message } }

// Drain one combined pipe before waiting: a long warning report must not deadlock.
func callEngine(_ request: Request) throws -> Reply {
    guard let resources = Bundle.main.resourceURL else { throw AppError(message: "The app’s converter is missing. Reinstall the app.") }
    let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
    guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw AppError(message: "Python 3.9 or newer is required. Install Python from python.org, then reopen the app.")
    }
    let task = Process(); task.executableURL = URL(fileURLWithPath: python)
    task.arguments = [resources.appendingPathComponent("bridge.py").path]
    let input = Pipe(), output = Pipe()
    task.standardInput = input; task.standardOutput = output; task.standardError = output
    try task.run()
    try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
        throw AppError(message: String(data: data, encoding: .utf8) ?? "The converter could not run.")
    }
    if !reply.ok { throw AppError(message: reply.error ?? "Conversion failed.") }
    return reply
}

@MainActor final class Model: ObservableObject {
    @Published var recording: Recording?
    @Published var cameras: Set<Int> = []
    @Published var soundtrack = ""
    @Published var extras: Set<String> = []
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var output: URL?
    @Published var report = ""
    @Published var confirmReplace = false

    var optionalAudio: [Audio] {
        guard let r = recording else { return [] }
        return r.audio.filter { inclusionReason($0.id, cameras: r.cameras, selected: cameras, soundtrack: soundtrack) == nil }
    }
    func reconcileAudio() {
        extras.formIntersection(Set(optionalAudio.map(\.id)))
    }
    func openPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an ATEM recording"
        panel.message = "Choose the recording folder or the .drp written by your ATEM."
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.prompt = "Choose Recording"
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { self.load(url) }
            }
        }
    }
    func load(_ url: URL) {
        guard !busy else { return }
        busy = true; status = "Reading recording…"; error = nil; output = nil; recording = nil
        Task {
            do {
                let request = Request(action: "inspect", path: url.path)
                let reply = try await Task.detached { try callEngine(request) }.value
                guard let rec = reply.recording else { throw AppError(message: "The recording could not be read.") }
                recording = rec; cameras = Set(rec.cameras.filter(\.used).map(\.id))
                soundtrack = rec.soundtrack; extras = []
            } catch { self.error = error.localizedDescription }
            busy = false; status = ""
        }
    }
    func create(replace: Bool = false) {
        guard let rec = recording, !busy, !cameras.isEmpty else { return }
        if !replace && FileManager.default.fileExists(atPath: rec.output) { confirmReplace = true; return }
        let allowed = Set(optionalAudio.map(\.id))
        let request = Request(action: "convert", path: rec.path, cameras: cameras.sorted(), soundtrack: soundtrack,
                              extras: extras.intersection(allowed).sorted(), replace: replace)
        busy = true; status = "Creating Final Cut XML…"; error = nil
        Task {
            do {
                let reply = try await Task.detached { try callEngine(request) }.value
                guard let path = reply.output else { throw AppError(message: "The converter did not return a file.") }
                output = URL(fileURLWithPath: path); report = reply.report ?? ""
            } catch { self.error = error.localizedDescription }
            busy = false; status = ""
        }
    }
    func openFinalCut() {
        guard let output else { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FinalCut") else {
            error = "Final Cut Pro is not installed. Use Show in Finder to locate the XML."; return
        }
        NSWorkspace.shared.open([output], withApplicationAt: app, configuration: .init()) { _, failure in
            if let failure { Task { @MainActor in self.error = failure.localizedDescription } }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let output = model.output {
                        Label("Ready for Final Cut", systemImage: "checkmark.circle.fill")
                            .font(.title2.weight(.semibold)).foregroundStyle(.green)
                        Text(output.lastPathComponent).font(.headline).textSelection(.enabled)
                        Text("Import the XML to add the multicam, live edit and footage to a new event.").foregroundStyle(.secondary)
                        Text(model.report).font(.callout).textSelection(.enabled)
                    } else if let rec = model.recording {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(rec.name).font(.title2.weight(.semibold))
                                Text(URL(fileURLWithPath: rec.path).deletingLastPathComponent().path)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            }
                            Spacer()
                            Button("Change…") { model.openPanel() }.disabled(model.busy)
                        }
                        section("Cameras", note: "") {
                            ForEach(rec.cameras) { camera in
                                Toggle(isOn: Binding(get: { model.cameras.contains(camera.id) }, set: { value in
                                    if value { model.cameras.insert(camera.id) } else { model.cameras.remove(camera.id) }
                                })) {
                                    HStack {
                                        Text(camera.name)
                                        Text("Input \(camera.id)").foregroundStyle(.secondary)
                                        Spacer()
                                        if camera.used { Text("Used live").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.toggleStyle(.checkbox)
                            }
                        }
                        section("Soundtrack", note: "Plays continuously across camera cuts.") {
                            if rec.audio.isEmpty {
                                Text("No WAV files found. The first selected camera’s MP4 audio will be used.").foregroundStyle(.secondary)
                            } else {
                                Picker("Soundtrack", selection: $model.soundtrack) {
                                    ForEach(rec.audio) { audio in Text(audio.name).tag(audio.id).help(audio.id) }
                                }.pickerStyle(.radioGroup).labelsHidden()
                            }
                        }
                        if !rec.audio.isEmpty {
                            section("Extra audio", note: "Optional angles, not mixed into the soundtrack.") {
                                ForEach(rec.audio) { audio in
                                    let reason = inclusionReason(audio.id, cameras: rec.cameras, selected: model.cameras, soundtrack: model.soundtrack)
                                    if let reason {
                                        HStack {
                                            Image(systemName: "checkmark").frame(width: 14)
                                            Text(audio.name)
                                            Spacer()
                                            Text(reason).font(.caption)
                                        }.foregroundStyle(.secondary)
                                            .accessibilityElement(children: .combine)
                                    } else {
                                        Toggle(audio.name, isOn: Binding(get: { model.extras.contains(audio.id) }, set: { value in
                                            if value { model.extras.insert(audio.id) } else { model.extras.remove(audio.id) }
                                        })).toggleStyle(.checkbox).help(audio.id)
                                    }
                                }
                            }
                        }
                        if !rec.warnings.isEmpty {
                            section("Recording notes", note: "") {
                                Text(rec.warnings.joined(separator: "\n")).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Text("Saves \(URL(fileURLWithPath: rec.output).lastPathComponent) beside the recording.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !model.busy {
                        VStack(spacing: 16) {
                            Image(systemName: "video.badge.waveform").font(.system(size: 42)).foregroundStyle(.secondary)
                            Text("Open an ATEM recording").font(.title2.weight(.semibold))
                            Text("Choose the recording folder or its .drp file.").foregroundStyle(.secondary)
                            Button("Choose Recording…") { model.openPanel() }.buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity).padding(.vertical, 70)
                    }
                    if let error = model.error {
                        Label { Text(error).textSelection(.enabled) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(.red).font(.callout)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.busy)
            Divider()
            HStack {
                if model.busy {
                    ProgressView().controlSize(.small)
                    Text(model.status).foregroundStyle(.secondary)
                } else if model.output != nil {
                    Button("Another Recording…") { model.openPanel() }
                    Spacer()
                    Button("Show in Finder") { if let output = model.output { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
                    Button("Open in Final Cut") { model.openFinalCut() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { NSApp.terminate(nil) }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if model.recording != nil {
                        if model.cameras.isEmpty { Text("Select at least one camera").font(.caption).foregroundStyle(.secondary) }
                        Button("Create Final Cut XML") { model.create() }.disabled(model.cameras.isEmpty)
                            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    }
                }
            }.padding(16).frame(height: 62)
        }
        .frame(width: 520, height: model.recording == nil || model.output != nil ? 360 : 720)
        .onChange(of: model.cameras) { _ in model.reconcileAudio() }
        .onChange(of: model.soundtrack) { _ in model.reconcileAudio() }
        .alert("Replace existing XML?", isPresented: $model.confirmReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { model.create(replace: true) }
        } message: { Text("An XML already exists beside this recording. Replacing it will not change your source media.") }
    }
    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            if !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 7, content: content)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.windows.first?.delegate = self
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1 else { model.error = "Choose one recording at a time."; return }
        model.load(urls[0])
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.busy ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct ATEMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("ATEM ISO to FCPXML", id: "converter") { ContentView(model: delegate.model) }
            .windowResizability(.contentSize)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Open Recording…") { delegate.model.openPanel() }.keyboardShortcut("o").disabled(delegate.model.busy)
                }
            }
    }
}
