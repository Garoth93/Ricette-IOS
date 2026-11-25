import Foundation

// MARK: - Tolerant decoding helper

extension KeyedDecodingContainer {
    /// Missing or malformed field → default (old files keep opening).
    func value<T: Decodable>(_ key: Key, default value: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? value
    }
}

// MARK: - Ingredient pool

public enum IngredientCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case vegetables, fruit, herbs, meat, fish, dairy, flours, pasta, legumes, nuts, baking, oils, sauces, drinks, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vegetables: return "Verdura"
        case .fruit: return "Frutta"
        case .herbs: return "Erbe e spezie"
        case .meat: return "Carne e salumi"
        case .fish: return "Pesce"
        case .dairy: return "Latticini e uova"
        case .flours: return "Farine e cereali"
        case .pasta: return "Pasta, riso e pane"
        case .legumes: return "Legumi"
        case .nuts: return "Frutta secca e semi"
        case .baking: return "Dolci e lievitanti"
        case .oils: return "Oli, aceti e grassi"
        case .sauces: return "Salse e conserve"
        case .drinks: return "Bevande e alcolici"
        case .other: return "Altro"
        }
    }

    public var icon: String {
        switch self {
        case .vegetables: return "carrot.fill"
        case .fruit: return "apple.logo"
        case .herbs: return "leaf.fill"
        case .meat: return "fork.knife"
        case .fish: return "fish.fill"
        case .dairy: return "oval.portrait.fill"
        case .flours: return "laurel.leading"
        case .pasta: return "takeoutbag.and.cup.and.straw.fill"
        case .legumes: return "circle.grid.3x3.fill"
        case .nuts: return "tree.fill"
        case .baking: return "birthday.cake.fill"
        case .oils: return "drop.fill"
        case .sauces: return "cylinder.fill"
        case .drinks: return "wineglass.fill"
        case .other: return "basket.fill"
        }
    }
}

/// An ingredient of the pool (seed or added by the user).
public struct CatalogIngredient: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// "seed.<slug>" for the built-in pool, "user.<uuid>" for the user's.
    public var id: String
    public var name: String
    public var category: IngredientCategory
    /// Unit proposed when the ingredient is added to a recipe.
    public var unit: CookUnit
    /// g per ml, to convert cups/spoons ↔ grams. Optional.
    public var density: Double?
    /// Counted ingredients that can't be split (eggs): scaling rounds to
    /// whole units. Others (lemons, onions) round to halves.
    public var wholeOnly: Bool
    /// false for salt, pepper…: the amount stays the same when scaling.
    public var scales: Bool

    public var isSeed: Bool { id.hasPrefix("seed.") }

    public init(id: String, name: String, category: IngredientCategory, unit: CookUnit = .g,
                density: Double? = nil, wholeOnly: Bool = false, scales: Bool = true) {
        self.id = id
        self.name = name
        self.category = category
        self.unit = unit
        self.density = density
        self.wholeOnly = wholeOnly
        self.scales = scales
    }

    public static func user(name: String, category: IngredientCategory = .other, unit: CookUnit = .g) -> CatalogIngredient {
        CatalogIngredient(id: "user.\(UUID().uuidString.lowercased())", name: name, category: category, unit: unit)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, default: "")
        category = c.value(.category, default: .other)
        unit = c.value(.unit, default: .g)
        density = c.value(.density, default: nil)
        wholeOnly = c.value(.wholeOnly, default: false)
        scales = c.value(.scales, default: true)
    }
}

// MARK: - Recipe

