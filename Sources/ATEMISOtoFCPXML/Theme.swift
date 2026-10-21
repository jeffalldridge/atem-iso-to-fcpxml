import SwiftUI

/// What the app shares with the website: the accent and the angle colors. The chrome is the system's dark appearance,
/// like Compressor's, so the window reads as a regular well-built dark Mac app.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let brandAccent = Color(hex: 0xFF8A4C)       // --accent on the site
    static let laneBase = Color(nsColor: .underPageBackgroundColor)
    static let audioLane = Color(hex: 0x2A4A3E)         // the soundtrack lane, Final Cut's audio green
    static let audioInk = Color(hex: 0xB4D5C5)          // soundtrack text and waveform
}

/// Colors for angles: cameras take the palette in input order; stills and the program recording are neutral.
enum AnglePalette {
    static let colors: [Color] = [.brandAccent, Color(hex: 0x6F7BB0), Color(hex: 0x5BB5A2), Color(hex: 0xF5D877),
                                  Color(hex: 0xD97AA6), Color(hex: 0x7CC4E8), Color(hex: 0xB08CFF), Color(hex: 0xE8A86B)]
    static func color(for angleID: String, cameraOrder: [Int]) -> Color {
        if angleID.hasPrefix("input-"), let index = Int(angleID.dropFirst(6)), let position = cameraOrder.firstIndex(of: index) {
            return colors[position % colors.count]
        }
        if angleID.hasPrefix("still-") { return Color(hex: 0x9292A4) }
        return Color(hex: 0x4A4A55)
    }
}

/// One set of measurements for the whole window.
enum Layout {
    static let gutter: CGFloat = 20
    static let columnInset: CGFloat = 16
    static let rowHeight: CGFloat = 28
    static let videoLane: CGFloat = 40
    static let audioLane: CGFloat = 24
    static let laneGap: CGFloat = 4
    static let headerHeight: CGFloat = 156
    static let columnsHeight: CGFloat = 236
    static let barHeight: CGFloat = 56
    static let minWidth: CGFloat = 860
    static let idealWidth: CGFloat = 980
}

/// Liquid Glass where the system has it (macOS 26), the standard modern controls on macOS 15.
extension View {
    @ViewBuilder func prominentButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }

    /// A secondary button: clear glass on macOS 26 (the accent tint would make it look like the primary), bordered on 15.
    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass).tint(Color(nsColor: .controlColor)) } else { buttonStyle(.bordered) }
    }
}

/// Groups adjacent glass buttons on macOS 26; a plain container elsewhere.
struct ButtonCluster<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 8) { HStack(spacing: 8) { content() } }
        } else {
            HStack(spacing: 8) { content() }
        }
    }
}
