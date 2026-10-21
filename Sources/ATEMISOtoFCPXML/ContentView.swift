import SwiftUI
import UniformTypeIdentifiers
import ATEMConverter

struct ContentView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        Group {
            switch model.phase {
            case .empty, .loading: EmptyStateView(model: model)
            case .ready: ChoicesView(model: model)
            case .converting: ConvertingView()
            case .done: DoneView(model: model)
            }
        }
        .frame(width: 540, height: windowHeight)
        .navigationSubtitle(model.loaded?.folderName ?? "")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isBusy else { return false }
            model.open(url)
            return true
        } isTargeted: { model.isTargeted = $0 }
        .overlay {
            if model.isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3).padding(8)
                    .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.selectedCameras) { model.refreshTimeline() }
        .onChange(of: model.transitions) { model.refreshTimeline() }
        .alert("Something Went Wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Replace the existing Final Cut XML?", isPresented: $model.showReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace") { model.convert(replace: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.loaded?.outputURL.lastPathComponent ?? "") already exists next to the recording. Your recording is never changed.")
        }
    }
}

extension ContentView {
    /// Each phase has a fixed window size so the window follows the content instead of scrolling it.
    var windowHeight: CGFloat {
        switch model.phase {
        case .empty, .loading, .converting: 420
        case .ready: 820
        case .done: 318
        }
    }
}

struct EmptyStateView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        ContentUnavailableView {
            Label("Open an ATEM Recording", systemImage: "video.badge.waveform")
        } description: {
            Text("Drop the recording folder from your ATEM SSD here, or choose it.")
        } actions: {
            if model.phase == .loading {
                ProgressView("Reading recording…").controlSize(.small)
            } else {
                Button("Choose Recording…") { model.chooseRecording() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 40)
    }
}

