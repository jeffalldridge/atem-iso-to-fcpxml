import Foundation

public struct ConversionError: Error, CustomStringConvertible, LocalizedError, Sendable {
    public let message: String
    /// Set when the log holds several recording sessions, so a front end can explain the choice in its own terms.
    public let sessionCount: Int?
    public init(_ message: String, sessionCount: Int? = nil) {
        self.message = message
        self.sessionCount = sessionCount
    }
    public var description: String { message }
    public var errorDescription: String? { message }
}

public enum VideoMode {
    static let ntscRates: [String: Rational] = [
        "2398": Rational(24000, 1001), "23.98": Rational(24000, 1001), "23.976": Rational(24000, 1001),
        "2997": Rational(30000, 1001), "29.97": Rational(30000, 1001),
        "5994": Rational(60000, 1001), "59.94": Rational(60000, 1001),
        "4795": Rational(48000, 1001), "47.95": Rational(48000, 1001),
    ]

    /// Lines, interlaced flag, and frame rate for an ATEM `videoMode` such as `1080p60`.
    public static func parse(_ mode: String) throws -> (lines: Int, interlaced: Bool, rate: Rational) {
        let pattern = try! NSRegularExpression(pattern: #"^\s*(\d{3,4})([pPiI])(\d{2,4}(?:\.\d+)?)\s*$"#)
        let range = NSRange(mode.startIndex..., in: mode)
        guard let match = pattern.firstMatch(in: mode, range: range) else {
            throw ConversionError("Unrecognized ATEM videoMode \(pyRepr(mode)).")
        }
        guard let lines = Int(mode[Range(match.range(at: 1), in: mode)!]) else {
            throw ConversionError("Unrecognized ATEM videoMode \(pyRepr(mode)).")
        }
        let scan = mode[Range(match.range(at: 2), in: mode)!].lowercased()
        let rateText = String(mode[Range(match.range(at: 3), in: mode)!])
        var rate: Rational
        if let known = ntscRates[rateText] {
            rate = known
        } else {
            guard let whole = Int(rateText), whole >= 20, whole <= 120 else {
                throw ConversionError("Unsupported frame rate in videoMode \(pyRepr(mode)).")
            }
            rate = Rational(whole)
        }
        if scan == "i" { rate = rate / Rational(2) }
        return (lines, scan == "i", rate)
    }
}

/// Python `repr()` of a string, for messages that must match the reference converter.
func pyRepr(_ text: String) -> String {
    if text.contains("'") && !text.contains("\"") { return "\"\(text)\"" }
    var out = "'"
    for scalar in text.unicodeScalars {
        switch scalar {
        case "'": out += "\\'"
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\x%02x", scalar.value) }
            else { out.unicodeScalars.append(scalar) }
        }
    }
    return out + "'"
}

/// Frame-accurate SMPTE timecode at a nominal (rounded) frame rate.
public struct Timecode: Sendable {
    public let frames: Int  // real frame index since midnight, drop-frame already resolved
    public let drop: Bool

    static func nominal(_ fps: Rational) -> Int { Int((fps.doubleValue).rounded()) }

    public static func parse(_ label: String, fps: Rational) throws -> Timecode {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = try! NSRegularExpression(pattern: #"^(\d{1,2}):(\d{2}):(\d{2})([:;.,])(\d{1,3})$"#)
        guard let match = pattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            throw ConversionError("Invalid timecode \(pyRepr(label)).")
        }
        func group(_ i: Int) -> String { String(trimmed[Range(match.range(at: i), in: trimmed)!]) }
        guard let h = Int(group(1)), let m = Int(group(2)), let s = Int(group(3)), let f = Int(group(5)) else {
            throw ConversionError("Invalid timecode \(pyRepr(label)).")
        }
        let drop = group(4) == ";" || group(4) == ","
        let nominal = Timecode.nominal(fps)
        if h >= 24 || m >= 60 || s >= 60 || f >= nominal {
            throw ConversionError("Timecode \(pyRepr(label)) is out of range for \(formatG(fps.doubleValue)) fps.")
        }
        var frames = ((h * 60 + m) * 60 + s) * nominal + f
        if drop {
            if fps != Rational(30000, 1001) && fps != Rational(60000, 1001) {
                throw ConversionError("Drop-frame timecode requires a 29.97 or 59.94 fps mode.")
            }
            let dropped = 2 * (nominal / 30)
            if m % 10 != 0 && s == 0 && f < dropped {
                throw ConversionError("Timecode \(pyRepr(label)) names a frame number that drop-frame counting skips.")
            }
            let minutes = h * 60 + m
            frames -= dropped * (minutes - minutes / 10)
        }
        return Timecode(frames: frames, drop: drop)
    }

    public static func framesPerDay(fps: Rational, drop: Bool) -> Int {
        let nominal = Timecode.nominal(fps)
        return nominal * 86400 - (drop ? 2 * (nominal / 30) * 1296 : 0)
    }

    public static func label(_ frames: Int, fps: Rational, drop: Bool) -> String {
        let nominal = Timecode.nominal(fps)
        let day = framesPerDay(fps: fps, drop: drop)
        var frames = ((frames % day) + day) % day
        if drop && nominal % 30 == 0 {
            let dropped = 2 * (nominal / 30)
            let perMinute = nominal * 60 - dropped
            let perTen = perMinute * 10 + dropped
            let tens = frames / perTen, rest = frames % perTen
            let extra = rest < dropped ? 0 : (rest - dropped) / perMinute
            frames += dropped * (tens * 9 + extra)
        }
        let f = frames % nominal
        let total = frames / nominal
        let sep = drop ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", total / 3600, total % 3600 / 60, total % 60, sep, f)
    }
}
