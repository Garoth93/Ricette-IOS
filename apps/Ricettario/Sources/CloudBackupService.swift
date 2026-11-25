import Foundation
import SwiftUI
import BackgroundTasks
import RicettarioCore

/// Automatic backups in iCloud Drive, in the shared container
/// `iCloud.com.garoth93.backup` › Documents › Ricettario (visible in the Files
/// app as iCloud Drive › Backup › Ricettario). One JSON per day plus "latest";
/// photos as separate files, uploaded once. Written when the data change,
/// when the app goes to background and from the background refresh.
/// Restore from Settings, or guided at first launch when the app is empty.
@MainActor
@Observable
final class CloudBackupService {
    static let shared = CloudBackupService()

    /// nil = not checked yet; false = iCloud off / not signed in / no entitlement.
    private(set) var available: Bool?
    private(set) var isWorking = false
    private(set) var lastBackupAt: Date? = UserDefaults.standard.object(forKey: Keys.lastAt) as? Date
    private(set) var lastError: String?
    private(set) var entries: [CloudBackupPlan.Entry] = []
    /// Set when an empty app finds a backup: RootView shows the guided restore.
    var offerRestore = false

    @ObservationIgnored private var scheduled: Task<Void, Never>?

    private enum Keys {
        static let fingerprint = "cloudBackup.fingerprint"
        static let lastAt = "cloudBackup.lastAt"
        static let restoreOffered = "cloudBackup.restoreOffered"
    }

    private var model: AppModel { AppModel.shared }

    // MARK: Folder

    /// Resolving the ubiquity container can block: always off the main thread.
    nonisolated static func folderURL() async -> URL? {
        await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: CloudBackupPlan.containerID) else { return nil }
            let folder = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(CloudBackupPlan.folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(CloudBackupPlan.photosFolder, isDirectory: true), withIntermediateDirectories: true)
            return folder
        }.value
    }

    // MARK: Backup

    /// After a change: back up a few seconds later (many edits → one write).
    func schedule() {
        guard model.data.settings.cloudBackup else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.backup(force: false)
        }
    }

    /// Writes the backup if the content changed since the last one (or `force`).
    /// An empty app never overwrites existing backups.
    @discardableResult
    func backup(force: Bool) async -> Bool {
        guard model.isLoaded, force || model.data.settings.cloudBackup, !model.data.isEmpty else { return false }
        let file = BackupFile(data: model.data)
        let fp = CloudBackupPlan.fingerprint(file)
        if !force, fp == UserDefaults.standard.string(forKey: Keys.fingerprint) { return false }
        guard let data = try? file.encoded() else { return false }
        isWorking = true
        defer { isWorking = false }
        guard let folder = await Self.folderURL() else {
            available = false
            if force { lastError = "iCloud Drive non disponibile: controlla di aver fatto l'accesso a iCloud e che iCloud Drive sia attivo." }
            return false
        }
        available = true
        let now = Date()
        let photos = Array(file.data.photoNames)
        let result = await Task.detached(priority: .utility) { () -> String? in
            do {
                try Self.uploadMissing(photos, from: AppFiles.photos, to: folder.appendingPathComponent(CloudBackupPlan.photosFolder))
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.dailyName(for: now)))
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.latestName))
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for name in CloudBackupPlan.namesToPrune(names) {
                    Self.coordinatedDelete(folder.appendingPathComponent(name))
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let result {
            lastError = "Backup su iCloud non riuscito: \(result)"
            return false
        }
        lastError = nil
        lastBackupAt = now
        UserDefaults.standard.set(now, forKey: Keys.lastAt)
        UserDefaults.standard.set(fp, forKey: Keys.fingerprint)
        return true
    }

    /// Photos never change (a new photo has a new name): copy only the ones not in iCloud yet.
    nonisolated private static func uploadMissing(_ names: [String], from local: URL, to remote: URL) throws {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: remote.path)) ?? []
        for name in CloudBackupPlan.missing(names, existing: existing) {
            guard let d = try? Data(contentsOf: local.appendingPathComponent(name)) else { continue }
            try coordinatedWrite(d, to: remote.appendingPathComponent(name))
        }
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &err) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Downloads (if needed) and reads an iCloud file; nil after ~30 s.
    nonisolated private static func coordinatedRead(_ url: URL, attempts: Int = 60) async -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<attempts {
            var coordError: NSError?
            var out: Data?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { target in
                out = try? Data(contentsOf: target)
            }
            if let out { return out }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    // MARK: Restore

    /// Backups in the iCloud folder, newest first.
    func refreshEntries() async {
        guard let folder = await Self.folderURL() else {
            available = false
            entries = []
            return
        }
        available = true
        let names = await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }.value
        entries = CloudBackupPlan.entries(fromFileNames: names)
    }

    func load(_ entry: CloudBackupPlan.Entry) async throws -> BackupFile {
        guard let folder = await Self.folderURL() else { throw BackupError.unreadable }
        let url = folder.appendingPathComponent(entry.name)
        guard let data = await Task.detached(priority: .userInitiated, operation: { await Self.coordinatedRead(url) }).value else {
            throw BackupError.unreadable
        }
        return try BackupFile.decode(data)
    }

    /// Replaces the app data with the backup and downloads its photos.
    func restore(_ entry: CloudBackupPlan.Entry) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let file = try await load(entry)
            guard let folder = await Self.folderURL() else { throw BackupError.unreadable }
            let photos = Array(file.data.photoNames)
            await Task.detached(priority: .userInitiated) {
                // Ask iCloud for everything first, then read file by file.
                let remote = folder.appendingPathComponent(CloudBackupPlan.photosFolder)
                for name in photos { try? FileManager.default.startDownloadingUbiquitousItem(at: remote.appendingPathComponent(name)) }
                for name in photos where !FileManager.default.fileExists(atPath: AppFiles.photo(name).path) {
                    if let d = await Self.coordinatedRead(remote.appendingPathComponent(name), attempts: 20) {
                        try? d.write(to: AppFiles.photo(name), options: .atomic)
                    }
                }
            }.value
            model.apply(file)
            // The restored content is already in iCloud: no need to rewrite it.
            UserDefaults.standard.set(CloudBackupPlan.fingerprint(BackupFile(data: model.data)), forKey: Keys.fingerprint)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Background refresh

    /// Asks iOS for a background run in ~6 hours (backup if something changed).
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppModel.backupTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: First launch

    /// Empty app + backups in iCloud → guided restore (asked once).
    func offerRestoreIfNeeded() async {
        guard model.data.isEmpty, !UserDefaults.standard.bool(forKey: Keys.restoreOffered) else { return }
        await refreshEntries()
        guard !entries.isEmpty, model.data.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: Keys.restoreOffered)
        offerRestore = true
    }
}

