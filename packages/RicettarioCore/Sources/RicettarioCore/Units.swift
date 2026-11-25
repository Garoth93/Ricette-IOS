import Foundation

/// What a quantity measures. Amounts are stored in the base unit of their
/// kind: grams (mass), millilitres (volume), number of units (count).
public enum QuantityKind: String, Codable, CaseIterable, Sendable {
    case mass, volume, count
}

/// Units the user can type. Mass and volume units convert to each other
/// within their kind (and across kinds with a density); count units are
/// independent ("2 spicchi", "3 fette").
public enum CookUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case g, kg, mg, ml, cl, dl, l
    case tsp, tbsp, cup, floz
    case oz, lb
    case piece, clove, slice, leaf, sprig, pinch, can, pack, bunch, glass

    public var id: String { rawValue }

    public var kind: QuantityKind {
        switch self {
        case .g, .kg, .mg, .oz, .lb: return .mass
        case .ml, .cl, .dl, .l, .tsp, .tbsp, .cup, .floz: return .volume
        default: return .count
        }
    }

    /// Size of one unit in the base unit of its kind (g, ml, 1 for counts).
    public func toBase(cupML: Double = UnitPreferences.defaultCupML) -> Double {
        switch self {
        case .g: return 1
        case .kg: return 1000
        case .mg: return 0.001
        case .oz: return 28.349523125
        case .lb: return 453.59237
        case .ml: return 1
        case .cl: return 10
        case .dl: return 100
        case .l: return 1000
        case .tsp: return 5
        case .tbsp: return 15
        case .cup: return cupML
        case .floz: return 29.5735295625
        default: return 1
        }
    }

    public var isImperial: Bool { [.oz, .lb, .floz, .cup].contains(self) }
    public var isSpoonOrCup: Bool { [.tsp, .tbsp, .cup].contains(self) }
    /// Shown with fractions (½, ¼…) rather than decimals.
    public var prefersFractions: Bool { [.tsp, .tbsp, .cup, .oz, .lb, .floz].contains(self) || kind == .count }

    /// Italian label for an amount (singular when the amount is 1 or less).
    public func label(for amount: Double) -> String {
        let one = amount <= 1.0001
        switch self {
        case .g: return "g"
        case .kg: return "kg"
        case .mg: return "mg"
        case .ml: return "ml"
        case .cl: return "cl"
        case .dl: return "dl"
        case .l: return "l"
        case .tsp: return one ? "cucchiaino" : "cucchiaini"
        case .tbsp: return one ? "cucchiaio" : "cucchiai"
        case .cup: return one ? "tazza" : "tazze"
        case .floz: return "fl oz"
        case .oz: return "oz"
        case .lb: return "lb"
        case .piece: return ""
        case .clove: return one ? "spicchio" : "spicchi"
        case .slice: return one ? "fetta" : "fette"
        case .leaf: return one ? "foglia" : "foglie"
        case .sprig: return one ? "rametto" : "rametti"
        case .pinch: return one ? "pizzico" : "pizzichi"
        case .can: return one ? "lattina" : "lattine"
        case .pack: return one ? "confezione" : "confezioni"
        case .bunch: return one ? "mazzetto" : "mazzetti"
        case .glass: return one ? "bicchiere" : "bicchieri"
        }
    }

    /// Name shown in pickers.
    public var pickerName: String {
        switch self {
        case .g: return "grammi (g)"
        case .kg: return "chilogrammi (kg)"
        case .mg: return "milligrammi (mg)"
        case .ml: return "millilitri (ml)"
        case .cl: return "centilitri (cl)"
        case .dl: return "decilitri (dl)"
        case .l: return "litri (l)"
        case .tsp: return "cucchiaini"
        case .tbsp: return "cucchiai"
        case .cup: return "tazze"
        case .floz: return "once liquide (fl oz)"
        case .oz: return "once (oz)"
        case .lb: return "libbre (lb)"
        case .piece: return "pezzi"
        case .clove: return "spicchi"
        case .slice: return "fette"
        case .leaf: return "foglie"
        case .sprig: return "rametti"
        case .pinch: return "pizzichi"
        case .can: return "lattine"
        case .pack: return "confezioni"
        case .bunch: return "mazzetti"
        case .glass: return "bicchieri"
        }
    }

    /// Short name for compact pickers.
    public var shortName: String {
        switch self {
        case .piece: return "pz"
        default: return label(for: 2)
        }
    }

    /// Units offered when typing a quantity, grouped by kind.
    public static let mass: [CookUnit] = [.g, .kg, .mg, .oz, .lb]
    public static let volume: [CookUnit] = [.ml, .cl, .dl, .l, .tsp, .tbsp, .cup, .floz]
    public static let count: [CookUnit] = [.piece, .clove, .slice, .leaf, .sprig, .pinch, .can, .pack, .bunch, .glass]
}

