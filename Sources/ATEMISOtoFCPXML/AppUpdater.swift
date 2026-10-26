import SwiftUI
import Combine
import Sparkle

/// Sparkle owns downloading, signature verification, replacement, and relaunch.
/// Recording contents and paths are never included in update requests.
@MainActor @Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyInstalls = false
    private(set) var startupError: String?
    private(set) var lastCheck: Date?
    @ObservationIgnored private var observations = Set<AnyCancellable>()
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private let isBusy: () -> Bool

    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.lastUpdateCheckDate).sink { [weak self] in self?.lastCheck = $0 }.store(in: &observations)
        controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).sink { [weak self] in self?.automaticallyInstalls = $0 }.store(in: &observations)
    }

    func start() {
        do { try controller.updater.start() }
        catch { startupError = error.localizedDescription }
    }

    func check() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticInstallation(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try Self.requireIdle(isBusy: isBusy())
    }

    static func requireIdle(isBusy: Bool) throws {
        if isBusy {
            throw NSError(domain: "ATEMUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wait for the recording operation to finish, then check for updates again."])
        }
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}

struct UpdateSettingsView: View {
    let updater: AppUpdater
    let model: ConversionModel

    var body: some View {
        Form {
            Text("Updates").font(.headline)
            Text("Installed version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
                .foregroundStyle(.secondary)
            if let lastCheck = updater.lastCheck {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Updates have not been checked yet.").font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticChecks))
            Toggle("Automatically download and install updates", isOn: Binding(get: { updater.automaticallyInstalls }, set: updater.setAutomaticInstallation))
                .disabled(!updater.automaticallyChecks)
            Text("Checks GitHub for published releases. Automatic installation happens when the app quits; an active conversion finishes first. Recordings are never uploaded.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Check for Updates…", action: updater.check)
                .disabled(!updater.canCheck || model.isBusy)
            if model.isBusy {
                Text("Updates can be checked after the recording operation finishes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = updater.startupError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            Link("Releases on GitHub", destination: URL(string: "https://github.com/jeffalldridge/atem-iso-to-fcpxml/releases")!)
        }
        .padding(24)
        .frame(width: 440)
    }
}