struct ChoicesView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        VStack(spacing: 0) {
            if let loaded = model.loaded {
                RecordingHeader(model: model, loaded: loaded)
                Divider()
                Form {
                    Section {
                        ForEach(loaded.cameras) { camera in
                            Toggle(isOn: binding(for: camera.id)) {
                                HStack(spacing: 10) {
                                    Circle().fill(model.selectedCameras.contains(camera.id) ? model.color(for: "input-\(camera.id)") : Color.secondary.opacity(0.25))
                                        .frame(width: 10, height: 10)
                                    Text(camera.name)
                                    Spacer()
                                    if camera.usedLive { Text("Used live").foregroundStyle(.secondary) }
                                    if camera.wavName == nil { Text("MP4 audio").foregroundStyle(.secondary) }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    } header: {
                        Text("Cameras")
                    } footer: {
                        Text(model.selectedCameras.isEmpty ? "Choose at least one camera." : "Each camera becomes a multicam angle with its ISO picture and its own WAV.")
                    }

                    Section {
                        if loaded.audio.isEmpty {
                            Text("No WAV files were found, so the first camera's MP4 audio will be the soundtrack.").foregroundStyle(.secondary)
                        } else {
                            Picker("Soundtrack", selection: $model.soundtrack) {
                                ForEach(loaded.audio) { audio in
                                    Text(audio.title).tag(audio.id)
                                }
                            }
                            ForEach(model.optionalAudio) { audio in
                                Toggle(isOn: binding(forAudio: audio.id)) {
                                    HStack {
                                        Text(audio.title)
                                        Spacer()
                                        Text(audio.detail).foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    } header: {
                        Text("Audio")
                    } footer: {
                        Text("The soundtrack plays continuously across camera cuts. Checked WAVs become extra audio angles you can switch to in Final Cut.")
                    }

                    Section {
                        Picker("ATEM transitions", selection: $model.transitions) {
                            ForEach(TransitionStyle.allCases) { style in Text(style.title).tag(style) }
                        }
                        if loaded.recording.programMp4 != nil {
                            Toggle("Include the program recording as an angle", isOn: $model.includeProgramAngle)
                        }
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("The XML is saved next to the recording as \(loaded.outputURL.lastPathComponent). Your recording is never changed.")
                    }

                    if !loaded.recording.warnings.isEmpty {
                        Section("Notes") {
                            ForEach(loaded.recording.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack {
                Button("Change Recording…") { model.chooseRecording() }
                Spacer()
                Button("Create Final Cut XML") { model.convert() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedCameras.isEmpty)
            }
            .padding()
        }
    }

    private func binding(for camera: Int) -> Binding<Bool> {
        Binding(get: { model.selectedCameras.contains(camera) },
                set: { on in if on { model.selectedCameras.insert(camera) } else { model.selectedCameras.remove(camera) } })
    }

    private func binding(forAudio id: String) -> Binding<Bool> {
        Binding(get: { model.extraAudio.contains(id) },
                set: { on in if on { model.extraAudio.insert(id) } else { model.extraAudio.remove(id) } })
    }
}

/// The recording's name, facts, and a strip showing the live switch.
struct RecordingHeader: View {
    @Bindable var model: ConversionModel
    let loaded: LoadedRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(loaded.recording.name).font(.title2.weight(.semibold))
                Spacer()
                Text(loaded.durationText).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(loaded.formatText) · \(loaded.recording.timecode(0)) to \(loaded.recording.timecode(loaded.recording.totalFrames))")
                .font(.callout).foregroundStyle(.secondary)
            TimelineStrip(segments: model.timeline, color: model.color(for:))
                .frame(height: 28)
                .padding(.top, 4)
            HStack(spacing: 14) {
                ForEach(loaded.cameras.filter { model.selectedCameras.contains($0.id) }) { camera in
                    Label {
                        Text(camera.name)
                    } icon: {
                        Circle().fill(model.color(for: "input-\(camera.id)")).frame(width: 8, height: 8)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(liveSwitchText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var liveSwitchText: String {
        let dissolves = model.timeline.filter(\.dissolveIn).count
        return "\(model.timeline.count) clips, \(dissolves) dissolves"
    }
}

/// A proportional bar of the live switch: one block per clip, colored by angle, with dissolves marked.
struct TimelineStrip: View {
    let segments: [TimelineSegment]
    let color: (String) -> Color

    var body: some View {
        Canvas { context, size in
            let bar = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            context.fill(Path(roundedRect: bar, cornerRadius: 6), with: .color(Color.secondary.opacity(0.15)))
            context.clip(to: Path(roundedRect: bar, cornerRadius: 6))
            for segment in segments {
                let x = segment.start * size.width
                let width = max(1, (segment.end - segment.start) * size.width)
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color(segment.angleID)))
            }
            for segment in segments where segment.dissolveIn {
                let x = segment.start * size.width
                var mark = Path()
                mark.move(to: CGPoint(x: x - 3, y: 0))
                mark.addLine(to: CGPoint(x: x + 3, y: 0))
                mark.addLine(to: CGPoint(x: x, y: 4))
                mark.closeSubpath()
                context.fill(mark, with: .color(.white.opacity(0.75)))
            }
        }
        .accessibilityLabel("Live switch timeline with \(segments.count) clips")
    }
}

struct ConvertingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Creating Final Cut XML…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

struct DoneView: View {
    @Bindable var model: ConversionModel
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Ready for Final Cut Pro")
                    .font(.title2.weight(.semibold))
                Text("\(model.output?.lastPathComponent ?? "") was saved next to the recording.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Show in Finder") { model.revealInFinder() }
                    Button("Open in Final Cut Pro") { model.openInFinalCut() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .fixedSize()
                .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)

            Divider()
            HStack {
                Button("Back") { model.backToChoices() }
                Button("Details…") { showDetails = true }
                Spacer()
                Button("Convert Another…") { model.chooseRecording() }
            }
            .padding()
        }
        .sheet(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Conversion Details").font(.headline)
                ScrollView {
                    Text(model.summary.joined(separator: "\n"))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Done") { showDetails = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 640, height: 400)
        }
    }
}
