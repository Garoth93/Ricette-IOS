import SwiftUI
import RicettarioCore

/// Adds an ingredient to a recipe: search the pool (or create a new
/// entry), then type the quantity.
struct IngredientPickerView: View {
    let onAdd: (RecipeIngredient) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var path: [Route] = []

    enum Route: Hashable {
        case amount(CatalogIngredient)
        case create(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let results = Catalog.search(search, in: model.pool)
                let trimmed = search.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, Catalog.existing(named: trimmed, in: model.pool) == nil {
                    Section {
                        NavigationLink(value: Route.create(trimmed)) {
                            Label("Crea «\(trimmed)»", systemImage: "plus.circle.fill").foregroundStyle(m3.primary)
                        }
                    } footer: {
                        Text("Lo aggiungi al tuo elenco di ingredienti: lo ritrovi nelle prossime ricette.")
                    }
                }
                if trimmed.isEmpty {
                    ForEach(IngredientCategory.allCases) { cat in
                        let items = results.filter { $0.category == cat }
                        if !items.isEmpty {
                            Section(cat.title) { ForEach(items) { row($0) } }
                        }
                    }
                } else {
                    Section { ForEach(results.prefix(80)) { row($0) } }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca o scrivi un ingrediente")
            .autocorrectionDisabled()
            .navigationTitle("Aggiungi ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .amount(let item):
                    IngredientEditView(ingredient: RecipeIngredient(from: item, value: nil, cupML: model.prefs.cupML), isNew: true) { ing in
                        onAdd(ing)
                        search = ""
                        path = []
                        model.show("\(ing.name) aggiunto", icon: "plus.circle.fill")
                    }
                case .create(let name):
                    CatalogIngredientForm(item: CatalogIngredient.user(name: name)) { item in
                        model.saveIngredient(item)
                        path = [.amount(item)]
                    }
                }
            }
        }
    }

    private func row(_ item: CatalogIngredient) -> some View {
        NavigationLink(value: Route.amount(item)) {
            HStack {
                Text(item.name)
                Spacer()
                Text(item.unit.shortName).font(.caption).foregroundStyle(m3.onSurfaceVariant)
                if !item.isSeed { Image(systemName: "person.fill").font(.caption2).foregroundStyle(m3.primary) }
            }
        }
    }
}

/// Quantity, unit and options of a recipe ingredient.
struct IngredientEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSave: (RecipeIngredient) -> Void
    @State private var ing: RecipeIngredient
    @State private var amountText: String
    @State private var toTaste: Bool
    @State private var densityText: String
    @FocusState private var amountFocused: Bool

    init(ingredient: RecipeIngredient, isNew: Bool = false, onSave: @escaping (RecipeIngredient) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _ing = State(initialValue: ingredient)
        let cup = AppModel.shared.prefs.cupML
        _amountText = State(initialValue: ingredient.amount.map { Self.text($0 / ingredient.unit.toBase(cupML: cup), unit: ingredient.unit) } ?? "")
        _toTaste = State(initialValue: !isNew && ingredient.amount == nil)
        _densityText = State(initialValue: ingredient.density.map { Fmt.number($0, digits: 3) } ?? "")
    }

    static func text(_ v: Double, unit: CookUnit) -> String {
        if unit.prefersFractions, let f = Fmt.fraction(v, tolerance: 0.005) { return f }
        return Fmt.number(v, digits: 3)
    }

    private var value: Double? { Fmt.parseAmount(amountText) }
    private var density: Double? { Fmt.parseAmount(densityText).flatMap { $0 > 0 ? $0 : nil } }

    private var result: RecipeIngredient {
        var r = ing
        r.density = density
        r.amount = toTaste ? nil : value.map { UnitConverter.toBase($0, unit: ing.unit, cupML: model.prefs.cupML) }
        if r.kind != .count { r.wholeOnly = false }
        return r
    }

    private var valid: Bool {
        !ing.name.trimmingCharacters(in: .whitespaces).isEmpty && (toTaste || (value ?? 0) > 0)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $ing.name)
                Toggle("Quanto basta (q.b.)", isOn: $toTaste.animation())
                if !toTaste {
                    HStack {
                        TextField("Quantità", text: $amountText)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($amountFocused)
                            .font(.m3TitleLarge)
                        Picker("Unità", selection: $ing.unit) {
                            Section("Peso") { ForEach(CookUnit.mass) { Text($0.pickerName).tag($0) } }
                            Section("Volume") { ForEach(CookUnit.volume) { Text($0.pickerName).tag($0) } }
                            Section("Pezzi") { ForEach(CookUnit.count) { Text($0.pickerName).tag($0) } }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    if let preview { Text(preview).font(.footnote).foregroundStyle(m3.onSurfaceVariant) }
                }
                TextField("Nota (es. a temperatura ambiente)", text: $ing.note)
            } footer: {
                Text("Quantità anche come frazione: 1/2, 1 1/2, ½.")
            }
            Section {
                Toggle("Scala con le persone", isOn: $ing.scales)
                if ing.kind == .count {
                    Toggle("Solo unità intere", isOn: $ing.wholeOnly)
                }
            } header: {
                Text("Quando ricalcoli la ricetta")
            } footer: {
                Text(ing.kind == .count
                     ? "Con «Solo unità intere» (uova, spicchi) il ricalcolo arrotonda all'unità e segnala la differenza; altrimenti arrotonda alla metà."
                     : "Spegni «Scala» per sale, pepe e simili: la quantità resta uguale.")
            }
            if ing.kind != .count {
                Section {
                    HStack {
                        Text("Densità")
                        Spacer()
                        TextField("—", text: $densityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g/ml").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(densityFooter)
                }
            }
        }
        .navigationTitle(isNew ? ing.name : "Modifica ingrediente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Aggiungi" : "Fatto") {
                    onSave(result)
                    if !isNew { dismiss() }
                }
                .disabled(!valid)
                .fontWeight(.semibold)
            }
        }
        .onAppear { if isNew { amountFocused = true } }
        .wrappedInNavigationIf(!isNew)
    }

    /// "= 127 g" for volumes with a density, or the other system.
    private var preview: String? {
        guard let v = value, v > 0, ing.kind != .count else { return nil }
        let base = UnitConverter.toBase(v, unit: ing.unit, cupML: model.prefs.cupML)
        var parts: [String] = []
        if let d = density {
            let other: CookUnit = ing.kind == .volume ? .g : .ml
            if let c = UnitConverter.convert(base: base, kind: ing.kind, to: other, density: d, cupML: model.prefs.cupML) {
                parts.append("≈ " + Fmt.quantity(c, unit: other))
            }
        }
        if ing.unit.isImperial || ing.unit.isSpoonOrCup {
            parts.append("= " + Fmt.quantity(base, unit: ing.kind == .mass ? .g : .ml))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "   ")
    }

    private var densityFooter: String {
        guard let d = density else {
            return "Facoltativa: serve a convertire tazze e cucchiai in grammi (es. farina 0,53, zucchero 0,85, acqua 1)."
        }
        let cup = model.prefs.cupML
        return "1 tazza ≈ \(Fmt.quantity(cup * d, unit: .g)) · 1 cucchiaio ≈ \(Fmt.quantity(15 * d, unit: .g))"
    }
}

