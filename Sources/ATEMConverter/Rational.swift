import Foundation

/// Exact rational seconds, mirroring Python's `fractions.Fraction` as the converter uses it.
///
/// Values are stored as `Int` but every operation computes in `Int128` and reduces before narrowing, so
/// products of the supported media values (see `MediaLimits`) cannot overflow. A result that still does not
/// fit `Int` stops the program rather than wrapping; the media limits make that unreachable.
public struct Rational: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        self.init(wide: Int128(numerator), Int128(denominator))
    }

    private init(wide numerator: Int128, _ denominator: Int128) {
        precondition(denominator != 0, "zero denominator")
        var n = numerator, d = denominator
        if d < 0 { n = -n; d = -d }
        let g = Rational.gcd(n < 0 ? -n : n, d)
        if g > 1 { n /= g; d /= g }
        guard let narrowN = Int(exactly: n), let narrowD = Int(exactly: d) else {
            preconditionFailure("rational value exceeds the supported range")
        }
        self.numerator = narrowN
        self.denominator = narrowD
    }

    private static func gcd(_ a: Int128, _ b: Int128) -> Int128 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    private var n: Int128 { Int128(numerator) }
    private var d: Int128 { Int128(denominator) }

    public var isInteger: Bool { denominator == 1 }
    public var doubleValue: Double { Double(numerator) / Double(denominator) }

    /// FCPXML time form: `2798s` or `1001/60000s`.
    public var fcpxml: String { denominator == 1 ? "\(numerator)s" : "\(numerator)/\(denominator)s" }
    public var description: String { fcpxml }

    public static func + (a: Rational, b: Rational) -> Rational { Rational(wide: a.n * b.d + b.n * a.d, a.d * b.d) }
    public static func - (a: Rational, b: Rational) -> Rational { Rational(wide: a.n * b.d - b.n * a.d, a.d * b.d) }
    public static func * (a: Rational, b: Rational) -> Rational { Rational(wide: a.n * b.n, a.d * b.d) }
    public static func / (a: Rational, b: Rational) -> Rational { Rational(wide: a.n * b.d, a.d * b.n) }
    public static func * (a: Int, b: Rational) -> Rational { Rational(wide: Int128(a) * b.n, b.d) }
    public static func * (a: Rational, b: Int) -> Rational { Rational(wide: a.n * Int128(b), a.d) }
    public static func < (a: Rational, b: Rational) -> Bool { a.n * b.d < b.n * a.d }
    public static prefix func - (a: Rational) -> Rational { Rational(wide: -a.n, a.d) }
    public var magnitude: Rational { numerator < 0 ? -self : self }
    public static let zero = Rational(0)
}

/// Python's `"%g"` formatting of a float, as used in warnings and the summary.
func formatG(_ value: Double) -> String { String(format: "%g", value) }
