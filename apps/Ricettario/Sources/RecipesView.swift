import SwiftUI
import RicettarioCore

struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var search = ""
    @State private var tags: Set<String> = []
    @State private var favoritesOnly = false
    @State private var editing: RecipeDraft?

    private var query: RecipeQuery {
        RecipeQuery(text: search, tags: tags, favoritesOnly: favoritesOnly, sort: model.data.settings.sort)
    }

    var body: some View {
        let results = query.apply(model.data.recipes)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !model.data.recipes.isEmpty { filters }
                if model.data.recipes.isEmpty {
                    EmptyStateView(icon: "book.closed.fill", title: "Il tuo ricettario è vuoto",
                                   message: "Tocca + per scrivere la prima ricetta: ingredienti, passaggi a pagine con foto e timer.")
                    PillButton(title: "Nuova ricetta", icon: "plus", tones: m3.primaryTones) { editing = RecipeDraft(recipe: Recipe()) }
                        .padding(.horizontal, 32)
                } else if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Nessuna ricetta", message: "Nessuna ricetta corrisponde alla ricerca o ai filtri.")
                }
                ForEach(results) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeRow(recipe: recipe)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu { contextMenu(recipe) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(m3.surface)
        .navigationTitle("Ricette")
        .searchable(text: $search, prompt: "Titolo, ingrediente, tag…")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { sortMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = RecipeDraft(recipe: Recipe()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuova ricetta")
            }
        }
        .sheet(item: $editing) { draft in
            RecipeEditorView(draft: draft)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Preferite", icon: "heart", selected: favoritesOnly) { favoritesOnly.toggle() }
                ForEach(model.data.allTags, id: \.self) { tag in
                    let on = tags.contains(where: { Search.normalize($0) == Search.normalize(tag) })
                    Chip(title: tag, icon: "number", selected: on) {
                        if on { tags = tags.filter { Search.normalize($0) != Search.normalize(tag) } } else { tags.insert(tag) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordina", selection: Binding(
                get: { model.data.settings.sort },
                set: { s in model.updateSettings { $0.sort = s } }
            )) {
                ForEach(RecipeSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Ordina")
    }

    @ViewBuilder
    private func contextMenu(_ recipe: Recipe) -> some View {
        Button { model.useRecipe = recipe } label: { Label("Usa ricetta", systemImage: "frying.pan.fill") }
        Button { model.toggleFavorite(recipe.id) } label: {
            Label(recipe.favorite ? "Togli dalle preferite" : "Preferita", systemImage: recipe.favorite ? "heart.slash" : "heart")
        }
        Button { editing = RecipeDraft(recipe: recipe) } label: { Label("Modifica", systemImage: "pencil") }
        Button { model.duplicate(recipe) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
    }
}

struct RecipeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumb(recipe: recipe, size: 72, corner: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(recipe.displayTitle).font(.m3TitleMedium).foregroundStyle(m3.onSurface).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if recipe.favorite {
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(m3.primary)
                    }
                }
                Text(detail).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
                if !recipe.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recipe.tags.prefix(3), id: \.self) { TagLabel(text: $0, tones: m3.neutral) }
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(m3.outline)
        }
        .padding(10)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var detail: String {
        var parts = [peopleText(Double(recipe.servings))]
        if !recipe.ingredients.isEmpty { parts.append("\(recipe.ingredients.count) ingr.") }
        if !recipe.steps.isEmpty { parts.append("\(recipe.steps.count) \(recipe.steps.count == 1 ? "passaggio" : "passaggi")") }
        if let t = recipe.totalMinutes { parts.append(Fmt.duration(t * 60)) }
        return parts.joined(separator: " · ")
    }
}
