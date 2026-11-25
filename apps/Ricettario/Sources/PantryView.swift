import SwiftUI
import RicettarioCore

/// The ingredient pool: built-in list plus the user's own.
struct PantryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var search = ""
    @State private var category: IngredientCategory?
    @State private var onlyMine = false
    @State private var editing: CatalogIngredient?
    @State private var creating = false

    var body: some View {
        let base = onlyMine ? model.pool.filter { !$0.isSeed } : model.pool
        let results = Catalog.search(search, in: base, category: category)
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Chip(title: "I miei", icon: "person.fill", selected: onlyMine) { onlyMine.toggle() }
                        ForEach(IngredientCategory.allCases) { c in
                            Chip(title: c.title, icon: c.icon, selected: category == c) { category = category == c ? nil : c }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            } footer: {
                Text("\(results.count) ingredienti. Tocca per cambiare unità proposta o densità; scorri per nascondere quelli che non usi.")
            }
            Section {
                ForEach(results) { item in
                    Button { editing = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.category.icon).foregroundStyle(m3.primary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(m3.onSurface)
                                Text(detail(item)).font(.caption).foregroundStyle(m3.onSurfaceVariant)
                            }
                            Spacer()
                            if !item.isSeed { Image(systemName: "person.fill").font(.caption).foregroundStyle(m3.primary) }
                            else if model.data.seedOverrides[item.id] != nil { Image(systemName: "pencil").font(.caption).foregroundStyle(m3.primary) }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.deleteIngredient(item) } label: {
                            Label(item.isSeed ? "Nascondi" : "Elimina", systemImage: item.isSeed ? "eye.slash" : "trash")
                        }
                    }
                }
            }
            if !model.data.hiddenSeeds.isEmpty {
                Section {
                    Button("Mostra di nuovo i \(model.data.hiddenSeeds.count) nascosti") { model.restoreHiddenSeeds() }
                }
            }
        }
        .navigationTitle("Ingredienti")
        .searchable(text: $search, prompt: "Cerca ingrediente")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuovo ingrediente")
            }
        }
        .sheet(item: $editing) { item in
            CatalogIngredientForm(item: item, inSheet: true) { model.saveIngredient($0) }
        }
        .sheet(isPresented: $creating) {
            CatalogIngredientForm(item: CatalogIngredient.user(name: search), inSheet: true) { model.saveIngredient($0) }
        }
    }

    private func detail(_ item: CatalogIngredient) -> String {
        var parts = [item.unit.pickerName]
        if let d = item.density { parts.append("\(Fmt.number(d, digits: 2)) g/ml") }
        if !item.scales { parts.append("non scala") }
        if item.wholeOnly { parts.append("solo interi") }
        let uses = Catalog.usage(of: item.id, in: model.data)
        if uses > 0 { parts.append("in \(uses) \(uses == 1 ? "ricetta" : "ricette")") }
        return parts.joined(separator: " · ")
    }
}
