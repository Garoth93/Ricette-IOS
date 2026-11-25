import Foundation

/// An ingredient amount after scaling.
public struct ScaledIngredient: Equatable, Identifiable, Sendable {
    public var ingredient: RecipeIngredient
    /// Exact scaled amount (base units); nil = q.b.
    public var exact: Double?
    /// Amount to use: equal to `exact`, or rounded for counted ingredients.
    public var amount: Double?
    public var id: UUID { ingredient.id }

    /// Counted ingredient rounded away from the exact value (e.g. 2,7 → 3 uova).
    public var isRounded: Bool {
        guard let e = exact, let a = amount else { return false }
        return abs(e - a) > 0.009
    }

    /// The ingredient does not follow the factor (q.b., "non scala").
    public var isFixed: Bool { exact == nil || !ingredient.scales }
}

public enum PieceRounding {
    /// Smart rounding of counted ingredients: whole units for eggs and the
    /// like, halves otherwise; never below one unit (or half) when the exact
    /// amount is above zero.
    public static func round(_ exact: Double, wholeOnly: Bool) -> Double {
        guard exact > 0 else { return 0 }
        if wholeOnly { return max(1, exact.rounded()) }
        return max(0.5, (exact * 2).rounded() / 2)
    }
}

/// "Usa ricetta": a temporary scaled view of a recipe. The original is
/// never modified; the session lives in memory and is lost when closed,
/// unless saved as a variant (a new recipe).
public struct ScaleSession: Equatable, Sendable {
    public static let minFactor = 0.01
    public static let maxFactor = 100.0

    public let original: Recipe
    public private(set) var factor: Double
    /// Ingredient the last factor was derived from (shown as "àncora").
    public private(set) var anchorID: UUID?

    public init(recipe: Recipe, factor: Double = 1) {
        original = recipe
        self.factor = Self.clamp(factor)
    }

    static func clamp(_ f: Double) -> Double {
        guard f.isFinite else { return 1 }
        return min(maxFactor, max(minFactor, f))
    }

    public var isScaled: Bool { abs(factor - 1) > 0.0001 }

    /// People the scaled recipe is for (may be fractional: 4 × 0,75 = 3).
    public var servings: Double { Double(original.servings) * factor }

    public mutating func reset() {
        factor = 1
        anchorID = nil
    }

    /// Changing the people: factor = new / original.
    public mutating func setServings(_ n: Double) {
        guard n > 0 else { return }
        factor = Self.clamp(n / Double(original.servings))
        anchorID = nil
    }

    /// Changing one ingredient ("àncora"): factor = new amount / original
    /// amount (4 uova → 3 = 0,75). `newAmount` is in base units. Ignored for
    /// q.b. or non-scaling ingredients.
    public mutating func setAnchor(_ id: UUID, newAmount: Double) {
        guard let ing = original.ingredient(id), ing.scales, let old = ing.amount, old > 0, newAmount > 0 else { return }
        factor = Self.clamp(newAmount / old)
        anchorID = id
    }

    /// ± one unit on a counted ingredient, starting from the amount shown.
    public mutating func step(_ id: UUID, by delta: Double) {
        guard let s = scaled(id), let shown = s.amount else { return }
        let unit = s.ingredient.wholeOnly ? 1.0 : 0.5
        let next = shown + delta * unit
        guard next > 0 else { return }
        setAnchor(id, newAmount: next)
    }

    public func scaled(_ ing: RecipeIngredient) -> ScaledIngredient {
        guard let base = ing.amount else { return ScaledIngredient(ingredient: ing, exact: nil, amount: nil) }
        guard ing.scales else { return ScaledIngredient(ingredient: ing, exact: base, amount: base) }
        let exact = base * factor
        let amount = ing.kind == .count ? PieceRounding.round(exact, wholeOnly: ing.wholeOnly) : exact
        return ScaledIngredient(ingredient: ing, exact: exact, amount: amount)
    }

    public func scaled(_ id: UUID) -> ScaledIngredient? { original.ingredient(id).map(scaled) }

    public var ingredients: [ScaledIngredient] { original.ingredients.map(scaled) }