/// How quantities are shown. Amounts are always stored in base units.
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    /// In the unit typed in the recipe (g → kg above 1000).
    case asEntered
    case metric
    case imperial

    public var title: String {
        switch self {
        case .asEntered: return "Come inserite"
        case .metric: return "Metrico (g, ml)"
        case .imperial: return "Imperiale (oz, cup)"
        }
    }
}

public struct UnitPreferences: Codable, Equatable, Sendable {
    public static let defaultCupML = 240.0

    public var system: UnitSystem
    /// Metric: keep teaspoons/tablespoons/cups instead of ml.
    public var keepSpoons: Bool
    /// Use the ingredient density to show volumes as weights (1 tazza di
    /// farina → 120 g in metric, → oz in imperial).
    public var weighVolumes: Bool
    /// Size of one cup in ml (240 US/IT, 250 metric cup).
    public var cupML: Double

    public init(system: UnitSystem = .asEntered, keepSpoons: Bool = true, weighVolumes: Bool = false, cupML: Double = defaultCupML) {
        self.system = system
        self.keepSpoons = keepSpoons
        self.weighVolumes = weighVolumes
        self.cupML = cupML
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        system = c.value(.system, default: .asEntered)
        keepSpoons = c.value(.keepSpoons, default: true)
        weighVolumes = c.value(.weighVolumes, default: false)
        cupML = c.value(.cupML, default: Self.defaultCupML)
    }
}

/// A quantity ready to show: value in `unit` plus the formatted text.
public struct DisplayQuantity: Equatable, Sendable {
    public var value: Double
    public var unit: CookUnit
    /// "250 g", "1 ½ tazze", "3" (pieces have no label).
    public var text: String
}

public enum UnitConverter {
    /// Converts an amount from base units into `unit` (same kind, or across
    /// mass/volume with `density` in g/ml). nil when not convertible.
    public static func convert(base: Double, kind: QuantityKind, to unit: CookUnit, density: Double?, cupML: Double) -> Double? {
        if unit.kind == kind { return base / unit.toBase(cupML: cupML) }
        guard let d = density, d > 0 else { return nil }
        switch (kind, unit.kind) {
        case (.volume, .mass): return base * d / unit.toBase(cupML: cupML)
        case (.mass, .volume): return base / d / unit.toBase(cupML: cupML)
        default: return nil
        }
    }

    /// Amount typed in `unit` → base units of the unit's kind.
    public static func toBase(_ value: Double, unit: CookUnit, cupML: Double) -> Double {
        value * unit.toBase(cupML: cupML)
    }

    /// Chooses the unit and formats a stored amount for display.
    public static func display(base: Double, entryUnit: CookUnit, density: Double?, prefs: UnitPreferences) -> DisplayQuantity {
        let kind = entryUnit.kind
        let unit = displayUnit(base: base, entryUnit: entryUnit, density: density, prefs: prefs)
        let value = convert(base: base, kind: kind, to: unit, density: density, cupML: prefs.cupML) ?? base
        return DisplayQuantity(value: value, unit: unit, text: Fmt.quantity(value, unit: unit))
    }

    static func displayUnit(base: Double, entryUnit: CookUnit, density: Double?, prefs: UnitPreferences) -> CookUnit {
        let kind = entryUnit.kind
        if kind == .count { return entryUnit }
        let canWeigh = prefs.weighVolumes && kind == .volume && (density ?? 0) > 0
        switch prefs.system {
        case .asEntered:
            if canWeigh, entryUnit.isSpoonOrCup || entryUnit == .floz { return metricMass(base * density!) }
            switch entryUnit {
            case .g, .kg: return metricMass(base)
            case .ml, .l: return base >= 1000 ? .l : .ml
            default: return entryUnit
            }
        case .metric:
            if canWeigh { return metricMass(base * density!) }
            if kind == .mass { return metricMass(base) }
            if prefs.keepSpoons, entryUnit.isSpoonOrCup { return entryUnit }
            return base >= 1000 ? .l : .ml
        case .imperial:
            if canWeigh { return base * density! >= 453.59237 ? .lb : .oz }
            if kind == .mass { return base >= 453.59237 ? .lb : .oz }
            if base < 15 { return .tsp }
            if base < 60 { return .tbsp }
            return .cup
        }
    }

