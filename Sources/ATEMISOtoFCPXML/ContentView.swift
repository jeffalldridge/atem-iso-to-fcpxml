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
        case .ready: 720
        case .done: 400
        }
    }
}

struct EmptyStateView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        ContentUnavailableView {
            Label("Open an ATEM Recording", systemImage: "video.badge.waveform")
        } description: {
            Text("Drop the recording folder from your ATEM SSD here, or choose it. You will get a Final Cut Pro multicam clip with your live switch and WAV audio.")
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
            Form {
                if let loaded = model.loaded {
                    Section {
                        LabeledContent("Recording", value: loaded.recording.name)
                        LabeledContent("Length", value: loaded.durationText)
                        LabeledContent("Format", value: loaded.formatText)
                        LabeledContent("Live switch", value: "\(loaded.cutCount) clips, \(loaded.dissolveCount) dissolves")
                    } header: {
                        Text(loaded.folderName)
                    }

                    Section("Cameras") {
                        ForEach(loaded.cameras) { camera in
                            Toggle(isOn: binding(for: camera.id)) {
                                HStack {
                                    Text(camera.name)
                                    Spacer()
                                    if camera.usedLive { Text("Used live").foregroundStyle(.secondary) }
                                    if camera.wavName == nil { Text("MP4 audio").foregroundStyle(.secondary) }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        if model.selectedCameras.isEmpty {
                            Text("Choose at least one camera.").foregroundStyle(.secondary).font(.callout)
                        }
                    }

                    if loaded.audio.isEmpty {
                        Section("Soundtrack") {
                            Text("No WAV files were found, so the first camera's MP4 audio will be the soundtrack.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            Picker("Soundtrack", selection: $model.soundtrack) {
                                ForEach(loaded.audio) { audio in
                                    Text(audio.title).tag(audio.id)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        } header: {
                            Text("Soundtrack")
                        } footer: {
                            Text("Plays continuously across camera cuts. Switch it later in Final Cut's Angle Viewer.")
                        }
                        if !model.optionalAudio.isEmpty {
                            Section {
                                ForEach(model.optionalAudio) { audio in
                                    Toggle(audio.title, isOn: binding(forAudio: audio.id)).toggleStyle(.checkbox)
                                }
                            } header: {
                                Text("Extra Audio Angles")
                            } footer: {
                                Text("Added as separate angles you can switch to. Nothing is mixed together.")
                            }
                        }
                    }

                    Section("Options") {
                        Picker("ATEM transitions", selection: $model.transitions) {
                            ForEach(TransitionStyle.allCases) { style in Text(style.title).tag(style) }
                        }
                        if loaded.recording.programMp4 != nil {
                            Toggle("Include the program recording as an angle", isOn: $model.includeProgramAngle)
                        }
                    }

                    if !loaded.recording.warnings.isEmpty {
                        Section("Notes") {
                            ForEach(loaded.recording.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Change Recording…") { model.chooseRecording() }
                Spacer()
                Text("Saves \(model.loaded?.outputURL.lastPathComponent ?? "") next to the recording")
                    .font(.callout).foregroundStyle(.secondary)
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
            ContentUnavailableView {
                Label("Ready for Final Cut Pro", systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                VStack(spacing: 6) {
                    Text(model.output?.lastPathComponent ?? "").font(.headline).textSelection(.enabled)
                    Text("Saved next to the recording. Importing it creates an event with the multicam clip, the live edit, and every source file.")
                }
            } actions: {
                HStack {
                    Button("Show in Finder") { model.revealInFinder() }
                    Button("Open in Final Cut Pro") { model.openInFinalCut() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

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
