import SwiftUI
import ATEMConverter

/// The middle band: Cameras, Audio, and Options as three flat panes, like Compressor's, each scrolling on its own.
struct ChoiceColumns: View {
    @Bindable var model: ConversionModel
    let loaded: LoadedRecording

    var body: some View {
        HStack(spacing: 0) {
            ChoiceColumn("Cameras", help: model.selectedCameras.isEmpty ? "Choose at least one camera." : "Each checked camera becomes an angle.") {
                ForEach(loaded.cameras) { camera in
                    Toggle(isOn: binding(for: camera.id)) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(model.selectedCameras.contains(camera.id) ? model.color(for: "input-\(camera.id)") : Color.secondary.opacity(0.25))
                                .frame(width: 10, height: 10)
                            Text(camera.name)
                            Spacer()
                            if !camera.usedLive { Text("Not in the switch").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .help(camera.wavName.map { "ISO picture with \($0)" } ?? "ISO picture with the MP4's own audio")
                    .choiceRow()
                }
            }
            Divider()
            ChoiceColumn("Audio", help: loaded.audio.isEmpty ? "No WAV files were found; the first camera's MP4 audio is the soundtrack." : "Checked WAVs become audio-only angles.") {
                if !loaded.audio.isEmpty {
                    LabeledContent("Soundtrack") {
                        Picker("Soundtrack", selection: $model.soundtrack) {
                            ForEach(loaded.audio) { audio in Text(audio.title).tag(audio.id) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .help("The WAV that plays through every cut")
                    .choiceRow()
                    if !model.optionalAudio.isEmpty {
                        Text("Extra angles").font(.subheadline).foregroundStyle(.secondary).padding(.top, 6).choiceRow()
                        ForEach(model.optionalAudio) { audio in
                            Toggle(audio.title, isOn: binding(forAudio: audio.id))
                                .help(audio.detail)
                                .choiceRow()
                        }
                    }
                }
            }
            Divider()
            ChoiceColumn("Options", help: "Next to the recording; the recording is never changed.") {
                LabeledContent("Transitions") {
                    Picker("Transitions", selection: $model.transitions) {
                        ForEach(TransitionStyle.allCases) { style in Text(style.title).tag(style) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .help("How mix transitions from the switcher are rebuilt")
                .choiceRow()
                if loaded.recording.programMp4 != nil {
                    Toggle("Add program recording as an angle", isOn: $model.includeProgramAngle)
                        .help("Also add the ATEM's own program recording as a multicam angle")
                        .choiceRow()
                }
                LabeledContent("Saves to") { Text(loaded.outputURL.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                    .choiceRow()
                if !loaded.recording.warnings.isEmpty {
                    Text("Notes").font(.subheadline).foregroundStyle(.secondary).padding(.top, 6).choiceRow()
                    ForEach(loaded.recording.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
        .frame(height: Layout.columnsHeight)
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

/// One pane: a heading, a one-line helper, and rows that scroll when there are more than fit.
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(help).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { rows() }
                    .padding(.top, 8)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, Layout.columnInset)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// A row in a choice column: one control, a fixed height, full width.
    func choiceRow() -> some View {
        frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
    }
}
