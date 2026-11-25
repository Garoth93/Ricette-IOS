import Foundation

public enum ShoppingList {
    /// Key used to merge lines: pool id (or name) + kind of quantity.
    static func key(name: String, catalogID: String?, kind: QuantityKind) -> String {
        "\(catalogID ?? "name." + Search.normalize(name))#\(kind.rawValue)"
    }

    /// Adds the (scaled) ingredients of a recipe to the list. Lines of the
    /// same ingredient still to buy are summed (same kind of quantity;
    /// mass and volume are merged when the density is known).
    public static func add(_ ingredients: [ScaledIngredient], recipeTitle: String, to list: [ShoppingItem],
                           categories: (RecipeIngredient) -> IngredientCategory) -> [ShoppingItem] {
        var out = list
        for s in ingredients {
            let ing = s.ingredient
            guard !ing.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let i = mergeIndex(for: ing, in: out) {
                var item = out[i]
                if let a = s.amount, item.amount == nil {
                    item.amount = a
                    item.unit = ing.unit
                    item.density = ing.density ?? item.density
                } else if let a = s.amount {
                    let add = sameKind(item.unit.kind, ing.kind) ? a : (convert(a, from: ing.kind, to: item.unit.kind, density: ing.density ?? item.density) ?? 0)
                    item.amount = (item.amount ?? 0) + add
                }
                if !item.sources.contains(recipeTitle) { item.sources.append(recipeTitle) }
                out[i] = item
            } else {
                out.append(ShoppingItem(name: ing.name, catalogID: ing.catalogID, amount: s.amount, unit: ing.unit,
                                        density: ing.density, category: categories(ing), sources: [recipeTitle]))
            }
        }
        return out
    }

    static func sameKind(_ a: QuantityKind, _ b: QuantityKind) -> Bool { a == b }

    static func convert(_ v: Double, from: QuantityKind, to: QuantityKind, density: Double?) -> Double? {
        guard let d = density, d > 0 else { return nil }
        switch (from, to) {
        case (.volume, .mass): return v * d
        case (.mass, .volume): return v / d
        default: return nil
        }
    }

    static func mergeIndex(for ing: RecipeIngredient, in list: [ShoppingItem]) -> Int? {
        let name = Search.normalize(ing.name)
        return list.firstIndex { item in
            guard !item.checked else { return false }
            let same = (ing.catalogID != nil && item.catalogID == ing.catalogID) || Search.normalize(item.name) == name
            guard same else { return false }
            if item.amount == nil || ing.amount == nil { return true }
            if item.unit.kind == ing.kind { return true }
            let d = ing.density ?? item.density
            return item.unit.kind != .count && ing.kind != .count && (d ?? 0) > 0
        }
    }

    /// Sorted for the shop: by category (in the order of the enum), then name.
    public static func grouped(_ items: [ShoppingItem]) -> [(IngredientCategory, [ShoppingItem])] {
        let order = Dictionary(uniqueKeysWithValues: IngredientCategory.allCases.enumerated().map { ($1, $0) })
        let groups = Dictionary(grouping: items, by: \.category)
        return groups.keys.sorted { order[$0]! < order[$1]! }.map { cat in
            (cat, groups[cat]!.sorted {
                if $0.checked != $1.checked { return !$0.checked }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        }
    }

    public static func amountText(_ item: ShoppingItem, prefs: UnitPreferences) -> String? {
        guard let a = item.amount, a > 0 else { return nil }
        return UnitConverter.display(base: a, entryUnit: item.unit, density: item.density, prefs: prefs).text
    }

    /// Text to share (only items still to buy).
    public static func text(_ items: [ShoppingItem], prefs: UnitPreferences) -> String {
        var lines = ["Lista della spesa"]
        for (cat, group) in grouped(items.filter { !$0.checked }) {
            lines.append("")
            lines.append(cat.title.uppercased())
            for item in group {
                if let q = amountText(item, prefs: prefs) { lines.append("• \(item.name) — \(q)") } else { lines.append("• \(item.name)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Recipe as text

public enum RecipeText {
    /// Plain text of a (possibly scaled) recipe, for sharing or printing.
    public static func plain(_ session: ScaleSession, prefs: UnitPreferences) -> String {
        let r = session.original
        var lines: [String] = ["\(r.emoji) \(r.displayTitle)"]
        let people = session.isScaled ? Fmt.number(session.servings, digits: 1) : "\(r.servings)"
        var meta = ["Per \(people) \(people == "1" ? "persona" : "persone")"]
        if let p = r.prepMinutes { meta.append("Preparazione \(Fmt.duration(p * 60))") }
        if let c = r.cookMinutes { meta.append("Cottura \(Fmt.duration(c * 60))") }
        lines.append(meta.joined(separator: " · "))
        if !r.tags.isEmpty { lines.append(r.tags.map { "#\($0)" }.joined(separator: " ")) }
        if !r.ingredients.isEmpty {
            lines.append("")
            lines.append("INGREDIENTI")
            for s in session.ingredients {
                lines.append("• " + line(s, prefs: prefs))
            }
        }
        if !r.steps.isEmpty {
            lines.append("")
            lines.append("PROCEDIMENTO")
            for (i, step) in r.steps.enumerated() {
                var t = "\(i + 1). " + StepRenderer.plain(step.text, session: session, prefs: prefs)
                if let sec = step.timerSeconds { t += " ⏱ \(Fmt.duration(sec))" }
                lines.append(t)
            }
        }
        if !r.notes.isEmpty {
            lines.append("")
            lines.append("NOTE")
            lines.append(r.notes)
        }
        if !r.source.isEmpty { lines.append("Fonte: \(r.source)") }
        return lines.joined(separator: "\n")
    }

    /// "Farina 00 — 250 g", "Sale fino — q.b.".
    public static func line(_ s: ScaledIngredient, prefs: UnitPreferences) -> String {
        let ing = s.ingredient
        var t = ing.name
        if let a = s.amount {
            t += " — " + UnitConverter.display(base: a, entryUnit: ing.unit, density: ing.density, prefs: prefs).text
        } else {
            t += " — q.b."
        }
        if !ing.note.isEmpty { t += " (\(ing.note))" }
        return t
    }
}