public struct RecipeIngredient: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Pool entry it came from (nil = typed only in this recipe).
    public var catalogID: String?
    public var name: String
    /// In base units of `unit.kind` (g, ml, count). nil = "q.b.".
    public var amount: Double?
    /// Unit typed by the user (display preference).
    public var unit: CookUnit
    public var scales: Bool
    public var wholeOnly: Bool
    /// g per ml (copied from the pool, editable).
    public var density: Double?
    public var note: String

    public var isToTaste: Bool { amount == nil }
    public var kind: QuantityKind { unit.kind }

    public init(id: UUID = UUID(), catalogID: String? = nil, name: String, amount: Double?, unit: CookUnit,
                scales: Bool = true, wholeOnly: Bool = false, density: Double? = nil, note: String = "") {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.amount = amount
        self.unit = unit
        self.scales = scales
        self.wholeOnly = wholeOnly
        self.density = density
        self.note = note
    }

    /// New recipe ingredient from a pool entry; `value` is in `unit`.
    public init(from item: CatalogIngredient, value: Double?, unit: CookUnit? = nil, cupML: Double = UnitPreferences.defaultCupML) {
        let u = unit ?? item.unit
        self.init(catalogID: item.id, name: item.name,
                  amount: value.map { UnitConverter.toBase($0, unit: u, cupML: cupML) },
                  unit: u, scales: item.scales, wholeOnly: item.wholeOnly, density: item.density)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        catalogID = c.value(.catalogID, default: nil)
        name = c.value(.name, default: "")
        amount = c.value(.amount, default: nil)
        unit = c.value(.unit, default: .g)
        scales = c.value(.scales, default: true)
        wholeOnly = c.value(.wholeOnly, default: false)
        density = c.value(.density, default: nil)
        note = c.value(.note, default: "")
    }
}

/// One page of the method.
public struct RecipeStep: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Free text with ingredient tokens `{{ing:<uuid>}}` / `{{ing:<uuid>|0.5}}`.
    public var text: String
    /// File name in the app's Photos folder.
    public var photo: String?
    public var timerSeconds: Int?

    public init(id: UUID = UUID(), text: String = "", photo: String? = nil, timerSeconds: Int? = nil) {
        self.id = id
        self.text = text
        self.photo = photo
        self.timerSeconds = timerSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        text = c.value(.text, default: "")
        photo = c.value(.photo, default: nil)
        timerSeconds = c.value(.timerSeconds, default: nil)
    }
}

public struct Recipe: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var emoji: String
    public var photo: String?
    /// Number of people the amounts are for (≥ 1).
    public var servings: Int
    public var ingredients: [RecipeIngredient]
    public var steps: [RecipeStep]
    public var tags: [String]
    public var notes: String
    public var source: String
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var favorite: Bool
    /// Recipe it was derived from ("salva come variante").
    public var variantOf: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastCookedAt: Date?
    public var timesCooked: Int

    public init(id: UUID = UUID(), title: String = "", emoji: String = "🍽️", photo: String? = nil, servings: Int = 4,
                ingredients: [RecipeIngredient] = [], steps: [RecipeStep] = [], tags: [String] = [], notes: String = "",
                source: String = "", prepMinutes: Int? = nil, cookMinutes: Int? = nil, favorite: Bool = false,
                variantOf: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), lastCookedAt: Date? = nil, timesCooked: Int = 0) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.photo = photo
        self.servings = max(1, servings)
        self.ingredients = ingredients
        self.steps = steps
        self.tags = tags
        self.notes = notes
        self.source = source
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.favorite = favorite
        self.variantOf = variantOf
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCookedAt = lastCookedAt
        self.timesCooked = timesCooked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        title = c.value(.title, default: "")
        emoji = c.value(.emoji, default: "🍽️")
        photo = c.value(.photo, default: nil)
        servings = max(1, c.value(.servings, default: 4))
        ingredients = c.value(.ingredients, default: [])
        steps = c.value(.steps, default: [])
        tags = c.value(.tags, default: [])
        notes = c.value(.notes, default: "")
        source = c.value(.source, default: "")
        prepMinutes = c.value(.prepMinutes, default: nil)
        cookMinutes = c.value(.cookMinutes, default: nil)
        favorite = c.value(.favorite, default: false)
        variantOf = c.value(.variantOf, default: nil)
        createdAt = c.value(.createdAt, default: Date(timeIntervalSince1970: 0))
        updatedAt = c.value(.updatedAt, default: createdAt)
        lastCookedAt = c.value(.lastCookedAt, default: nil)
        timesCooked = c.value(.timesCooked, default: 0)
    }

    public var displayTitle: String { title.trimmingCharacters(in: .whitespaces).isEmpty ? "Senza titolo" : title }

    /// Photos used by the recipe (cover + steps).
    public var photoNames: [String] { ([photo] + steps.map(\.photo)).compactMap { $0 } }

    public var totalMinutes: Int? {
        let t = (prepMinutes ?? 0) + (cookMinutes ?? 0)
        return t > 0 ? t : nil
    }

    /// Copy with a new id ("Duplica"): same ingredient/step ids (they are
    /// only unique inside a recipe) and same photo files (shared, removed
    /// only when no recipe uses them).
    public func duplicated(title: String? = nil, now: Date = Date()) -> Recipe {
        var r = self
        r.id = UUID()
        r.title = title ?? "\(self.title) (copia)"
        r.createdAt = now
        r.updatedAt = now
        r.lastCookedAt = nil
        r.timesCooked = 0
        r.favorite = false
        return r
    }

    public func ingredient(_ id: UUID) -> RecipeIngredient? { ingredients.first { $0.id == id } }
}

