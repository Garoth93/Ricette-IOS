import SwiftUI
import RicettarioCore

/// One page of the method: free text with ingredient references inserted
/// from a menu (at the cursor), photo and optional timer.
struct StepEditorView: View {
    @Binding var step: RecipeStep
    let number: Int
    let recipe: Recipe
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var photo: String?
    @State private var timerOn = false
    @State private var timerSeconds = 300
    @State private var customFor: RecipeIngredient?
    @State private var customText = ""
    @FocusState private var focused: Bool

    private var stored: String { StepText.stored(text, ingredients: recipe.ingredients) }
    private var names: [UUID: String] { StepText.editorNames(recipe.ingredients) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text, selection: $selection)
                        .frame(minHeight: 170)
                        .focused($focused)
                    insertMenu
                } header: {
                    Text("Testo")
                } footer: {
                    Text("Gli ingredienti inseriti appaiono tra graffe, es. {1/2 Farina 00}: nella ricetta mostrano la quantità giusta anche quando la scali.")
                }
                if !text.isEmpty {
                    Section("Anteprima") {
                        StepTextView(segments: StepRenderer.render(stored, session: ScaleSession(recipe: recipe), prefs: model.prefs), font: .m3BodyMedium)
                    }
                }
                Section("Foto") { PhotoField(name: $photo) }
                Section {
                    Toggle("Timer", isOn: $timerOn.animation())
                    if timerOn {
                        DurationPicker(seconds: $timerSeconds)
                    } else if let suggested = TimerDetector.detect(stored) {
                        Button {
                            timerSeconds = suggested
                            withAnimation { timerOn = true }
                        } label: {
                            Label("Usa \(Fmt.duration(suggested)) dal testo", systemImage: "wand.and.stars")
                        }
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    Text("In modalità cottura parte con un tocco e ti avvisa anche con l'app chiusa.")
                }
            }
            .navigationTitle("Pagina \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { commit(); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                text = StepText.editable(step.text, ingredients: recipe.ingredients)
                photo = step.photo
                timerOn = step.timerSeconds != nil
                timerSeconds = step.timerSeconds ?? 300
                if text.isEmpty { focused = true }
            }
            .alert("Quantità parziale", isPresented: Binding(get: { customFor != nil }, set: { if !$0 { customFor = nil } })) {
                TextField("Es. 1/3 o 40%", text: $customText)
                Button("Inserisci") {
                    if let ing = customFor, let f = Fraction.parse(customText), f > 0 { insert(ing, fraction: min(f, 1)) }
                    customFor = nil
                    customText = ""
                }
                Button("Annulla", role: .cancel) { customFor = nil }
            } message: {
                Text("Che parte di «\(customFor?.name ?? "")» usi in questo passaggio?")
            }
        }
        .interactiveDismissDisabled()
    }

    private var insertMenu: some View {
        Menu {
            if recipe.ingredients.isEmpty {
                Text("Aggiungi prima gli ingredienti alla ricetta")
            }
            ForEach(recipe.ingredients) { ing in
                Menu {
                    ForEach(Fraction.common, id: \.1) { f, label in
                        Button(label == "tutto" ? "Tutto (\(ing.amountText(model.prefs)))" : "\(label) — \(partial(ing, f))") { insert(ing, fraction: f) }
                    }
                    Button("Altra quantità…") { customFor = ing }
                } label: {
                    Text("\(names[ing.id] ?? ing.name) · \(ing.amountText(model.prefs))")
                }
            }
        } label: {
            Label("Inserisci ingrediente", systemImage: "text.badge.plus")
        }
        .disabled(recipe.ingredients.isEmpty)
    }

    private func partial(_ ing: RecipeIngredient, _ f: Double) -> String {
        guard let a = ing.amount else { return "q.b." }
        return UnitConverter.display(base: a * f, entryUnit: ing.unit, density: ing.density, prefs: model.prefs).text
    }

    /// Inserts the readable token at the cursor (or at the end).
    private func insert(_ ing: RecipeIngredient, fraction: Double) {
        let token = StepText.editorToken(name: names[ing.id] ?? ing.name, fraction: fraction)
        if let sel = selection, case .selection(let range) = sel.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let before = start > 0 ? text[text.index(before: range.lowerBound)] : " "
            let piece = (before == " " || before == "\n" ? "" : " ") + token + " "
            text.replaceSubrange(range, with: piece)
            selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: start + piece.count))
        } else {
            let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
            text += sep + token + " "
        }
        focused = true
    }

    private func commit() {
        step.text = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        step.photo = photo
        step.timerSeconds = timerOn && timerSeconds > 0 ? timerSeconds : nil
    }
}

/// Hours / minutes / seconds wheels.
struct DurationPicker: View {
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 0) {
            wheel(value: Binding(get: { seconds / 3600 }, set: { seconds = $0 * 3600 + seconds % 3600 }), range: 0..<24, label: "h")
            wheel(value: Binding(get: { (seconds % 3600) / 60 }, set: { seconds = (seconds / 3600) * 3600 + $0 * 60 + seconds % 60 }), range: 0..<60, label: "min")
            wheel(value: Binding(get: { seconds % 60 }, set: { seconds = seconds - seconds % 60 + $0 }), range: 0..<60, label: "s")
        }
        .frame(height: 150)
    }

    private func wheel(value: Binding<Int>, range: Range<Int>, label: String) -> some View {
        Picker(label, selection: value) {
            ForEach(range, id: \.self) { Text("\($0) \(label)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