    /// Counted ingredients whose rounding differs from the exact value.
    public var roundingNotes: [ScaledIngredient] { ingredients.filter(\.isRounded) }

    /// Amount for a step reference: fraction of the scaled amount. Counted
    /// ingredients use the rounded amount (what is really in the bowl).
    public func amount(for id: UUID, fraction: Double) -> Double? {
        guard let s = scaled(id), let a = s.amount else { return nil }
        return a * fraction
    }

    /// "Salva come variante": a new recipe with the scaled amounts (counted
    /// ingredients rounded) and the people rounded to a whole number.
    public func makeVariant(title: String? = nil, now: Date = Date()) -> Recipe {
        var r = original.duplicated(title: title ?? defaultVariantTitle, now: now)
        r.variantOf = original.id
        r.servings = max(1, Int(servings.rounded()))
        r.ingredients = ingredients.map { s in
            var i = s.ingredient
            if let a = s.amount { i.amount = i.kind == .count ? a : (a * 100).rounded() / 100 }
            return i
        }
        return r
    }

    public var defaultVariantTitle: String {
        let n = servings
        let people = abs(n - n.rounded()) < 0.01 ? "\(Int(n.rounded()))" : Fmt.number(n, digits: 1)
        return "\(original.displayTitle) (\(people) \(people == "1" ? "persona" : "persone"))"
    }
}

// MARK: - Rendering

/// A step ready to show: text pieces and resolved ingredient references.
public struct RenderedSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case text, ingredient, missing }
    public var kind: Kind
    public var text: String
    public var ingredientID: UUID?
}

public enum StepRenderer {
    /// Resolves the references of a step with the session amounts:
    /// "Aggiungi {1/2 Farina}" → "Aggiungi " + "125 g di farina".
    public static func render(_ text: String, session: ScaleSession, prefs: UnitPreferences) -> [RenderedSegment] {
        StepText.parse(text).map { seg in
            switch seg {
            case .text(let s): return RenderedSegment(kind: .text, text: s, ingredientID: nil)
            case .ingredient(let id, let f):
                guard let ing = session.original.ingredient(id) else {
                    return RenderedSegment(kind: .missing, text: "(ingrediente rimosso)", ingredientID: id)
                }
                return RenderedSegment(kind: .ingredient, text: phrase(ing, amount: session.amount(for: id, fraction: f), fraction: f, prefs: prefs), ingredientID: id)
            }
        }
    }

    public static func plain(_ text: String, session: ScaleSession, prefs: UnitPreferences) -> String {
        render(text, session: session, prefs: prefs).map(\.text).joined()
    }

    /// "125 g di farina", "2 uova", "sale q.b.", "1 spicchio di aglio".
    public static func phrase(_ ing: RecipeIngredient, amount: Double?, fraction: Double = 1, prefs: UnitPreferences) -> String {
        let name = lowerFirst(ing.name)
        guard let amount else {
            if abs(fraction - 1) > 0.0001, let w = Fraction.words(fraction) { return "\(w) del \(name) q.b." }
            return "\(name) q.b."
        }
        let q = UnitConverter.display(base: amount, entryUnit: ing.unit, density: ing.density, prefs: prefs)
        if q.unit == .piece { return "\(q.text) \(name)" }
        let p = preposition(name)
        return p == "d'" ? "\(q.text) d'\(name)" : "\(q.text) di \(name)"
    }

    /// "di" / "d'" before vowels.
    static func preposition(_ name: String) -> String {
        guard let f = name.first.map({ String($0).lowercased() }) else { return "di" }
        return "aeiouàèéìòù".contains(f) ? "d'" : "di"
    }

    static func lowerFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        // Keep acronyms and proper names written in capitals ("DOP", "Grana Padano").
        let words = s.split(separator: " ")
        if let w = words.first, w.count > 1, w.allSatisfy({ $0.isUppercase }) { return s }
        if words.count > 1, words.dropFirst().contains(where: { $0.first?.isUppercase == true }) { return s }
        return f.lowercased() + s.dropFirst()
    }
}

