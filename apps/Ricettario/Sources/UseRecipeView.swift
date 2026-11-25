import SwiftUI
import RicettarioCore

/// "Usa ricetta": temporary session with a scale factor. The original
/// recipe is never touched; closing loses everything unless the user saves
/// a variant (a new recipe).
struct UseRecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(TimerCenter.self) private var timers
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var session: ScaleSession
    @State private var anchorEditing: ScaledIngredient?
    @State private var cooking = false
    @State private var confirmClose = false
    @State private var variantPrompt = false
    @State private var variantTitle = ""

    init(recipe: Recipe) {
        _session = State(initialValue: ScaleSession(recipe: recipe))
    }

    private var r: Recipe { session.original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    banner
                    servingsCard
                    if !session.roundingNotes.isEmpty { roundingCard }
                    if !r.ingredients.isEmpty {
                        SectionTitle("Ingredienti", trailing: "tocca una quantità per ricalcolare")
                        M3Card {
                            VStack(spacing: 0) {
                                ForEach(Array(session.ingredients.enumerated()), id: \.element.id) { i, s in
                                    if i > 0 { Divider().overlay(m3.outlineVariant) }
                                    ScaledRow(scaled: s, isAnchor: session.anchorID == s.id,
                                              onTap: { anchorEditing = s },
                                              onStep: { d in withAnimation(.m3Effects) { session.step(s.id, by: d) } })
                                }
                            }
                        }
                    }
                    if !r.steps.isEmpty {
                        SectionTitle("Procedimento")
                        ForEach(Array(r.steps.enumerated()), id: \.element.id) { i, step in
                            StepCard(index: i, step: step, session: session)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 130)
            }
            .background(m3.surface)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(r.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if session.isScaled { confirmClose = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Chiudi")
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .sheet(item: $anchorEditing) { s in
                AnchorEditView(scaled: s) { base in withAnimation(.m3Spatial) { session.setAnchor(s.id, newAmount: base) } }
                    .presentationDetents([.height(330)])
            }
            .fullScreenCover(isPresented: $cooking) {
                CookingModeView(session: session) { cooked in
                    if cooked { model.markCooked(r.id) }
                }
                .environment(\.m3, m3)
            }
            .confirmationDialog("Chiudere la sessione?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Salva come variante") { askVariant() }
                Button("Chiudi senza salvare", role: .destructive) { dismiss() }
            } message: {
                Text("Le quantità ricalcolate si perdono: la ricetta originale resta com'era.")
            }
            .alert("Salva come variante", isPresented: $variantPrompt) {
                TextField("Nome", text: $variantTitle)
                Button("Salva") {
                    let v = model.saveVariant(session, title: variantTitle)
                    dismiss()
                    model.recipesPath.append(v.id)
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Diventa una nuova ricetta con queste quantità. L'originale non cambia.")
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(m3.primary)
            Text("Sessione temporanea: puoi cambiare persone e quantità, la ricetta salvata non cambia.")
                .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
        }
        .padding(.top, 6)
    }

    private var servingsCard: some View {
        M3Card(color: m3.primaryContainer) {
            VStack(spacing: 12) {
                HStack {
                    RoundIconButton(icon: "minus", tones: m3.primaryTones, size: 52, filled: true) { changePeople(-1) }
                        .disabled(session.servings <= 1)
                    Spacer()
                    VStack(spacing: 0) {
                        Text(Fmt.number(session.servings, digits: 1))
                            .font(.m3DisplayMedium).monospacedDigit()
                            .contentTransition(.numericText(value: session.servings))
                        Text(session.servings == 1 ? "persona" : "persone").font(.m3LabelLarge)
                    }
                    .foregroundStyle(m3.onPrimaryContainer)
                    Spacer()
                    RoundIconButton(icon: "plus", tones: m3.primaryTones, size: 52, filled: true) { changePeople(1) }
                }
                HStack(spacing: 8) {
                    TagLabel(text: "× \(Fmt.number(session.factor, digits: 2))", icon: "arrow.up.left.and.arrow.down.right", tones: m3.neutral)
                    if let a = session.anchorID, let ing = r.ingredient(a) {
                        TagLabel(text: "da \(ing.name)", icon: "scope", tones: m3.tertiaryTones)
                    }
                    Text("originale: \(r.servings)").font(.m3LabelMedium).foregroundStyle(m3.onPrimaryContainer.opacity(0.7))
                    Spacer()
                    if session.isScaled {
                        Button("Ripristina") { withAnimation(.m3Spatial) { session.reset() } }.font(.m3LabelLarge)
                    }
                }
            }
        }
        .animation(.m3Effects, value: session.factor)
    }

    private var roundingCard: some View {
        M3Card(color: m3.warningContainer) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Arrotondati", systemImage: "exclamationmark.triangle.fill").font(.m3TitleSmall)
                ForEach(session.roundingNotes) { s in
                    Text("\(s.ingredient.name): servirebbero \(Fmt.number(s.exact ?? 0, digits: 2)), usi \(s.amountText(model.prefs))")
                        .font(.m3BodySmall)
                }
            }
            .foregroundStyle(m3.onWarningContainer)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PillButton(title: r.steps.isEmpty ? "Prepara" : "Cucina", icon: "flame.fill", tones: m3.primaryTones) { cooking = true }
            RoundIconButton(icon: "cart.badge.plus", tones: m3.primaryTones, size: 54) { model.addToShopping(session) }
                .disabled(r.ingredients.isEmpty)
                .accessibilityLabel("Aggiungi alla spesa")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            if !timers.timers.isEmpty { TimerStrip().padding(.horizontal, 16).offset(y: -52) }
        }
    }

    private var menu: some View {
        Menu {
            Button { askVariant() } label: { Label("Salva come variante", systemImage: "square.on.square") }
            Button { model.addToShopping(session) } label: { Label("Aggiungi alla spesa", systemImage: "cart.badge.plus") }
            ShareLink(item: RecipeText.plain(session, prefs: model.prefs)) { Label("Condividi queste quantità", systemImage: "square.and.arrow.up") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func changePeople(_ delta: Double) {
        let current = session.servings
        let next = delta > 0 ? (current + 1).rounded(.down) : max(1, (current - 1).rounded(.up))
        withAnimation(.m3Spatial) { session.setServings(next) }
    }

    private func askVariant() {
        variantTitle = session.defaultVariantTitle
        variantPrompt = true
    }
}

/// Ingredient row in the session: tap to anchor, ± for counted ones.
struct ScaledRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let scaled: ScaledIngredient
    let isAnchor: Bool
    let onTap: () -> Void
    let onStep: (Double) -> Void

    var body: some View {
        let ing = scaled.ingredient
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ing.name).font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                HStack(spacing: 6) {
                    if scaled.isFixed, scaled.amount != nil { Text("non scala").font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant) }
                    if scaled.isRounded { Text("≈ \(Fmt.number(scaled.exact ?? 0, digits: 2))").font(.m3LabelSmall).foregroundStyle(m3.warning) }
                    if !ing.note.isEmpty { Text(ing.note).font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant) }
                }
            }
            Spacer(minLength: 6)
            if ing.kind == .count, !scaled.isFixed {
                RoundIconButton(icon: "minus", tones: m3.neutral, size: 32) { onStep(-1) }
                    .disabled((scaled.amount ?? 0) <= (ing.wholeOnly ? 1 : 0.5))
            }
            Button(action: onTap) {
                Text(scaled.amountText(model.prefs))
                    .font(.m3TitleSmall).monospacedDigit()
                    .foregroundStyle(isAnchor ? m3.onTertiaryContainer : m3.onSurface)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isAnchor ? m3.tertiaryContainer : m3.surfaceContainerHigh, in: Capsule())
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .disabled(scaled.isFixed)
            if ing.kind == .count, !scaled.isFixed {
                RoundIconButton(icon: "plus", tones: m3.neutral, size: 32) { onStep(1) }
            }
        }
        .padding(.vertical, 8)
    }
}

