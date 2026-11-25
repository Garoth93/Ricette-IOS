import SwiftUI
import RicettarioCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(CloudBackupService.self) private var cloud
    @Environment(TimerCenter.self) private var timers
    @Environment(\.m3) private var m3

    var body: some View {
        @Bindable var model = model
        @Bindable var cloud = cloud
        TabView(selection: $model.tab) {
            Tab("Ricette", systemImage: "book.closed.fill", value: AppTab.recipes) {
                NavigationStack(path: $model.recipesPath) {
                    RecipesView()
                        .navigationDestination(for: UUID.self) { RecipeDetailView(recipeID: $0) }
                }
            }
            Tab("Spesa", systemImage: "cart.fill", value: AppTab.shopping) {
                NavigationStack { ShoppingView() }
            }
            .badge(model.data.shopping.filter { !$0.checked }.count)
            Tab("Ingredienti", systemImage: "carrot.fill", value: AppTab.pantry) {
                NavigationStack { PantryView() }
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .fullScreenCover(item: $model.useRecipe) { recipe in
            UseRecipeView(recipe: recipe)
                .environment(\.m3, m3)
        }
        .sheet(item: $model.pendingShare) { share in
            ImportSharedView(share: share)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(
            get: { cloud.offerRestore && model.useRecipe == nil },
            set: { if !$0 { cloud.offerRestore = false } }
        )) {
            CloudRestoreView(firstLaunch: true)
        }
        .alert("Attenzione", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if !timers.timers.isEmpty, model.useRecipe == nil {
                TimerStrip()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 64)
            }
        }
        .animation(.m3Spatial, value: model.toast)
    }
}

/// A recipe received from someone else (`.ricetta`).
struct ImportSharedView: View {
    let share: PendingShare
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = share.file.recipe
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(r.emoji).font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.displayTitle).font(.m3TitleLarge)
                            Text("Per \(r.servings) persone · \(r.ingredients.count) ingredienti · \(r.steps.count) passaggi")
                                .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        model.importShared(share.file)
                        dismiss()
                    } label: {
                        Label("Aggiungi alle mie ricette", systemImage: "square.and.arrow.down.fill").font(.headline)
                    }
                } footer: {
                    Text("La ricetta viene aggiunta come nuova: le tue ricette non vengono modificate.")
                }
            }
            .navigationTitle("Ricetta ricevuta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }
}
