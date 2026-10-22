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
        .padding(.vertical, 12)
        .frame(minHeight: Layout.barHeight)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $showDetails) { DetailsSheet(lines: model.summary) { showDetails = false } }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .empty:
            EmptyView()  // the empty window has no action bar; see ContentView
        case .loading:
            ProgressView().controlSize(.small)
            Text("Reading the recording…").foregroundStyle(.secondary)
        case .ready:
            VStack(alignment: .leading, spacing: 2) {
                Text(model.planSummary).lineLimit(2)
                Text(model.destinationNote).font(.caption).lineLimit(2)
            }
            .foregroundStyle(.secondary)
        case .converting:
            ProgressView().controlSize(.small)
            Text("Creating \(model.loaded?.outputURL.lastPathComponent ?? "the FCPXML")…").foregroundStyle(.secondary)
        case .done:
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Saved \(model.output?.lastPathComponent ?? "") next to the recording.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if model.warningCount > 0 {
                    Label("\(model.warningCount) recording note\(model.warningCount == 1 ? "" : "s"). Open Details to review.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.phase {
        case .empty, .loading, .ready, .converting:
            Button("Create FCPXML") { model.convert() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Save the Final Cut Pro XML next to the recording (⌘S)")
                .disabled(model.isBusy || model.selectedCameras.isEmpty)
        case .done:
            HStack(spacing: 8) {
                Button("Details…") { showDetails = true }.buttonStyle(.bordered)
                Button("Show in Finder") { model.revealInFinder() }.buttonStyle(.bordered)
                Button("Open in Final Cut Pro") { model.openInFinalCut() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
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
