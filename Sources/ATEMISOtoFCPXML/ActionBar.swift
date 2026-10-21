import SwiftUI

/// The bottom band, where Compressor keeps Start Batch: what the conversion will make on the left, the action on the right.
struct ActionBar: View {
    @Bindable var model: ConversionModel
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 16)
            buttons
        }
        .padding(.horizontal, Layout.gutter)
        .frame(height: Layout.barHeight)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $showDetails) { DetailsSheet(lines: model.summary) { showDetails = false } }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .empty:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small)
            Text("Reading the recording…").foregroundStyle(.secondary)
        case .ready:
            Text(model.planSummary).foregroundStyle(.secondary).lineLimit(2)
        case .converting:
            ProgressView().controlSize(.small)
            Text("Creating \(model.loaded?.outputURL.lastPathComponent ?? "the FCPXML")…").foregroundStyle(.secondary)
        case .done:
            Label {
                Text("Saved \(model.output?.lastPathComponent ?? "") next to the recording.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.phase {
        case .empty, .loading:
            Button("Choose Recording…") { model.chooseRecording() }
                .prominentButton()
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
        case .ready, .converting:
            Button("Create FCPXML") { model.convert() }
                .prominentButton()
                .keyboardShortcut("s")
                .help("Save the Final Cut Pro XML next to the recording (⌘S)")
                .disabled(model.isBusy || model.selectedCameras.isEmpty)
        case .done:
            ButtonCluster {
                Button("Details…") { showDetails = true }.glassButton()
                Button("Show in Finder") { model.revealInFinder() }.glassButton()
                Button("Open in Final Cut Pro") { model.openInFinalCut() }.prominentButton().keyboardShortcut(.defaultAction)
            }
            .fixedSize()
        }
    }
}

struct DetailsSheet: View {
    let lines: [String]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion Details").font(.headline)
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Done", action: dismiss).keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 680, height: 420)
    }
}
