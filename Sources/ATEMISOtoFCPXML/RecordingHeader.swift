import SwiftUI
import ATEMConverter

/// The top band: the recording's name and format, the live switch as two lanes, and a ruler line under them.
struct RecordingHeader: View {
    @Bindable var model: ConversionModel
    let loaded: LoadedRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(loaded.recording.name).font(.title2.bold()).lineLimit(1)
                Text(loaded.formatText).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(loaded.durationText).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
            TimelineLanes(model: model)
            HStack(spacing: 14) {
                Text(loaded.recording.timecode(0)).monospacedDigit()
                ForEach(loaded.cameras.filter { model.selectedCameras.contains($0.id) }) { camera in
                    LegendItem(name: camera.name, color: model.color(for: "input-\(camera.id)"))
                }
                if model.timeline.contains(where: { $0.angleID.hasPrefix("still-") }) {
                    LegendItem(name: "Still", color: model.color(for: "still-"))
                }
                if model.timeline.contains(where: { $0.angleID == "program" }) {
                    LegendItem(name: "Program", color: model.color(for: "program"))
                }
                Spacer()
                Text(model.liveSwitchText)
                Text(loaded.recording.timecode(loaded.recording.totalFrames)).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Layout.gutter)
        .frame(height: Layout.headerHeight)
    }
}

struct LegendItem: View {
    let name: String
    let color: Color
    var body: some View {
        Label { Text(name) } icon: { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9) }
            .labelStyle(.titleAndIcon)
    }
}

/// The live switch as Final Cut will show it: a video lane cut by angle and the soundtrack lane beneath.
struct TimelineLanes: View {
    @Bindable var model: ConversionModel

    var body: some View {
        Canvas { context, size in
            let video = CGRect(x: 0, y: 0, width: size.width, height: Layout.videoLane)
            let audio = CGRect(x: 0, y: Layout.videoLane + Layout.laneGap, width: size.width, height: Layout.audioLane)
            context.fill(Path(roundedRect: video, cornerRadius: 5), with: .color(.laneBase))
            context.drawLayer { layer in
                layer.clip(to: Path(roundedRect: video, cornerRadius: 5))
                for segment in model.timeline {
                    let x = segment.start * size.width
                    let width = max(1, (segment.end - segment.start) * size.width)
                    layer.fill(Path(CGRect(x: x, y: 0, width: width, height: video.height)), with: .color(model.color(for: segment.angleID)))
                    layer.fill(Path(CGRect(x: x, y: 0, width: 1, height: video.height)), with: .color(.black.opacity(0.35)))
                    if width > 72 {
                        layer.draw(Text(model.angleName(segment.angleID)).font(.caption).foregroundStyle(.white.opacity(0.95)),
                                   at: CGPoint(x: x + 8, y: video.midY), anchor: .leading)
                    }
                }
                for segment in model.timeline where segment.dissolveIn {
                    let x = segment.start * size.width
                    layer.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: video.height)), with: .color(.white.opacity(0.6)))
                }
            }
            context.fill(Path(roundedRect: audio, cornerRadius: 5), with: .color(.audioLane))
            context.drawLayer { layer in
                layer.clip(to: Path(roundedRect: audio, cornerRadius: 5))
                var seed: UInt32 = 7
                var x: CGFloat = 4
                while x < size.width - 4 {
                    seed = seed &* 1103515245 &+ 12345
                    let amplitude = CGFloat((seed >> 16) % 100) / 100
                    let h = 2 + amplitude * (audio.height - 8)
                    layer.fill(Path(CGRect(x: x, y: audio.midY - h / 2, width: 2, height: h)), with: .color(.audioInk.opacity(0.4)))
                    x += 4
                }
                let label = layer.resolve(Text(model.soundtrackName).font(.caption).foregroundStyle(Color.audioInk))
                let labelSize = label.measure(in: CGSize(width: size.width, height: audio.height))
                layer.fill(Path(roundedRect: CGRect(x: 5, y: audio.minY + 3, width: labelSize.width + 12, height: audio.height - 6), cornerRadius: 4),
                           with: .color(.audioLane))
                layer.draw(label, at: CGPoint(x: 11, y: audio.midY), anchor: .leading)
            }
        }
        .frame(height: Layout.videoLane + Layout.laneGap + Layout.audioLane)
        .accessibilityLabel("Live switch with \(model.timeline.count) clips; soundtrack \(model.soundtrackName)")
    }
}
