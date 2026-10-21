import Foundation

/// Exact rational seconds, mirroring Python's `fractions.Fraction` as the converter uses it.
public struct Rational: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "zero denominator")
        var n = numerator, d = denominator
        if d < 0 { n = -n; d = -d }
        let g = Rational.gcd(abs(n), d)
        if g > 1 { n /= g; d /= g }
        self.numerator = n
        self.denominator = d
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    public var isInteger: Bool { denominator == 1 }
    public var doubleValue: Double { Double(numerator) / Double(denominator) }

    /// FCPXML time form: `2798s` or `1001/60000s`.
    public var fcpxml: String { denominator == 1 ? "\(numerator)s" : "\(numerator)/\(denominator)s" }
    public var description: String { fcpxml }

    public static func + (a: Rational, b: Rational) -> Rational { Rational(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator) }
    public static func - (a: Rational, b: Rational) -> Rational { Rational(a.numerator * b.denominator - b.numerator * a.denominator, a.denominator * b.denominator) }
    public static func * (a: Rational, b: Rational) -> Rational { Rational(a.numerator * b.numerator, a.denominator * b.denominator) }
    public static func / (a: Rational, b: Rational) -> Rational { Rational(a.numerator * b.denominator, a.denominator * b.numerator) }
    public static func * (a: Int, b: Rational) -> Rational { Rational(a * b.numerator, b.denominator) }
    public static func * (a: Rational, b: Int) -> Rational { Rational(a.numerator * b, a.denominator) }
    public static func < (a: Rational, b: Rational) -> Bool { a.numerator * b.denominator < b.numerator * a.denominator }
    public static prefix func - (a: Rational) -> Rational { Rational(-a.numerator, a.denominator) }
    public var magnitude: Rational { numerator < 0 ? -self : self }
    public static let zero = Rational(0)
}

/// Python's `"%g"` formatting of a float, as used in warnings and the summary.
func formatG(_ value: Double) -> String { String(format: "%g", value) }