/// "Quanta ne hai?": new amount of one ingredient → new factor.
struct AnchorEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let scaled: ScaledIngredient
    let onSet: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var shown: DisplayQuantity? {
        scaled.amount.map { UnitConverter.display(base: $0, entryUnit: scaled.ingredient.unit, density: scaled.ingredient.density, prefs: model.prefs) }
    }

    /// Typed value (in the shown unit) → base units of the ingredient.
    private var base: Double? {
        guard let q = shown, let v = Fmt.parseAmount(text), v > 0 else { return nil }
        let ing = scaled.ingredient
        let b = UnitConverter.toBase(v, unit: q.unit, cupML: model.prefs.cupML)
        if q.unit.kind == ing.kind { return b }
        guard let d = ing.density, d > 0 else { return nil }
        return q.unit.kind == .mass ? b / d : b * d
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Quanta «\(scaled.ingredient.name)» usi?").font(.m3TitleMedium)
                HStack(alignment: .firstTextBaseline) {
                    TextField(shown.map { Fmt.amount($0.value, unit: $0.unit) } ?? "", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.m3DisplaySmall)
                        .focused($focused)
                    Text(shown.map { $0.unit == .piece ? "pezzi" : $0.unit.label(for: 2) } ?? "").font(.m3TitleLarge).foregroundStyle(m3.onSurfaceVariant)
                }
                .padding(14)
                .background(m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if let b = base, let old = scaled.ingredient.amount, old > 0 {
                    Text("Tutte le quantità × \(Fmt.number(b / old, digits: 2)) (rispetto all'originale)")
                        .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                } else {
                    Text("Es. hai solo 3 uova invece di 4: scrivi 3 e il resto si adegua.")
                        .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                }
                PillButton(title: "Ricalcola", icon: "arrow.triangle.2.circlepath", tones: m3.primaryTones) {
                    if let b = base { onSet(b) }
                    dismiss()
                }
                .disabled(base == nil)
                .opacity(base == nil ? 0.5 : 1)
            }
            .padding(20)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}