    static func metricMass(_ grams: Double) -> CookUnit { grams >= 1000 ? .kg : .g }
}

// MARK: - Formatting (Italian, deterministic on every platform)

public enum Fmt {
    /// Italian number: comma decimal separator, at most `digits` decimals,
    /// trailing zeros removed. "1.250" thousands are not grouped on purpose.
    public static func number(_ v: Double, digits: Int = 2) -> String {
        guard v.isFinite else { return "—" }
        let p = pow(10.0, Double(digits))
        let r = (v * p).rounded() / p
        var s = String(format: "%.\(digits)f", r)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    private static let fractions: [(Double, String)] = [
        (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.5, "½"),
        (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.875, "⅞")
    ]

    /// "1 ½", "¾", "2"; nil when the value is not close to a simple fraction.
    public static func fraction(_ v: Double, tolerance: Double = 0.03) -> String? {
        guard v.isFinite, v > 0 else { return v == 0 ? "0" : nil }
        let whole = v.rounded(.down)
        let frac = v - whole
        if frac < tolerance { return String(Int(whole)) }
        if frac > 1 - tolerance { return String(Int(whole) + 1) }
        for (f, glyph) in fractions where abs(frac - f) < tolerance {
            return whole > 0 ? "\(Int(whole)) \(glyph)" : glyph
        }
        return nil
    }

    /// Rounds a value to a sensible precision for its unit.
    public static func nice(_ v: Double, unit: CookUnit) -> Double {
        switch unit {
        case .g, .ml:
            if v < 10 { return (v * 2).rounded() / 2 }
            if v < 250 { return v.rounded() }
            if v < 1000 { return (v / 5).rounded() * 5 }
            return (v / 10).rounded() * 10
        case .kg, .l: return (v * 100).rounded() / 100
        case .mg: return v.rounded()
        case .cl, .dl: return (v * 10).rounded() / 10
        default: return (v * 100).rounded() / 100
        }
    }

    /// Value of a quantity without the unit: fractions for spoons, cups and
    /// counts when they fit, decimals otherwise.
    public static func amount(_ v: Double, unit: CookUnit) -> String {
        let n = nice(v, unit: unit)
        if unit.prefersFractions, let f = fraction(n) { return f }
        switch unit {
        case .g, .ml, .mg: return number(n, digits: 1)
        case .kg, .l: return number(n, digits: 2)
        default: return number(n, digits: 2)
        }
    }

    /// "250 g", "1 ½ tazze", "3".
    public static func quantity(_ v: Double, unit: CookUnit) -> String {
        let a = amount(v, unit: unit)
        let n = nice(v, unit: unit)
        let label = unit.label(for: n)
        return label.isEmpty ? a : "\(a) \(label)"
    }

    /// "1 h 05 min", "12 min", "45 s".
    public static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return m > 0 ? "\(h) h \(String(format: "%02d", m)) min" : "\(h) h" }
        if m > 0 { return sec > 0 ? "\(m) min \(sec) s" : "\(m) min" }
        return "\(sec) s"
    }

    /// Countdown "mm:ss" or "h:mm:ss".
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    /// Parses a typed amount: "250", "1,5", "1.5", "1/2", "1 1/2", "½", "1½".
    public static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let glyphs: [Character: Double] = ["½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]
        var extra = 0.0
        if let last = s.last, let g = glyphs[last] {
            extra = g
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return extra }
        }
        s = s.replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: " ").map(String.init)
        if parts.count == 2, let w = Double(parts[0]), let f = parseSlash(parts[1]) { return w + f + extra }
        if parts.count == 1 {
            if let f = parseSlash(parts[0]) { return f + extra }
            if let d = Double(parts[0]), d.isFinite { return d + extra }
        }
        return nil
    }

    private static func parseSlash(_ s: String) -> Double? {
        let p = s.split(separator: "/")
        guard p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b != 0 else { return nil }
        return a / b
    }
}
