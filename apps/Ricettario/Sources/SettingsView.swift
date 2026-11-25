import SwiftUI
import UniformTypeIdentifiers
import RicettarioCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CloudBackupService.self) private var cloud
    @Environment(\.m3) private var m3
    @State private var exportDoc: DataFileDocument?
    @State private var exporting = false
    @State private var includePhotos = true
    @State private var importing = false
    @State private var imported: Data?
    @State private var restoring = false

    private var s: RicettarioSettings { model.data.settings }

    private func bind<T>(_ key: WritableKeyPath<RicettarioSettings, T>) -> Binding<T> {
        Binding(get: { model.data.settings[keyPath: key] }, set: { v in model.updateSettings { $0[keyPath: key] = v } })
    }

    var body: some View {
        Form {
            unitsSection
            appearanceSection
            Section {
                Toggle("Avvisa quando un timer finisce", isOn: bind(\.timerNotifications))
            } header: {
                Text("Timer")
            } footer: {
                Text("Notifica con suono anche con l'app chiusa o il telefono bloccato.")
            }
            cloudSection
            manualBackupSection
            Section("Informazioni") {
                LabeledContent("Ricette", value: "\(model.data.recipes.count)")
                LabeledContent("Ingredienti aggiunti da te", value: "\(model.data.customIngredients.count)")
                LabeledContent("Versione", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                Text("I dati restano sul telefono; il backup va solo nel tuo iCloud Drive.")
                    .font(.footnote).foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .navigationTitle("Impostazioni")
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json, defaultFilename: model.backupFileName) { result in
            if case .success = result { model.show("Backup esportato", icon: "square.and.arrow.up.fill") }
            exportDoc = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .ricetta]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { model.errorMessage = "Non riesco a leggere il file."; return }
            if let share = try? RecipeShareFile.decode(data) {
                model.pendingShare = PendingShare(file: share)
            } else {
                imported = data
            }
        }
        .confirmationDialog("Come importare il backup?", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } }),
                            titleVisibility: .visible) {
            Button("Aggiungi alle mie ricette") { if let d = imported { model.importBackup(d, mode: .merge) }; imported = nil }
            Button("Sostituisci tutto", role: .destructive) { if let d = imported { model.importBackup(d, mode: .replace) }; imported = nil }
        } message: {
            Text("«Aggiungi» unisce: per le ricette presenti in entrambi tiene la più recente. «Sostituisci» cancella i dati attuali.")
        }
        .sheet(isPresented: $restoring) { CloudRestoreView(firstLaunch: false) }
    }

    private var unitsSection: some View {
        Section {
            Picker("Mostra le quantità", selection: bind(\.units.system)) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if s.units.system == .metric {
                Toggle("Tieni cucchiai e tazze", isOn: bind(\.units.keepSpoons))
            }
            Toggle("Converti tazze e cucchiai in peso", isOn: bind(\.units.weighVolumes))
            Picker("Tazza", selection: bind(\.units.cupML)) {
                Text("240 ml (USA/Italia)").tag(240.0)
                Text("250 ml (metrica)").tag(250.0)
            }
            LabeledContent("Esempio", value: example)
        } header: {
            Text("Unità di misura")
        } footer: {
            Text("Le quantità sono salvate in grammi, millilitri o pezzi e convertite solo quando le vedi. La conversione in peso usa la densità dell'ingrediente, se c'è.")
        }
    }

    private var example: String {
        let flour = UnitConverter.display(base: 240, entryUnit: .cup, density: 0.53, prefs: s.units).text
        let butter = UnitConverter.display(base: 250, entryUnit: .g, density: 0.96, prefs: s.units).text
        return "1 tazza farina → \(flour) · 250 g burro → \(butter)"
    }

    private var appearanceSection: some View {
        Section("Aspetto") {
            Picker("Tema", selection: bind(\.appearance)) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Palette.seeds, id: \.hex) { seed in
                        let on = s.seed == seed.hex
                        Button { model.updateSettings { $0.seed = seed.hex } } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color(rgb: RGBColor(hex: seed.hex) ?? RGBColor(red: 0.8, green: 0.2, blue: 0.2)))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if on { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white) }
                                    }
                                    .overlay(Circle().strokeBorder(on ? m3.onSurface : .clear, lineWidth: 2).padding(-4))
                                Text(seed.name).font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var cloudSection: some View {
        Section {
            Toggle("Backup automatico", isOn: bind(\.cloudBackup))
            if let d = cloud.lastBackupAt {
                LabeledContent("Ultimo backup", value: d.formatted(date: .abbreviated, time: .shortened))
            }
            if cloud.available == false {
                Text("iCloud Drive non disponibile: accedi a iCloud e attiva iCloud Drive per questa app.")
                    .font(.footnote).foregroundStyle(m3.error)
            }
            Button {
                Task {
                    if await cloud.backup(force: true) { model.show("Backup su iCloud fatto", icon: "icloud.and.arrow.up.fill") }
                }
            } label: {
                HStack {
                    Label("Fai il backup ora", systemImage: "icloud.and.arrow.up")
                    if cloud.isWorking { Spacer(); ProgressView() }
                }
            }
            .disabled(cloud.isWorking || model.data.isEmpty)
            Button { restoring = true } label: { Label("Ripristina da iCloud", systemImage: "icloud.and.arrow.down") }
            if let e = cloud.lastError { Text(e).font(.footnote).foregroundStyle(m3.error) }
        } header: {
            Text("Backup su iCloud")
        } footer: {
            Text("Uno al giorno (ultimi 30) in iCloud Drive › Backup › Ricettario, foto comprese. Visibili nell'app File.")
        }
    }

    private var manualBackupSection: some View {
        Section {
            Toggle("Includi le foto", isOn: $includePhotos)
            Button {
                do {
                    exportDoc = DataFileDocument(data: try model.backupData(includePhotos: includePhotos))
                    exporting = true
                } catch {
                    model.errorMessage = "Esportazione non riuscita: \(error.localizedDescription)"
                }
            } label: { Label("Esporta backup JSON", systemImage: "square.and.arrow.up") }
            Button { importing = true } label: { Label("Importa backup o ricetta", systemImage: "square.and.arrow.down") }
        } header: {
            Text("Backup manuale")
        } footer: {
            Text("Un file JSON con ricette, ingredienti aggiunti, lista della spesa e impostazioni. Puoi importare anche i file .ricetta ricevuti.")
        }
    }
}
