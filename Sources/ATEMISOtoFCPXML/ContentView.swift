import SwiftUI
import UniformTypeIdentifiers
import ATEMConverter

/// The one window, laid out like Compressor: the recording and its live switch across the top, the choices in three
/// columns under it, and the action in a bar along the bottom. Every band has a fixed height and the columns scroll
/// inside themselves, so the window resizes sideways only and never shows empty space.
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
        .safeAreaInset(edge: .bottom, spacing: 0) { ActionBar(model: model) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.chooseRecording() } label: { Label("Open Recording…", systemImage: "folder") }
                    .help("Open an ATEM recording folder or .drp file (⌘O)")
                    .disabled(model.isBusy)
            }
        }
        .navigationTitle("ATEM ISO to FCPXML")
        .preferredColorScheme(.dark)
        .tint(.brandAccent)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isBusy else { return false }
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
        .onChange(of: model.selectedCameras) { model.refreshTimeline() }
        .onChange(of: model.transitions) { model.refreshTimeline() }
        .alert("Something Went Wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Replace the existing FCPXML?", isPresented: $model.showReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace") { model.convert(replace: true) }
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
        .frame(height: Layout.headerHeight + 1 + Layout.columnsHeight)
    }
}
