import Foundation

/// Ingredient references inside the text of a step.
///
/// Stored form: `{{ing:<uuid>}}` (whole amount) or `{{ing:<uuid>|0.5}}`
/// (a fraction of it). Ids never change, so renaming an ingredient keeps
/// the reference. The editor shows a readable form instead:
/// `{Farina}`, `{1/2 Farina}`, `{30% Farina}`.
public enum StepSegment: Equatable, Sendable {
    case text(String)
    case ingredient(id: UUID, fraction: Double)
}

public enum StepText {
    static let open = "{{ing:"
    static let close = "}}"

    /// Stored token for an ingredient (fraction 1 = whole amount).
    public static func token(_ id: UUID, fraction: Double = 1) -> String {
        if abs(fraction - 1) < 0.0001 { return "\(open)\(id.uuidString)\(close)" }
        return "\(open)\(id.uuidString)|\(Fmt.number(fraction, digits: 4).replacingOccurrences(of: ",", with: "."))\(close)"
    }

    /// Splits stored text into plain text and ingredient references.
    public static func parse(_ text: String) -> [StepSegment] {
        var out: [StepSegment] = []
        var rest = Substring(text)
        var buffer = ""
        while let r = rest.range(of: open) {
            buffer += rest[rest.startIndex..<r.lowerBound]
            let after = rest[r.upperBound...]
            guard let end = after.range(of: close) else {
                buffer += rest[r.lowerBound...]
                rest = ""
                break
            }
            let body = after[after.startIndex..<end.lowerBound]
            let parts = body.split(separator: "|", maxSplits: 1).map(String.init)
            if let first = parts.first, let id = UUID(uuidString: first) {
                let frac = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
                if !buffer.isEmpty { out.append(.text(buffer)); buffer = "" }
                out.append(.ingredient(id: id, fraction: frac > 0 ? frac : 1))
            } else {
                buffer += rest[r.lowerBound..<end.upperBound]
            }
            rest = after[end.upperBound...]
        }
        buffer += rest
        if !buffer.isEmpty { out.append(.text(buffer)) }
        return out
    }

    /// Ids referenced by a stored text.
    public static func references(_ text: String) -> [UUID] {
        parse(text).compactMap { if case .ingredient(let id, _) = $0 { return id } else { return nil } }
    }

    /// Removes references to ingredients that no longer exist, writing
    /// their last known name instead (kept readable).
    public static func dropMissing(_ text: String, keep ids: Set<UUID>, names: [UUID: String] = [:]) -> String {
        parse(text).map { seg -> String in
            switch seg {
            case .text(let s): return s
            case .ingredient(let id, let f):
                if ids.contains(id) { return token(id, fraction: f) }
                return names[id] ?? ""
            }
        }.joined()
    }

    // MARK: Editable form

    /// Unique display names: duplicates get " (2)", " (3)"…
    public static func editorNames(_ ingredients: [RecipeIngredient]) -> [UUID: String] {
        var count: [String: Int] = [:]
        var out: [UUID: String] = [:]
        for ing in ingredients {
            let base = ing.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Ingrediente" : ing.name.trimmingCharacters(in: .whitespaces)
            let k = Search.normalize(base)
            let n = (count[k] ?? 0) + 1
            count[k] = n
            out[ing.id] = n == 1 ? base : "\(base) (\(n))"
        }
        return out
    }

    /// "1/2", "30%": short fraction label for the editor and the menus.
    public static func fractionLabel(_ f: Double) -> String {
        for (v, label) in Fraction.common where abs(v - f) < 0.0005 { return label }
        return "\(Fmt.number(f * 100, digits: 1))%"
    }

    /// Readable token for the editor: "{Farina}", "{1/2 Farina}".
    public static func editorToken(name: String, fraction: Double) -> String {
        abs(fraction - 1) < 0.0001 ? "{\(name)}" : "{\(fractionLabel(fraction)) \(name)}"
    }

    /// Stored → editable text.
    public static func editable(_ stored: String, ingredients: [RecipeIngredient]) -> String {
        let names = editorNames(ingredients)
        return parse(stored).map { seg -> String in
            switch seg {
            case .text(let s): return s
            case .ingredient(let id, let f):
                guard let n = names[id] else { return "" }
                return editorToken(name: n, fraction: f)
            }
        }.joined()
    }

    /// Editable → stored text. `{…}` blocks whose name matches an
    /// ingredient become references; anything else stays as typed.
    public static func stored(_ editable: String, ingredients: [RecipeIngredient]) -> String {
        let names = editorNames(ingredients)
        var byName: [String: UUID] = [:]
        for ing in ingredients {
            if let n = names[ing.id] { byName[Search.normalize(n)] = ing.id }
        }
        // Plain names also match the first ingredient with that name.
        for ing in ingredients where byName[Search.normalize(ing.name)] == nil {
            byName[Search.normalize(ing.name)] = ing.id
        }
        var out = ""
        var rest = Substring(editable)
        while let o = rest.firstIndex(of: "{") {
            out += rest[rest.startIndex..<o]
            let after = rest[rest.index(after: o)...]
            guard let c = after.firstIndex(of: "}"), !after[after.startIndex..<c].contains("{") else {
                out += "{"
                rest = after
                continue
            }
            let inner = String(after[after.startIndex..<c]).trimmingCharacters(in: .whitespaces)
            if let (id, f) = resolve(inner, byName: byName) {
                out += token(id, fraction: f)
            } else {
                out += "{\(inner)}"
            }
            rest = after[after.index(after: c)...]
        }
        out += rest
        return out
    }

    private static func resolve(_ inner: String, byName: [String: UUID]) -> (UUID, Double)? {
        if let id = byName[Search.normalize(inner)] { return (id, 1) }
        let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let f = Fraction.parse(parts[0]), f > 0,
              let id = byName[Search.normalize(parts[1])] else { return nil }
        return (id, f)
    }
}

public enum Fraction {
    /// Fractions offered by the "insert ingredient" menu.
    public static let common: [(Double, String)] = [
        (1, "tutto"), (0.75, "3/4"), (2.0 / 3, "2/3"), (0.5, "1/2"), (1.0 / 3, "1/3"), (0.25, "1/4"), (0.2, "1/5"), (0.125, "1/8")
    ]

    /// "1/2", "50%", "0,5" → 0.5.
    public static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("%"), let v = Double(t.dropLast().replacingOccurrences(of: ",", with: ".")) { return v / 100 }
        let p = t.split(separator: "/")
        if p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b != 0 { return a / b }
        if let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0, v <= 1 { return v }
        return nil
    }

    /// "metà", "un terzo"… for the rendered text.
    public static func words(_ f: Double) -> String? {
        let w: [(Double, String)] = [(0.5, "metà"), (1.0 / 3, "un terzo"), (2.0 / 3, "due terzi"), (0.25, "un quarto"), (0.75, "tre quarti")]
        return w.first { abs($0.0 - f) < 0.0005 }?.1
    }
}
