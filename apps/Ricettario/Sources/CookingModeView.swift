import SwiftUI
import RicettarioCore

/// Step by step, big text, screen always on, timers.
/// Page 0 = ingredients to prepare, then one page per step, then the end.
struct CookingModeView: View {
    let session: ScaleSession
    let onFinish: (Bool) -> Void
    @Environment(AppModel.self) private var model
    @Environment(TimerCenter.self) private var timers
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cooking.textScale") private var textScale = 1.0
    @State private var page = 0
    @State private var ready: Set<UUID> = []
    @State private var showIngredients = false

    private var r: Recipe { session.original }
    private var hasIngredients: Bool { !r.ingredients.isEmpty }
    private var firstStepPage: Int { hasIngredients ? 1 : 0 }
    private var lastPage: Int { firstStepPage + r.steps.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                TabView(selection: $page) {
                    if hasIngredients {
                        ingredientsPage.tag(0)
                    }
                    ForEach(Array(r.steps.enumerated()), id: \.element.id) { i, step in
                        stepPage(step, index: i).tag(firstStepPage + i)
                    }
                    endPage.tag(lastPage)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.m3Spatial, value: page)
                if !timers.timers.isEmpty {
                    TimerStrip().padding(.horizontal, 16).padding(.bottom, 8)
                }
                navigation
            }
            .background(m3.surface)
            .navigationTitle(r.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Chiudi")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { textScale = max(0.8, textScale - 0.15) } label: { Image(systemName: "textformat.size.smaller") }
                        .accessibilityLabel("Testo più piccolo")
                    Button { textScale = min(2.0, textScale + 0.15) } label: { Image(systemName: "textformat.size.larger") }
                        .accessibilityLabel("Testo più grande")
                    if hasIngredients {
                        Button { showIngredients = true } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("Ingredienti")
                    }
                }
            }
            .sheet(isPresented: $showIngredients) {
                NavigationStack {
                    ScrollView { ingredientList.padding(16) }
                        .navigationTitle("Ingredienti · \(peopleText(session.servings))")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { showIngredients = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var stepFont: Font { .system(size: 24 * textScale, weight: .medium, design: .rounded) }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0...lastPage, id: \.self) { i in
                Capsule()
                    .fill(i <= page ? m3.primary : m3.secondaryContainer)
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.m3Effects, value: page)
    }

    // MARK: Pages

    private var ingredientsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prepara gli ingredienti").font(.m3HeadlineMedium)
                Text("Per \(peopleText(session.servings)). Tocca per spuntare quello che hai già pronto.")
                    .font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
                ingredientList
            }
            .padding(16)
        }
    }

    private var ingredientList: some View {
        VStack(spacing: 8) {
            ForEach(session.ingredients) { s in
                let on = ready.contains(s.id)
                Button {
                    withAnimation(.m3Effects) { if on { ready.remove(s.id) } else { ready.insert(s.id) } }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24 * min(textScale, 1.4)))
                            .foregroundStyle(on ? m3.primary : m3.outline)
                        Text(s.ingredient.name)
                            .font(.system(size: 19 * textScale, weight: .medium, design: .rounded))
                            .strikethrough(on)
                            .foregroundStyle(on ? m3.onSurfaceVariant : m3.onSurface)
                        Spacer()
                        Text(s.amountText(model.prefs))
                            .font(.system(size: 19 * textScale, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(m3.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepPage(_ step: RecipeStep, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Passaggio \(index + 1) di \(r.steps.count)")
                    .font(.m3LabelLarge).foregroundStyle(m3.primary)
                if let p = step.photo {
                    StoredPhoto(name: p)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                if !step.text.isEmpty {
                    StepTextView(segments: StepRenderer.render(step.text, session: session, prefs: model.prefs), font: stepFont)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let used = Array(Set(StepText.references(step.text)))
                if !used.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(session.ingredients.filter { used.contains($0.id) }) { s in
                            TagLabel(text: "\(s.ingredient.name) · \(s.amountText(model.prefs))", tones: m3.neutral)
                        }
                    }
                }
                if let seconds = step.timerSeconds { timerControl(step, seconds: seconds) }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func timerControl(_ step: RecipeStep, seconds: Int) -> some View {
        if let t = timers.timer(for: step.id) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = t.remaining(at: ctx.date)
                M3Card(color: left == 0 ? m3.errorContainer : m3.warningContainer) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(left == 0 ? "Tempo scaduto!" : Fmt.clock(left))
                                .font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text(t.isPaused ? "In pausa" : "Timer del passaggio").font(.m3LabelMedium)
                        }
                        Spacer()
                        if left > 0 {
                            RoundIconButton(icon: t.isPaused ? "play.fill" : "pause.fill", tones: m3.warningTones, size: 50, filled: true) {
                                if t.isPaused { timers.resume(t.id) } else { timers.pause(t.id) }
                            }
                        }
                        RoundIconButton(icon: "plus", tones: m3.warningTones, size: 50) { timers.add(t.id, seconds: 60) }
                        RoundIconButton(icon: "xmark", tones: m3.warningTones, size: 50) { timers.cancel(t.id) }
                    }
                    .foregroundStyle(left == 0 ? m3.onErrorContainer : m3.onWarningContainer)
                }
            }
        } else {
            PillButton(title: "Avvia timer · \(Fmt.duration(seconds))", icon: "timer", tones: m3.warningTones) {
                let label = "Passaggio \((r.steps.firstIndex { $0.id == step.id } ?? 0) + 1)"
                timers.start(label: label, recipeTitle: r.displayTitle, seconds: seconds, stepID: step.id)
            }
        }
    }

    private var endPage: some View {
        VStack(spacing: 20) {
            Spacer()
            IconBadge(icon: "fork.knife", tones: m3.primaryTones, size: 120, cookie: true, filled: true)
            Text("Buon appetito!").font(.m3HeadlineLarge)
            Text("\(r.displayTitle) per \(peopleText(session.servings)).")
                .font(.m3BodyLarge).foregroundStyle(m3.onSurfaceVariant).multilineTextAlignment(.center)
            PillButton(title: "Fatto, l'ho cucinata", icon: "checkmark", tones: m3.primaryTones) {
                onFinish(true)
                dismiss()
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding(16)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            PillButton(title: "Indietro", icon: "chevron.left", tones: m3.primaryTones, filled: false) {
                page = max(0, page - 1)
            }
            .disabled(page == 0)
            .opacity(page == 0 ? 0.4 : 1)
            PillButton(title: page >= lastPage - 1 ? "Fine" : "Avanti", icon: "chevron.right", tones: m3.primaryTones) {
                page = min(lastPage, page + 1)
            }
            .disabled(page == lastPage)
            .opacity(page == lastPage ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
