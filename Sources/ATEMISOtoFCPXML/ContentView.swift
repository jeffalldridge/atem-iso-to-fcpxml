import SwiftUI
import UniformTypeIdentifiers
import ATEMConverter

/// One recording workspace; the choice panes grow with the window.
struct ContentView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        VStack(spacing: 0) {
            if let loaded = model.loaded {
                RecordingHeader(model: model, loaded: loaded)
                Divider()
                ChoiceColumns(model: model, loaded: loaded)
                    .disabled(model.isBusy)
            } else {
                EmptyStateView(model: model)
            }
        }
        .frame(minWidth: Layout.minWidth, idealWidth: Layout.idealWidth, maxWidth: .infinity)
        .frame(minHeight: 560, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { ActionBar(model: model) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.chooseRecording() } label: { Label("Open Recording…", systemImage: "folder") }
                    .help("Open an ATEM recording folder or .drp file (⌘O)")
                    .disabled(model.isBusy)
            }
        }
        .navigationTitle("ATEM ISO to FCPXML")
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, url.isFileURL, !model.isBusy else { return false }
            model.open(url)
            return true
        } isTargeted: { model.isTargeted = $0 }
        .overlay {
            if model.isTargeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.tint, lineWidth: 3).padding(10)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Replace the existing FCPXML?", isPresented: $model.showReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace", role: .destructive) { model.convert(replace: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.loaded?.outputURL.lastPathComponent ?? "") already exists next to the recording. Your recording is never changed.")
        }
    }
}

struct EmptyStateView: View {
    @Bindable var model: ConversionModel

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).accessibilityHidden(true)
                Text("Open an ATEM Recording").font(.title2.bold())
            }
        } description: {
            if model.phase == .loading {
                ProgressView("Reading the recording…").controlSize(.small)
            } else {
                Text("Drop the recording folder from your ATEM SSD here, or choose it.")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }
}