/// Restore from iCloud: list of backups, preview, confirm.
struct CloudRestoreView: View {
    let firstLaunch: Bool
    @Environment(CloudBackupService.self) private var cloud
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var choice: CloudBackupPlan.Entry?
    @State private var preview: BackupFile?
    @State private var loading = false
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            List {
                if firstLaunch {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down.fill").font(.system(size: 40)).foregroundStyle(m3.primary)
                            Text("Bentornato!").font(.title2.weight(.bold))
                            Text("In iCloud Drive c'è un backup di Ricettario. Vuoi ripristinare le tue ricette?").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section {
                    if cloud.entries.isEmpty {
                        Text(cloud.available == false ? "iCloud Drive non disponibile." : "Nessun backup trovato.").foregroundStyle(.secondary)
                    }
                    ForEach(cloud.entries) { entry in
                        Button {
                            choice = entry
                            Task { await loadPreview(entry) }
                        } label: {
                            HStack {
                                Image(systemName: entry.isLatest ? "clock.arrow.circlepath" : "doc.text").foregroundStyle(m3.primary)
                                Text(title(entry)).foregroundStyle(.primary)
                                Spacer()
                                if choice == entry {
                                    if loading { ProgressView() } else { Image(systemName: "checkmark").foregroundStyle(m3.primary) }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Backup in iCloud Drive › Backup › Ricettario")
                } footer: {
                    Text("Il ripristino sostituisce ricette, ingredienti, lista della spesa e impostazioni con quelli del backup, foto comprese.")
                }
                if let preview, choice != nil {
                    Section {
                        LabeledContent("Ricette", value: "\(preview.data.recipes.count)")
                        LabeledContent("Ingredienti aggiunti", value: "\(preview.data.customIngredients.count)")
                        LabeledContent("Salvato il", value: preview.exportedAt.formatted(date: .long, time: .shortened))
                        Button {
                            if AppModel.shared.data.isEmpty { Task { await doRestore() } } else { confirm = true }
                        } label: {
                            Label("Ripristina", systemImage: "arrow.counterclockwise").font(.headline)
                        }
                        .disabled(cloud.isWorking)
                        if cloud.isWorking { HStack { ProgressView(); Text("Scarico le foto…").foregroundStyle(.secondary) } }
                    }
                }
                if let e = cloud.lastError {
                    Section { Text(e).foregroundStyle(m3.error) }
                }
            }
            .navigationTitle("Ripristina da iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(firstLaunch ? "Inizia da zero" : "Chiudi") { dismiss() }
                }
            }
            .confirmationDialog("Sostituire i dati attuali?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Ripristina il backup", role: .destructive) { Task { await doRestore() } }
            } message: { Text("Le ricette attuali verranno sostituite da quelle del backup.") }
            .task {
                await cloud.refreshEntries()
                if let first = cloud.entries.first, choice == nil {
                    choice = first
                    await loadPreview(first)
                }
            }
        }
    }

    private func doRestore() async {
        guard let choice else { return }
        await cloud.restore(choice)
        if cloud.lastError == nil { dismiss() }
    }

    private func title(_ e: CloudBackupPlan.Entry) -> String {
        if let d = e.day { return d.formatted(date: .complete, time: .omitted).capitalized }
        return "Ultimo backup"
    }

    private func loadPreview(_ entry: CloudBackupPlan.Entry) async {
        loading = true
        preview = try? await cloud.load(entry)
        loading = false
    }
}