extension View {
    /// Sheets need their own navigation bar; pushed views don't.
    @ViewBuilder
    func wrappedInNavigationIf(_ condition: Bool) -> some View {
        if condition { NavigationStack { self } } else { self }
    }
}

/// Pool entry: name, category, default unit, density, flags.
struct CatalogIngredientForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var item: CatalogIngredient
    @State private var densityText: String
    let onSave: (CatalogIngredient) -> Void
    var inSheet = false

    init(item: CatalogIngredient, inSheet: Bool = false, onSave: @escaping (CatalogIngredient) -> Void) {
        _item = State(initialValue: item)
        _densityText = State(initialValue: item.density.map { Fmt.number($0, digits: 3) } ?? "")
        self.inSheet = inSheet
        self.onSave = onSave
    }

    private var duplicate: Bool {
        guard let other = Catalog.existing(named: item.name, in: model.pool) else { return false }
        return other.id != item.id
    }

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $item.name)
                Picker("Categoria", selection: $item.category) {
                    ForEach(IngredientCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                Picker("Unità proposta", selection: $item.unit) {
                    Section("Peso") { ForEach(CookUnit.mass) { Text($0.pickerName).tag($0) } }
                    Section("Volume") { ForEach(CookUnit.volume) { Text($0.pickerName).tag($0) } }
                    Section("Pezzi") { ForEach(CookUnit.count) { Text($0.pickerName).tag($0) } }
                }
            } footer: {
                if duplicate { Text("Esiste già un ingrediente con questo nome.").foregroundStyle(.red) }
            }
            Section {
                Toggle("Scala con le persone", isOn: $item.scales)
                if item.unit.kind == .count { Toggle("Solo unità intere (es. uova)", isOn: $item.wholeOnly) }
                HStack {
                    Text("Densità")
                    Spacer()
                    TextField("—", text: $densityText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("g/ml").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Valori proposti quando aggiungi l'ingrediente a una ricetta; nella ricetta puoi cambiarli. La densità converte tazze e cucchiai in grammi.")
            }
        }
        .navigationTitle(item.isSeed ? "Ingrediente" : "Nuovo ingrediente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    var out = item
                    out.name = out.name.trimmingCharacters(in: .whitespaces)
                    out.density = Fmt.parseAmount(densityText).flatMap { $0 > 0 ? $0 : nil }
                    if out.unit.kind != .count { out.wholeOnly = false }
                    onSave(out)
                    if inSheet { dismiss() }
                }
                .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || duplicate)
                .fontWeight(.semibold)
            }
        }
        .wrappedInNavigationIf(inSheet)
    }
}
