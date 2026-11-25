import SwiftUI
import RicettarioCore

/// Rendered step text: ingredient references in bold and colored.
struct StepTextView: View {
    @Environment(\.m3) private var m3
    let segments: [RenderedSegment]
    var font: Font = .m3BodyLarge

    var body: some View {
        Text(attributed).font(font).foregroundStyle(m3.onSurface)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for s in segments {
            var a = AttributedString(s.text)
            switch s.kind {
            case .text: break
            case .ingredient:
                a.foregroundColor = m3.primary
                a.inlinePresentationIntent = .stronglyEmphasized
            case .missing:
                a.foregroundColor = m3.error
                a.inlinePresentationIntent = .emphasized
            }
            out += a
        }
        return out
    }
}

struct RecipeDetailView: View {
    let recipeID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var editing: RecipeDraft?
    @State private var confirmDelete = false
    @State private var shareURL: URL?
    @State private var photoFull: String?

    var body: some View {
        if let recipe = model.recipe(recipeID) {
            content(recipe)
        } else {
            EmptyStateView(icon: "questionmark.folder", title: "Ricetta non trovata", message: "Forse è stata eliminata.")
        }
    }

    private func content(_ recipe: Recipe) -> some View {
        let session = ScaleSession(recipe: recipe)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(recipe)
                actions(recipe)
                if !recipe.ingredients.isEmpty {
                    SectionTitle("Ingredienti", trailing: "per \(peopleText(Double(recipe.servings)))")
                    M3Card {
                        VStack(spacing: 0) {
                            ForEach(Array(session.ingredients.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { Divider().overlay(m3.outlineVariant) }
                                IngredientLine(scaled: s)
                            }
                        }
                    }
                }
                if !recipe.steps.isEmpty {
                    SectionTitle("Procedimento", trailing: "\(recipe.steps.count) \(recipe.steps.count == 1 ? "pagina" : "pagine")")
                    ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { i, step in
                        StepCard(index: i, step: step, session: session) { photoFull = step.photo }
                    }
                }
                if !recipe.notes.isEmpty || !recipe.source.isEmpty {
                    SectionTitle("Note")
                    M3Card {
                        VStack(alignment: .leading, spacing: 8) {
                            if !recipe.notes.isEmpty { Text(recipe.notes).font(.m3BodyMedium) }
                            if !recipe.source.isEmpty {
                                Label(recipe.source, systemImage: "link").font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                    }
                }
                if let parentID = recipe.variantOf, let parent = model.recipe(parentID) {
                    NavigationLink(value: parent.id) {
                        Label("Variante di «\(parent.displayTitle)»", systemImage: "arrow.triangle.branch")
                            .font(.m3LabelLarge)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(m3.surface)
        .navigationTitle(recipe.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.toggleFavorite(recipe.id) } label: {
                    Image(systemName: recipe.favorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(recipe.favorite ? "Togli dalle preferite" : "Aggiungi alle preferite")
            }
            ToolbarItem(placement: .topBarTrailing) { menu(recipe, session: session) }
        }
        .sheet(item: $editing) { RecipeEditorView(draft: $0) }
        .sheet(item: Binding(get: { photoFull.map { IdentifiedString(value: $0) } }, set: { photoFull = $0?.value })) { p in
            PhotoViewer(name: p.value)
        }
        .confirmationDialog("Eliminare «\(recipe.displayTitle)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                model.recipesPath = NavigationPath()
                model.delete(recipe)
            }
        } message: {
            Text("L'operazione non si può annullare (a meno di ripristinare un backup).")
        }
    }

    private func header(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if recipe.photo != nil {
                StoredPhoto(name: recipe.photo, placeholder: recipe.emoji)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .clipShape(ExpressiveShape(corner: 34))
                    .onTapGesture { photoFull = recipe.photo }
            }
            HStack(alignment: .top, spacing: 12) {
                if recipe.photo == nil {
                    Text(recipe.emoji).font(.system(size: 40))
                        .frame(width: 68, height: 68)
                        .background(m3.primaryContainer, in: CookieShape())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.displayTitle).font(.m3HeadlineMedium).foregroundStyle(m3.onSurface)
                    FlowLayout(spacing: 6) {
                        TagLabel(text: peopleText(Double(recipe.servings)), icon: "person.2.fill", tones: m3.primaryTones)
                        if let p = recipe.prepMinutes { TagLabel(text: "Prep. \(Fmt.duration(p * 60))", icon: "hands.and.sparkles.fill", tones: m3.tertiaryTones) }
                        if let c = recipe.cookMinutes { TagLabel(text: "Cottura \(Fmt.duration(c * 60))", icon: "flame.fill", tones: m3.warningTones) }
                        if recipe.timesCooked > 0 { TagLabel(text: "Cucinata \(recipe.timesCooked)×", icon: "checkmark", tones: m3.successTones) }
                        ForEach(recipe.tags, id: \.self) { TagLabel(text: $0, icon: "number", tones: m3.neutral) }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func actions(_ recipe: Recipe) -> some View {
        HStack(spacing: 10) {
            PillButton(title: "Usa ricetta", icon: "frying.pan.fill", tones: m3.primaryTones) { model.useRecipe = recipe }
            RoundIconButton(icon: "cart.badge.plus", tones: m3.primaryTones, size: 54) {
                model.addToShopping(ScaleSession(recipe: recipe))
            }
            .accessibilityLabel("Aggiungi alla spesa")
            .disabled(recipe.ingredients.isEmpty)
        }
    }

    private func menu(_ recipe: Recipe, session: ScaleSession) -> some View {
        Menu {
            Button { editing = RecipeDraft(recipe: recipe) } label: { Label("Modifica", systemImage: "pencil") }
            Button {
                let copy = model.duplicate(recipe)
                model.recipesPath.append(copy.id)
            } label: { Label("Duplica", systemImage: "plus.square.on.square") }
            Divider()
            ShareLink(item: RecipeText.plain(session, prefs: model.prefs)) { Label("Condividi come testo", systemImage: "text.alignleft") }
            ShareLink(item: RecipeShareItem(recipeID: recipe.id), preview: SharePreview(recipe.displayTitle)) {
                Label("Invia file ricetta", systemImage: "doc.badge.arrow.up")
            }
            Divider()
            Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

/// `.ricetta` file created only when the user actually shares.
struct RecipeShareItem: Transferable {
    let recipeID: UUID

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .ricetta) { item in
            let url = try await MainActor.run { try AppModel.shared.writeShareFile(for: item.recipeID) }
            return SentTransferredFile(url)
        }
    }
}

struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
}

struct IngredientLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let scaled: ScaledIngredient
    var highlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scaled.ingredient.name).font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                if !scaled.ingredient.note.isEmpty {
                    Text(scaled.ingredient.note).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                }
            }
            Spacer(minLength: 8)
            Text(scaled.amountText(model.prefs))
                .font(.m3TitleSmall)
                .monospacedDigit()
                .foregroundStyle(highlighted ? m3.primary : m3.onSurface)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 9)
    }
}

struct StepCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let index: Int
    let step: RecipeStep
    let session: ScaleSession
    var onPhoto: () -> Void = {}

    var body: some View {
        M3Card {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onPrimaryContainer)
                    .frame(width: 34, height: 34)
                    .background(m3.primaryContainer, in: Circle())
                VStack(alignment: .leading, spacing: 10) {
                    if !step.text.isEmpty {
                        StepTextView(segments: StepRenderer.render(step.text, session: session, prefs: model.prefs), font: .m3BodyMedium)
                    }
                    if let p = step.photo {
                        StoredPhoto(name: p)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .onTapGesture(perform: onPhoto)
                    }
                    if let t = step.timerSeconds {
                        TagLabel(text: Fmt.duration(t), icon: "timer", tones: m3.warningTones)
                    }
                }
            }
        }
    }
}

/// Full-screen photo with pinch to zoom.
struct PhotoViewer: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            StoredPhoto(name: name, contentMode: .fit)
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, min(4, $0.magnification)) }.onEnded { _ in withAnimation { scale = 1 } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
