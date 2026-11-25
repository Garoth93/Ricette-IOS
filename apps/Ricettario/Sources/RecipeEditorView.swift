import SwiftUI
import RicettarioCore

/// A recipe being edited (new or existing).
struct RecipeDraft: Identifiable {
    let id = UUID()
    var recipe: Recipe
}

struct RecipeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe
    private let original: Recipe
    @State private var tagsText: String
    @State private var picking = false
    @State private var editingIngredient: RecipeIngredient?
    @State private var editingStep: StepRef?
    @State private var confirmDiscard = false

    struct StepRef: Identifiable { let id: UUID }

    init(draft: RecipeDraft) {
        _recipe = State(initialValue: draft.recipe)
        original = draft.recipe
        _tagsText = State(initialValue: draft.recipe.tags.joined(separator: ", "))
    }

    private var isNew: Bool { model.recipe(recipe.id) == nil }
    private var changed: Bool { recipe != original || tagsText != original.tags.joined(separator: ", ") }
    private var canSave: Bool { !recipe.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                mainSection
                Section("Foto") { PhotoField(name: $recipe.photo, height: 180) }
                timesSection
                tagsSection
                ingredientsSection
                stepsSection
                Section("Note") {
                    TextField("Consigli, varianti, conservazione…", text: $recipe.notes, axis: .vertical).lineLimit(3...10)
                    TextField("Fonte (libro, sito, persona)", text: $recipe.source)
                }
            }
            .navigationTitle(isNew ? "Nuova ricetta" : "Modifica ricetta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { if changed { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog("Scartare le modifiche?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Scarta", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $picking) {
                IngredientPickerView { ing in recipe.ingredients.append(ing) }
            }
            .sheet(item: $editingIngredient) { ing in
                IngredientEditView(ingredient: ing) { updated in
                    if let i = recipe.ingredients.firstIndex(where: { $0.id == updated.id }) { recipe.ingredients[i] = updated }
                }
            }
            .sheet(item: $editingStep) { ref in
                if let i = recipe.steps.firstIndex(where: { $0.id == ref.id }) {
                    StepEditorView(step: $recipe.steps[i], number: i + 1, recipe: recipe)
                }
            }
        }
    }

    private var mainSection: some View {
        Section {
            HStack(spacing: 12) {
                EmojiPicker(emoji: $recipe.emoji)
                TextField("Nome della ricetta", text: $recipe.title, axis: .vertical)
                    .font(.m3TitleLarge)
            }
            Stepper(value: $recipe.servings, in: 1...99) {
                Label(peopleText(Double(recipe.servings)), systemImage: "person.2.fill")
            }
        } footer: {
            Text("Le quantità sono per il numero di persone indicato: in «Usa ricetta» le ricalcoli per quante ne vuoi.")
        }
    }

    private var timesSection: some View {
        Section("Tempi") {
            MinutesField(title: "Preparazione", icon: "hands.and.sparkles.fill", minutes: $recipe.prepMinutes)
            MinutesField(title: "Cottura", icon: "flame.fill", minutes: $recipe.cookMinutes)
        }
    }

    private var tagsSection: some View {
        Section {
            TextField("Es. primi, veloce, vegetariano", text: $tagsText)
                .textInputAutocapitalization(.never)
                .onChange(of: tagsText) { _, t in recipe.tags = Tags.parse(t) }
            let current = Set(recipe.tags.map(Search.normalize))
            let suggestions = model.data.allTags.filter { !current.contains(Search.normalize($0)) }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { tag in
                            Chip(title: tag, icon: "plus", selected: false) {
                                let parts = Tags.parse(tagsText) + [tag]
                                tagsText = parts.joined(separator: ", ")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Tag")
        } footer: {
            Text("Separati da virgola. Servono per filtrare e cercare.")
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(recipe.ingredients) { ing in
                Button { editingIngredient = ing } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ing.name).foregroundStyle(m3.onSurface)
                            if !ing.note.isEmpty || !ing.scales {
                                Text([ing.note, ing.scales ? "" : "non scala"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        Spacer()
                        Text(ing.amountText(model.prefs)).foregroundStyle(m3.onSurfaceVariant).monospacedDigit()
                    }
                }
            }
            .onDelete { recipe.ingredients.remove(atOffsets: $0) }
            .onMove { recipe.ingredients.move(fromOffsets: $0, toOffset: $1) }
            Button { picking = true } label: { Label("Aggiungi ingrediente", systemImage: "plus.circle.fill") }
        } header: {
            Text("Ingredienti (\(recipe.ingredients.count))")
        } footer: {
            Text("Facoltativi. Tieni premuto e trascina per riordinare, scorri per eliminare.")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { i, step in
                Button { editingStep = StepRef(id: step.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.m3LabelLarge).foregroundStyle(m3.onPrimaryContainer)
                            .frame(width: 26, height: 26).background(m3.primaryContainer, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            let preview = StepRenderer.plain(step.text, session: ScaleSession(recipe: recipe), prefs: model.prefs)
                            Text(preview.isEmpty ? "Pagina vuota" : preview).lineLimit(3).foregroundStyle(preview.isEmpty ? m3.onSurfaceVariant : m3.onSurface)
                            HStack(spacing: 8) {
                                if step.photo != nil { Label("Foto", systemImage: "photo").font(.caption) }
                                if let t = step.timerSeconds { Label(Fmt.duration(t), systemImage: "timer").font(.caption) }
                            }
                            .foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                }
            }
            .onDelete { recipe.steps.remove(atOffsets: $0) }
            .onMove { recipe.steps.move(fromOffsets: $0, toOffset: $1) }
            Button {
                let s = RecipeStep()
                recipe.steps.append(s)
                editingStep = StepRef(id: s.id)
            } label: { Label("Aggiungi pagina", systemImage: "plus.circle.fill") }
        } header: {
            Text("Procedimento (\(recipe.steps.count) \(recipe.steps.count == 1 ? "pagina" : "pagine"))")
        } footer: {
            Text("Facoltativo. Ogni pagina ha testo, foto e timer; dentro il testo richiami gli ingredienti, che si ricalcolano quando scali la ricetta.")
        }
    }

    private func save() {
        recipe.tags = Tags.parse(tagsText)
        model.save(recipe, previous: isNew ? nil : original)
        let keep = model.data.photoNames
        model.cleanupOrphanPhotos(keeping: keep)
        if isNew { model.recipesPath.append(recipe.id) }
        dismiss()
    }
}

/// Optional minutes (empty = not set).
struct MinutesField: View {
    let title: String
    let icon: String
    @Binding var minutes: Int?

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            TextField("—", value: $minutes, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("min").foregroundStyle(.secondary)
        }
    }
}

/// Emoji of the recipe: a grid of food emoji, or any emoji typed.
struct EmojiPicker: View {
    @Binding var emoji: String
    @State private var open = false
    @Environment(\.m3) private var m3

    static let choices = ["🍝", "🍕", "🥗", "🍲", "🍛", "🥘", "🍜", "🍣", "🥩", "🍗", "🐟", "🦐", "🥚", "🧀", "🥖", "🥐", "🥞", "🧇",
                          "🍰", "🎂", "🧁", "🍪", "🍫", "🍮", "🍨", "🥧", "🍩", "🍎", "🍋", "🍓", "🥑", "🍅", "🥕", "🌽", "🥦", "🍄",
                          "🫘", "🥔", "🧄", "🌶️", "🍚", "🥟", "🌮", "🥙", "🍔", "🥪", "☕️", "🍹", "🍷", "🫖", "🍽️", "🔥"]

    var body: some View {
        Button { open = true } label: {
            Text(emoji.isEmpty ? "🍽️" : emoji).font(.system(size: 34))
                .frame(width: 54, height: 54)
                .background(m3.primaryContainer, in: CookieShape())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(Self.choices, id: \.self) { e in
                        Button {
                            emoji = e
                            open = false
                        } label: { Text(e).font(.system(size: 30)) }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .frame(minWidth: 320, minHeight: 300)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Emoji della ricetta")
    }
}
