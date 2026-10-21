import SwiftUI
import ATEMConverter

/// Audio choices stay visible, with separate controls for the continuous soundtrack and optional angles.
struct ChoiceColumns: View {
    @Bindable var model: ConversionModel
    let loaded: LoadedRecording

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ChoiceColumn("Camera angles", help: "Inputs used in the live switch start checked.") {
                    ForEach(loaded.cameras) { camera in
                        Toggle(isOn: binding(for: camera.id)) {
                            HStack(alignment: .top, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(model.color(for: "input-\(camera.id)"))
                                    .frame(width: 10, height: 10).padding(.top, 3)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(camera.name).fixedSize(horizontal: false, vertical: true)
                                    Text(camera.wavName == nil ? "MP4 audio" : "Paired with WAV audio")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .help(camera.wavName ?? "Uses the MP4's own audio")
                        .accessibilityLabel("\(camera.name), \(camera.wavName == nil ? "MP4 audio" : "paired with WAV audio")")
                        .padding(.vertical, 6)
                    }
                    if model.selectedCameras.isEmpty {
                        Label("Choose at least one camera.", systemImage: "exclamationmark.triangle")
                            .font(.callout).padding(.top, 8)
                    }
                }
                Divider()
                ChoiceColumn("Soundtrack", help: "One source plays throughout the edit. The live mix keeps the recorded ATEM mix; a WAV uses one isolated input.") {
                    Picker("Soundtrack", selection: $model.soundtrack) {
                        if model.liveMixAvailable {
                            Text("ATEM live mix")
                                .help("Keeps the recorded input on/off and audio-follow-video decisions. Later picture edits do not recompute the mix.")
                                .tag(AudioChoice.liveMixID)
                        }
                        ForEach(loaded.audio) { audio in
                            Text(audio.title).help(audio.detail).tag(audio.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .padding(.vertical, 6)
                }
                Divider()
                ChoiceColumn("Extra audio angles", help: "Available for mixing or switching in Final Cut. Not added to the soundtrack automatically.") {
                    if model.optionalAudio.isEmpty {
                        Text(loaded.audio.isEmpty ? "No separate WAVs found." : "All WAVs are already included.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(model.optionalAudio) { audio in
                            Toggle(audio.title, isOn: binding(forAudio: audio.id))
                                .help(audio.detail).padding(.vertical, 6)
                        }
                    }
                }
            }
            .frame(minHeight: Layout.columnsHeight, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Transitions").font(.headline)
                    Picker("Transitions", selection: $model.transitions) {
                        ForEach(TransitionStyle.allCases) { style in Text(style.title).tag(style) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 310)
                    Spacer(minLength: 0)
                }
                Text(transitionHelp).font(.caption).foregroundStyle(.secondary)
                if loaded.recording.programMp4 != nil {
                    Toggle("Include program picture as an angle", isOn: $model.includeProgramAngle)
                        .help("Adds the recorded program picture. Choose its audio separately under Soundtrack.")
                }
                if !loaded.recording.warnings.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(loaded.recording.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 88)
                    .accessibilityLabel("Recording notes")
                }
            }
            .padding(.horizontal, Layout.gutter).padding(.vertical, 14)
        }
        .toggleStyle(.checkbox)
    }

    private var transitionHelp: String {
        switch model.transitions {
        case .dissolve: "Rebuild the switcher's mix transitions as editable dissolves."
        case .cut: "Use straight cuts between cameras."
        case .program: "Use the recorded program picture during transitions."
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

struct ChoiceColumn<Rows: View>: View {
    let title: String
    let help: String
    @ViewBuilder let rows: () -> Rows

    init(_ title: String, help: String, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.help = help
        self.rows = rows
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(help).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                rows()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}
