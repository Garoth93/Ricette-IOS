import Foundation

/// The ingredient pool: built-in seed (with the user's edits and hidden
/// entries) plus the ingredients added by the user.
public enum Catalog {
    /// Parsed once.
    public static let seed: [CatalogIngredient] = parse(SeedTable.lines)

    static func parse(_ table: String) -> [CatalogIngredient] {
        var seen = Set<String>()
        var out: [CatalogIngredient] = []
        for raw in table.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard f.count >= 3, let cat = categoryCode[f[1]], let unit = CookUnit(rawValue: f[2]) else { continue }
            let id = "seed." + slug(f[0])
            guard seen.insert(id).inserted else { continue }
            let density = f.count > 3 ? Double(f[3]) : nil
            let flags = f.count > 4 ? f[4] : ""
            out.append(CatalogIngredient(id: id, name: f[0], category: cat, unit: unit, density: density,
                                         wholeOnly: flags.contains("w"), scales: !flags.contains("n")))
        }
        return out
    }

    static let categoryCode: [String: IngredientCategory] = [
        "vegetables": .vegetables, "fruit": .fruit, "herbs": .herbs, "meat": .meat, "fish": .fish, "dairy": .dairy,
        "flour": .flours, "pasta": .pasta, "legumes": .legumes, "nuts": .nuts, "baking": .baking, "oil": .oils,
        "sauces": .sauces, "drinks": .drinks, "other": .other
    ]

    /// "Farina 00" → "farina-00", "Fiocchi d'avena" → "fiocchi-d-avena".
    public static func slug(_ s: String) -> String {
        let n = Search.normalize(s)
        var out = ""
        var dash = false
        for ch in n {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                dash = false
            } else if !dash, !out.isEmpty {
                out.append("-")
                dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// The pool as the user sees it.
    public static func pool(_ data: RicettarioData) -> [CatalogIngredient] {
        let hidden = Set(data.hiddenSeeds)
        let seeds = seed.filter { !hidden.contains($0.id) }.map { data.seedOverrides[$0.id] ?? $0 }
        return (seeds + data.customIngredients).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func item(_ id: String, in data: RicettarioData) -> CatalogIngredient? {
        if let c = data.customIngredients.first(where: { $0.id == id }) { return c }
        if let o = data.seedOverrides[id] { return o }
        return seed.first { $0.id == id }
    }

    /// Pool search: prefix matches first, then word prefix, then contains.
    public static func search(_ query: String, in pool: [CatalogIngredient], category: IngredientCategory? = nil) -> [CatalogIngredient] {
        let base = category.map { c in pool.filter { $0.category == c } } ?? pool
        let q = Search.normalize(query)
        guard !q.isEmpty else { return base }
        var scored: [(Int, CatalogIngredient)] = []
        for item in base {
            let n = Search.normalize(item.name)
            if n == q { scored.append((0, item)) }
            else if n.hasPrefix(q) { scored.append((1, item)) }
            else if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { scored.append((2, item)) }
            else if n.contains(q) { scored.append((3, item)) }
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name.count < $1.1.name.count }.map(\.1)
    }

    /// An ingredient with the same name already in the pool (adding by hand).
    public static func existing(named name: String, in pool: [CatalogIngredient]) -> CatalogIngredient? {
        let q = Search.normalize(name)
        return pool.first { Search.normalize($0.name) == q }
    }

    /// How many recipes use a pool entry.
    public static func usage(of id: String, in data: RicettarioData) -> Int {
        data.recipes.filter { $0.ingredients.contains { $0.catalogID == id } }.count
    }
}

// MARK: - Search and filters

public enum Search {
    /// Lowercase, no accents, trimmed.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RecipeQuery: Equatable, Sendable {
    public var text: String
    public var tags: Set<String>
    public var favoritesOnly: Bool
    public var sort: RecipeSort

    public init(text: String = "", tags: Set<String> = [], favoritesOnly: Bool = false, sort: RecipeSort = .recent) {
        self.text = text
        self.tags = tags
        self.favoritesOnly = favoritesOnly
        self.sort = sort
    }

    /// Every word of the text must appear in title, tags, ingredients or
    /// notes; every selected tag must be on the recipe.
    public func matches(_ r: Recipe) -> Bool {
        if favoritesOnly, !r.favorite { return false }
        let recipeTags = Set(r.tags.map(Search.normalize))
        for t in tags where !recipeTags.contains(Search.normalize(t)) { return false }
        let words = Search.normalize(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = Search.normalize(([r.title, r.notes, r.source] + r.tags + r.ingredients.map(\.name)).joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    public func apply(_ recipes: [Recipe]) -> [Recipe] {
        let f = recipes.filter(matches)
        switch sort {
        case .recent: return f.sorted { $0.updatedAt > $1.updatedAt }
        case .alphabetical: return f.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .lastCooked: return f.sorted { ($0.lastCookedAt ?? .distantPast, $0.updatedAt) > ($1.lastCookedAt ?? .distantPast, $1.updatedAt) }
        case .mostCooked: return f.sorted { ($0.timesCooked, $0.updatedAt) > ($1.timesCooked, $1.updatedAt) }
        }
    }
}

public enum Tags {
    /// "Primi, veloci ,  vegetariano" → ["Primi", "veloci", "vegetariano"]
    /// (trimmed, no duplicates ignoring case and accents).
    public static func parse(_ s: String) -> [String] {
        clean(s.split(whereSeparator: { $0 == "," || $0 == "#" }).map(String.init))
    }

    public static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty, seen.insert(Search.normalize(v)).inserted { out.append(v) }
        }
        return out
    }
}

// MARK: - Timers in the text

public enum TimerDetector {
    /// Suggests a timer from the step text: "cuoci per 10 minuti" → 600,
    /// "1 ora e 30 minuti" → 5400, "45 secondi" → 45. nil when no duration.
    public static func detect(_ text: String) -> Int? {
        let words = Search.normalize(text)
            .map { $0.isLetter || $0.isNumber || $0 == "," || $0 == "." ? $0 : " " }
        let tokens = String(words).split(separator: " ").map(String.init)
        var total = 0
        var found = false
        var i = 0
        while i < tokens.count {
            if let v = number(tokens[i]), i + 1 < tokens.count {
                var unitIndex = i + 1
                var value = v
                // "10-12 minuti" / "10 o 12 minuti": take the upper bound.
                if ["o", "-", "a"].contains(tokens[unitIndex]), unitIndex + 1 < tokens.count, let w = number(tokens[unitIndex + 1]) {
                    value = w
                    unitIndex += 2
                } else if let w = number(tokens[unitIndex]), unitIndex + 1 < tokens.count {
                    value = w
                    unitIndex += 1
                }
                guard unitIndex < tokens.count else { break }
                let u = tokens[unitIndex]
                if u == "ora" || u == "ore" || u == "h" { total += Int(value * 3600); found = true; i = unitIndex + 1; continue }
                if u.hasPrefix("minut") || u == "min" { total += Int(value * 60); found = true; i = unitIndex + 1; continue }
                if u.hasPrefix("second") || u == "sec" { total += Int(value); found = true; i = unitIndex + 1; continue }
            } else if tokens[i] == "mezz" || tokens[i] == "mezzora" {
                total += 1800; found = true
            } else if tokens[i] == "un" || tokens[i] == "una", i + 1 < tokens.count, tokens[i + 1] == "ora" || tokens[i + 1] == "minuto" {
                total += tokens[i + 1] == "ora" ? 3600 : 60; found = true; i += 2; continue
            }
            i += 1
        }
        return found && total > 0 ? total : nil
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
}
