import SwiftUI
import UniformTypeIdentifiers
import ATEMConverter

extension UTType {
    static let atemLog = UTType(exportedAs: "com.tentstudios.atem-recording-log", conformingTo: .data)
}

struct ATEMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ATEM ISO to FCPXML", id: "converter") {
            ContentView(model: delegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: Layout.idealWidth, height: 620)
        .windowToolbarStyle(.unifiedCompact)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Recording…") { delegate.model.chooseRecording() }
                    .keyboardShortcut("o")
                    .disabled(!delegate.model.canOpenRecording)
                Menu("Open Recent") {
                    ForEach(delegate.model.recentRecordings, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) { delegate.model.open(url) }
                    }
                    if !delegate.model.recentRecordings.isEmpty {
                        Divider()
                        Button("Clear Menu") { delegate.model.clearRecentRecordings() }
                    }
                }
                .disabled(!delegate.model.canOpenRecording)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: delegate.updater.check)
                    .disabled(!delegate.updater.canCheck || delegate.model.isBusy)
                Link("Latest Release on GitHub…", destination: URL(string: "https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases/latest")!)
            }
            CommandGroup(replacing: .saveItem) {
                // Replacing the save group also removes the standard Close item, so restore it.
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
                Divider()
                Button("Create FCPXML") { delegate.model.convert() }
                    .keyboardShortcut("s")
                    .disabled(delegate.model.phase != .ready || delegate.model.selectedCameras.isEmpty)
                Divider()
                Button("Show in Finder") { delegate.model.revealInFinder() }
                    .keyboardShortcut("r")
                    .disabled(delegate.model.phase != .done)
                Button("Open in Final Cut Pro") { delegate.model.openInFinalCut() }
                    .disabled(delegate.model.phase != .done)
            }
            CommandGroup(replacing: .help) {
                Link("ATEM ISO to FCPXML Help", destination: URL(string: "https://jeffalldridge.github.io/atem-iso-to-fcpxml/")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/jeffalldridge/atem-iso-to-fcpxml/issues")!)
            }
        }
        Settings {
            UpdateSettingsView(updater: delegate.updater, model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ConversionModel()
    let termination = DeferredTermination()
    private(set) lazy var updater = AppUpdater(isBusy: { [weak self] in self?.model.isBusy ?? true })

    override init() {
        super.init()
        model.operationFinished = { [weak self] succeeded in
            guard let self, let shouldQuit = self.termination.finish(succeeded: succeeded) else { return }
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
            if !shouldQuit {
                self.model.reopenWindow?()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        updater.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else {
            model.problem = Problem(title: "Open One Recording at a Time", message: "Select a single recording folder or .drp file.")
            return
        }
        model.open(url)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        termination.request(isBusy: model.isPublishing) ? .terminateLater : .terminateNow
    }
}

/// Separate the quit policy from AppKit so completion and failure can be regression-tested.
@MainActor
final class DeferredTermination {
    private(set) var pending = false

    func request(isBusy: Bool) -> Bool {
        pending = isBusy
        return pending
    }

    func finish(succeeded: Bool) -> Bool? {
        guard pending else { return nil }
        pending = false
        return succeeded
    }
}