// MARK: - Shopping list

public struct ShoppingItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var catalogID: String?
    /// Base units of `unit.kind`; nil = no amount ("q.b." or typed by hand).
    public var amount: Double?
    public var unit: CookUnit
    public var density: Double?
    public var category: IngredientCategory
    public var checked: Bool
    /// Titles of the recipes the item comes from.
    public var sources: [String]

    public init(id: UUID = UUID(), name: String, catalogID: String? = nil, amount: Double? = nil, unit: CookUnit = .piece,
                density: Double? = nil, category: IngredientCategory = .other, checked: Bool = false, sources: [String] = []) {
        self.id = id
        self.name = name
        self.catalogID = catalogID
        self.amount = amount
        self.unit = unit
        self.density = density
        self.category = category
        self.checked = checked
        self.sources = sources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "")
        catalogID = c.value(.catalogID, default: nil)
        amount = c.value(.amount, default: nil)
        unit = c.value(.unit, default: .piece)
        density = c.value(.density, default: nil)
        category = c.value(.category, default: .other)
        checked = c.value(.checked, default: false)
        sources = c.value(.sources, default: [])
    }
}

// MARK: - Settings and app data

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: return "Automatico"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }
}

public enum RecipeSort: String, Codable, CaseIterable, Sendable {
    case recent, alphabetical, lastCooked, mostCooked

    public var title: String {
        switch self {
        case .recent: return "Modificate di recente"
        case .alphabetical: return "Alfabetico"
        case .lastCooked: return "Cucinate di recente"
        case .mostCooked: return "Più cucinate"
        }
    }
}

public struct RicettarioSettings: Codable, Equatable, Sendable {
    public var units: UnitPreferences
    public var appearance: Appearance
    public var seed: String
    public var cloudBackup: Bool
    public var sort: RecipeSort
    /// Timer notifications (when the app is in background).
    public var timerNotifications: Bool

    public init(units: UnitPreferences = UnitPreferences(), appearance: Appearance = .system, seed: String = Palette.defaultAccent,
                cloudBackup: Bool = true, sort: RecipeSort = .recent, timerNotifications: Bool = true) {
        self.units = units
        self.appearance = appearance
        self.seed = seed
        self.cloudBackup = cloudBackup
        self.sort = sort
        self.timerNotifications = timerNotifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = c.value(.units, default: UnitPreferences())
        appearance = c.value(.appearance, default: .system)
        seed = c.value(.seed, default: Palette.defaultAccent)
        cloudBackup = c.value(.cloudBackup, default: true)
        sort = c.value(.sort, default: .recent)
        timerNotifications = c.value(.timerNotifications, default: true)
    }
}

