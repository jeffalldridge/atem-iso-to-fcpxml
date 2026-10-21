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
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Recording…") { delegate.model.chooseRecording() }
                    .keyboardShortcut("o")
                    .disabled(delegate.model.isBusy)
                Menu("Open Recent") {
                    ForEach(delegate.model.recentRecordings, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) { delegate.model.open(url) }
                    }
                    if !delegate.model.recentRecordings.isEmpty {
                        Divider()
                        Button("Clear Menu") { NSDocumentController.shared.clearRecentDocuments(nil) }
                    }
                }
                .disabled(delegate.model.isBusy)
            }
            CommandGroup(replacing: .help) {
                Link("ATEM ISO to FCPXML Help", destination: URL(string: "https://jeffalldridge.github.io/atem-iso-to-fcpxml/")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/jeffalldridge/atem-iso-to-fcpxml/issues")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ConversionModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        model.open(url)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.isBusy ? .terminateCancel : .terminateNow
    }
}
