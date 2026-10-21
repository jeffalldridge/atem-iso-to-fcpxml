import SwiftUI

/// Timeline colors describe media; window chrome and controls follow macOS appearance.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let laneBase = Color(nsColor: .underPageBackgroundColor)
    static let audioLane = Color(hex: 0x2A4A3E)         // the soundtrack lane, Final Cut's audio green
    static let audioInk = Color(hex: 0xB4D5C5)          // soundtrack text and waveform
}

/// Colors for angles: cameras take the palette in input order; stills and the program recording are neutral.
enum AnglePalette {
    static let colors: [Color] = [Color(hex: 0x406B9A), Color(hex: 0x685B96), Color(hex: 0x34786D), Color(hex: 0x866B38),
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
    static let videoLane: CGFloat = 40
    static let audioLane: CGFloat = 24
    static let laneGap: CGFloat = 4
    static let headerHeight: CGFloat = 156
    static let columnsHeight: CGFloat = 260
    static let barHeight: CGFloat = 56
    static let minWidth: CGFloat = 760
    static let idealWidth: CGFloat = 900
}
