import SwiftUI
import RicettarioCore

struct ShoppingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var newItem = ""
    @State private var confirmClear = false
    @FocusState private var adding: Bool

    var body: some View {
        let items = model.data.shopping
        List {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(m3.primary)
                    TextField("Aggiungi a mano (es. 2 limoni)", text: $newItem)
                        .focused($adding)
                        .submitLabel(.done)
                        .onSubmit(addManual)
                }
            }
            if items.isEmpty {
                Section {
                    EmptyStateView(icon: "cart.fill", title: "Lista vuota",
                                   message: "Dalla scheda di una ricetta, o da «Usa ricetta» con le quantità ricalcolate, tocca il carrello per aggiungere gli ingredienti.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(ShoppingList.grouped(items), id: \.0) { cat, group in
                Section {
                    ForEach(group) { item in row(item) }
                        .onDelete { idx in
                            let ids = Set(idx.map { group[$0].id })
                            model.mutate { $0.shopping.removeAll { ids.contains($0.id) } }
                        }
                } header: {
                    Label(cat.title, systemImage: cat.icon)
                }
            }
        }
        .navigationTitle("Spesa")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: ShoppingList.text(items, prefs: model.prefs)) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { model.mutate { $0.shopping.removeAll(where: \.checked) } } label: {
                            Label("Togli gli spuntati", systemImage: "checkmark.circle")
                        }
                        .disabled(!items.contains(where: \.checked))
                        Button { model.mutate { d in for i in d.shopping.indices { d.shopping[i].checked = false } } } label: {
                            Label("Togli tutte le spunte", systemImage: "circle")
                        }
                        Button(role: .destructive) { confirmClear = true } label: { Label("Svuota la lista", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog("Svuotare la lista della spesa?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Svuota", role: .destructive) { model.mutate { $0.shopping = [] } }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            withAnimation(.m3Effects) {
                model.mutate { d in
                    if let i = d.shopping.firstIndex(where: { $0.id == item.id }) { d.shopping[i].checked.toggle() }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.checked ? m3.primary : m3.outline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).strikethrough(item.checked).foregroundStyle(item.checked ? m3.onSurfaceVariant : m3.onSurface)
                    if !item.sources.isEmpty {
                        Text(item.sources.joined(separator: ", ")).font(.caption).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
                    }
                }
                Spacer()
                if let q = ShoppingList.amountText(item, prefs: model.prefs) {
                    Text(q).monospacedDigit().foregroundStyle(m3.onSurfaceVariant)
                }
            }
        }
    }

    /// "2 limoni", "limoni x2", "farina": name and optional count.
    private func addManual() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var name = t
        var amount: Double?
        let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, let n = Fmt.parseAmount(parts[0]) {
            amount = n
            name = parts[1]
        } else if let r = t.range(of: " x", options: .backwards), let n = Fmt.parseAmount(String(t[r.upperBound...])) {
            amount = n
            name = String(t[..<r.lowerBound])
        }
        let match = Catalog.existing(named: name, in: model.pool)
        let item = ShoppingItem(name: match?.name ?? name.prefix(1).uppercased() + name.dropFirst(), catalogID: match?.id,
                                amount: amount, unit: .piece, category: match?.category ?? .other)
        model.mutate { $0.shopping.append(item) }
        newItem = ""
        adding = true
    }
}