public struct RicettarioData: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Incremented on every change (never overwrite newer data with older).
    public var revision: Int
    public var recipes: [Recipe]
    public var customIngredients: [CatalogIngredient]
    /// Edited seed entries (density, unit…), by seed id.
    public var seedOverrides: [String: CatalogIngredient]
    public var hiddenSeeds: [String]
    public var shopping: [ShoppingItem]
    public var settings: RicettarioSettings

    public init(recipes: [Recipe] = [], customIngredients: [CatalogIngredient] = [], seedOverrides: [String: CatalogIngredient] = [:],
                hiddenSeeds: [String] = [], shopping: [ShoppingItem] = [], settings: RicettarioSettings = RicettarioSettings()) {
        version = Self.currentVersion
        revision = 0
        self.recipes = recipes
        self.customIngredients = customIngredients
        self.seedOverrides = seedOverrides
        self.hiddenSeeds = hiddenSeeds
        self.shopping = shopping
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: Self.currentVersion)
        revision = c.value(.revision, default: 0)
        recipes = c.value(.recipes, default: [])
        customIngredients = c.value(.customIngredients, default: [])
        seedOverrides = c.value(.seedOverrides, default: [:])
        hiddenSeeds = c.value(.hiddenSeeds, default: [])
        shopping = c.value(.shopping, default: [])
        settings = c.value(.settings, default: RicettarioSettings())
    }

    public var isEmpty: Bool { recipes.isEmpty && customIngredients.isEmpty }

    /// All photo files referenced by the data.
    public var photoNames: Set<String> { Set(recipes.flatMap(\.photoNames)) }

    public func recipe(_ id: UUID) -> Recipe? { recipes.first { $0.id == id } }

    /// Inserts or replaces a recipe, stamping `updatedAt`.
    public mutating func upsert(_ recipe: Recipe, now: Date = Date()) {
        var r = recipe
        r.updatedAt = now
        if let i = recipes.firstIndex(where: { $0.id == r.id }) { recipes[i] = r } else { recipes.append(r) }
    }

    public mutating func delete(recipe id: UUID) {
        recipes.removeAll { $0.id == id }
    }

    /// Every tag used, sorted, case-insensitively unique.
    public var allTags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in recipes.flatMap(\.tags) {
            let k = Search.normalize(t)
            if !k.isEmpty, seen.insert(k).inserted { out.append(t) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Cleaning before save

public enum RecipeOps {
    /// Cleans a recipe coming from the editor: trimmed title, no unnamed
    /// ingredients, tags without duplicates, empty steps removed, step
    /// references to removed ingredients replaced by their last name.
    public static func sanitized(_ recipe: Recipe, previous: Recipe? = nil) -> Recipe {
        var r = recipe
        r.title = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        r.servings = max(1, r.servings)
        r.ingredients = r.ingredients.compactMap { i in
            var i = i
            i.name = i.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !i.name.isEmpty else { return nil }
            if let a = i.amount, !(a > 0) { i.amount = nil }
            return i
        }
        r.tags = Tags.clean(r.tags)
        var names: [UUID: String] = [:]
        for i in (previous?.ingredients ?? []) + recipe.ingredients { names[i.id] = StepRenderer.lowerFirst(i.name) }
        let keep = Set(r.ingredients.map(\.id))
        r.steps = r.steps.compactMap { s in
            var s = s
            s.text = StepText.dropMissing(s.text, keep: keep, names: names).trimmingCharacters(in: .whitespacesAndNewlines)
            if let t = s.timerSeconds, t <= 0 { s.timerSeconds = nil }
            if s.text.isEmpty, s.photo == nil, s.timerSeconds == nil { return nil }
            return s
        }
        return r
    }
}
