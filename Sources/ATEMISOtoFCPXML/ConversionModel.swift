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
    let title: String  // the camera's name for a camera WAV, otherwise the WAV's own name
    let detail: String  // the file name
    let isCameraAudio: Bool
}

/// One stretch of the live switch, for the timeline strip.
struct TimelineSegment: Identifiable {
    let id: Int
    let start: Double  // 0...1
    let end: Double
    let angleID: String
    let dissolveIn: Bool
}

/// Colors for angles: cameras take the palette in input order; stills and the program recording are neutral.
enum AnglePalette {
    static let colors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .yellow, .indigo]
    static func color(for angleID: String, cameraOrder: [Int]) -> Color {
        if angleID.hasPrefix("input-"), let index = Int(angleID.dropFirst(6)), let position = cameraOrder.firstIndex(of: index) {
            return colors[position % colors.count]
        }
        if angleID.hasPrefix("still-") { return .gray }
        return Color(white: 0.35)
    }
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
    private(set) var timeline: [TimelineSegment] = []
    var cameraOrder: [Int] { loaded?.cameras.map(\.id) ?? [] }
    func color(for angleID: String) -> Color { AnglePalette.color(for: angleID, cameraOrder: cameraOrder) }

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
                var cameraNames: [String: String] = [:]
                for source in recording.sources { if let wav = source.wav { cameraNames[wav.lastPathComponent] = source.name } }
                let prefix = recording.name + " "
                let audio = recording.audioFiles.map { entry in
                    let file = entry.path.lastPathComponent
                    let short = entry.stem.hasPrefix(prefix) && entry.stem.count > prefix.count ? String(entry.stem.dropFirst(prefix.count)) : entry.stem
                    return AudioChoice(id: file, title: cameraNames[file] ?? short, detail: file, isCameraAudio: cameraNames[file] != nil)
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
        refreshTimeline()
        NSDocumentController.shared.noteNewRecentDocumentURL(item.log)
    }

    /// Recompute the live-switch strip for the current camera selection (cheap: the log is tiny).
    func refreshTimeline() {
        guard let loaded, !selectedCameras.isEmpty,
              let edit = try? buildEditList(loaded.recording, cameras: selectedCameras.sorted(), transitions: transitions.rawValue) else {
            timeline = []
            return
        }
        let total = Double(max(loaded.recording.totalFrames, 1))
        timeline = edit.cuts.enumerated().map { index, cut in
            TimelineSegment(id: index, start: Double(cut.start) / total, end: Double(cut.end) / total,
                            angleID: cut.picture.kind == "angle" ? cut.picture.key : cut.picture.kind, dissolveIn: cut.transitionIn != nil)
        }
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
