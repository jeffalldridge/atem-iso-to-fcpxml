import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ATEMConverter

/// A camera input as shown in the window.
struct CameraChoice: Identifiable, Hashable {
    let id: Int
    let name: String
    let usedLive: Bool
    let wavName: String?
}

struct AudioChoice: Identifiable, Hashable {
    let id: String  // file name
    let title: String
    let isCameraAudio: Bool
}

struct LoadedRecording {
    let log: URL
    let recording: Recording
    let cameras: [CameraChoice]
    let audio: [AudioChoice]
    let cutCount: Int
    let dissolveCount: Int
    let outputURL: URL
    var folderName: String { recording.root.lastPathComponent }
    var durationText: String {
        let seconds = Int(recording.duration.doubleValue.rounded())
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
                               : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    var formatText: String {
        let rate = formatRate(recording.frameRate.doubleValue)
        return "\(recording.width) × \(recording.height), \(rate) fps"
    }
}

func formatRate(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
}

enum TransitionStyle: String, CaseIterable, Identifiable {
    case dissolve, cut, program
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dissolve: "Cross dissolves"
        case .cut: "Hard cuts"
        case .program: "Program recording"
        }
    }
}

@Observable
@MainActor
final class ConversionModel {
    enum Phase { case empty, loading, ready, converting, done }

    private(set) var phase: Phase = .empty
    private(set) var loaded: LoadedRecording?
    var selectedCameras: Set<Int> = []
    var soundtrack: String = ""
    var extraAudio: Set<String> = []
    var transitions: TransitionStyle = .dissolve
    var includeProgramAngle = false
    private(set) var output: URL?
    private(set) var summary: [String] = []
    var errorMessage: String?
    var showReplaceConfirmation = false
    var isTargeted = false

    var isBusy: Bool { phase == .loading || phase == .converting }

    /// WAVs that can be added as separate angles: not the soundtrack and not already paired with a chosen camera.
    var optionalAudio: [AudioChoice] {
        guard let loaded else { return [] }
        let paired = Set(loaded.cameras.filter { selectedCameras.contains($0.id) }.compactMap(\.wavName))
        return loaded.audio.filter { $0.id != soundtrack && !paired.contains($0.id) }
    }

    func chooseRecording() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an ATEM Recording"
        panel.message = "Choose the recording folder your ATEM wrote, or the .drp file inside it."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .atemLog]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !isBusy else { return }
        phase = .loading
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let log = try locateLog(url)
                let recording = try openRecording(log)
                let defaults = try makePlan(recording)
                let used = Set(defaults.angles.filter { $0.kind == "camera" }.compactMap(\.sourceIndex))
                let cameras = recording.sources.filter { $0.kind == "Video" && $0.mp4 != nil }.sorted { $0.index < $1.index }
                    .map { CameraChoice(id: $0.index, name: $0.name, usedLive: used.contains($0.index), wavName: $0.wav?.lastPathComponent) }
                let cameraWavs = Set(recording.sources.compactMap { $0.wav?.lastPathComponent })
                let prefix = recording.name + " "
                let audio = recording.audioFiles.map { entry in
                    let title = entry.stem.hasPrefix(prefix) && entry.stem.count > prefix.count ? String(entry.stem.dropFirst(prefix.count)) : entry.stem
                    return AudioChoice(id: entry.path.lastPathComponent, title: title, isCameraAudio: cameraWavs.contains(entry.path.lastPathComponent))
                }
                let main = defaults.angles.first { $0.id == defaults.mainAudioAngle }?.audio?.lastPathComponent ?? ""
                let mics = Set(defaults.angles.filter { $0.kind == "audio" && $0.id != defaults.mainAudioAngle }.compactMap { $0.audio?.lastPathComponent })
                let item = LoadedRecording(log: log, recording: recording, cameras: cameras, audio: audio,
                                           cutCount: defaults.edit.cuts.count, dissolveCount: defaults.edit.cuts.filter { $0.transitionIn != nil }.count,
                                           outputURL: log.deletingPathExtension().appendingPathExtension("fcpxml"))
                await MainActor.run { self.finishLoading(item, cameras: used, soundtrack: main, extras: mics) }
            } catch {
                await MainActor.run { self.fail(error) }
            }
        }
    }

    private func finishLoading(_ item: LoadedRecording, cameras: Set<Int>, soundtrack: String, extras: Set<String>) {
        loaded = item
        selectedCameras = cameras
        self.soundtrack = soundtrack
        extraAudio = extras
        output = nil
        summary = []
        phase = .ready
        NSDocumentController.shared.noteNewRecentDocumentURL(item.log)
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? ConversionError)?.message ?? error.localizedDescription
        phase = loaded == nil ? .empty : .ready
    }

    func convert(replace: Bool = false) {
        guard let loaded, phase == .ready, !selectedCameras.isEmpty else { return }
        if !replace && FileManager.default.fileExists(atPath: loaded.outputURL.path) {
            showReplaceConfirmation = true
            return
        }
        var options = PlanOptions()
        options.cameras = selectedCameras.sorted()
        options.audio = soundtrack.isEmpty ? nil : soundtrack
        let allowed = Set(optionalAudio.map(\.id))
        options.extraAudio = extraAudio.intersection(allowed).sorted()
        options.transitions = transitions.rawValue
        options.includeProgram = includeProgramAngle
        let destination = loaded.outputURL
        phase = .converting
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let recording = try openRecording(loaded.log)
                let plan = try makePlan(recording, options)
                let payload = try buildFCPXML(plan)
                if OutputWriter.protectedPaths(recording).contains(destination.resolvedPath) {
                    throw ConversionError("Refusing to overwrite the .drp or recording media.")
                }
                try OutputWriter.write(payload, to: destination, replace: replace)
                let lines = plan.summary()
                await MainActor.run {
                    self.output = destination
                    self.summary = lines
                    self.phase = .done
                }
            } catch {
                await MainActor.run { self.fail(error) }
            }
        }
    }

    func openInFinalCut() {
        guard let output else { return }
        guard let finalCut = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FinalCut") else {
            errorMessage = "Final Cut Pro is not installed on this Mac. The XML is saved next to the recording; import it with File → Import → XML in Final Cut Pro."
            return
        }
        NSWorkspace.shared.open([output], withApplicationAt: finalCut, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.errorMessage = error.localizedDescription } }
        }
    }

    func revealInFinder() {
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }

    func startOver() {
        guard !isBusy else { return }
        loaded = nil
        output = nil
        summary = []
        phase = .empty
    }

    func backToChoices() {
        guard phase == .done, loaded != nil else { return }
        output = nil
        phase = .ready
    }
}
