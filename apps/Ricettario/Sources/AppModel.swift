import SwiftUI
import UIKit
import RicettarioCore

enum AppTab: Hashable {
    case recipes, shopping, pantry, settings
}

/// Files of the app in Application Support.
enum AppFiles {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Ricettario", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var data: URL { support.appendingPathComponent("ricettario-data.json") }
    static var previous: URL { support.appendingPathComponent("ricettario-data.json.bak") }

    static let photos: URL = {
        let dir = support.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func photo(_ name: String) -> URL { photos.appendingPathComponent(name) }
}

/// Serial writer: atomic write, previous version kept as `.bak`, never
/// overwrites newer data with older (revision).
actor DataWriter {
    private let store = JSONFileStore<RicettarioData>(url: AppFiles.data, compact: true)
    private var lastRevision = -1

    func save(_ data: RicettarioData) throws {
        guard data.revision > lastRevision else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: AppFiles.data.path) {
            try? fm.removeItem(at: AppFiles.previous)
            try? fm.copyItem(at: AppFiles.data, to: AppFiles.previous)
        }
        try store.save(data)
        lastRevision = data.revision
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
}

/// A `.ricetta` file opened from another app, waiting for confirmation.
struct PendingShare: Identifiable {
    let id = UUID()
    let file: RecipeShareFile
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    nonisolated static let backupTaskID = "com.garoth93.ricettario.backup"

    private(set) var data = RicettarioData()
    private(set) var isLoaded = false
    /// Ingredient pool (seed + user), cached.
    private(set) var pool: [CatalogIngredient] = Catalog.seed
    var tab: AppTab = .recipes
    var recipesPath = NavigationPath()
    var toast: Toast?
    var errorMessage: String?
    var pendingShare: PendingShare?
    /// "Usa ricetta" session shown full screen (temporary, never saved).
    var useRecipe: Recipe?

    private let writer = DataWriter()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        Task { await load() }
    }

    var prefs: UnitPreferences { data.settings.units }
    var seedColor: String { data.settings.seed }

    // MARK: - Loading and saving

    private func load() async {
        let result = await Task.detached(priority: .userInitiated) { () -> (RicettarioData?, Bool) in
            let store = JSONFileStore<RicettarioData>(url: AppFiles.data)
            if let d = try? store.load() { return (d, false) }
            guard FileManager.default.fileExists(atPath: AppFiles.data.path) else { return (nil, false) }
            // Unreadable: keep it aside and try the previous version.
            let aside = AppFiles.support.appendingPathComponent("ricettario-data-illeggibile-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: AppFiles.data, to: aside)
            let previous = try? JSONFileStore<RicettarioData>(url: AppFiles.previous).load()
            return (previous, true)
        }.value
        data = result.0 ?? RicettarioData()
        if result.1 {
            errorMessage = result.0 == nil
                ? "Il file dei dati non era leggibile ed è stato messo da parte. Puoi ripristinare un backup dalle Impostazioni."
                : "Il file dei dati non era leggibile: è stata ripristinata la copia precedente."
        }
        refreshPool()
        isLoaded = true
        cleanupOrphanPhotos()
        Task { await CloudBackupService.shared.offerRestoreIfNeeded() }
    }

    func mutate(_ change: (inout RicettarioData) -> Void) {
        let before = (data.customIngredients, data.seedOverrides, data.hiddenSeeds)
        change(&data)
        data.revision += 1
        if before.0 != data.customIngredients || before.1 != data.seedOverrides || before.2 != data.hiddenSeeds { refreshPool() }
        scheduleSave()
        CloudBackupService.shared.schedule()
    }

    private func refreshPool() { pool = Catalog.pool(data) }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let writer = writer
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do { try await writer.save(snapshot) } catch { errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)" }
        }
    }

    /// Writes immediately (going to background).
    func flush() {
        saveTask?.cancel()
        let snapshot = data
        let writer = writer
        Task { try? await writer.save(snapshot) }
    }

    func setActive(_ active: Bool) {
        if !active {
            flush()
            Task { await CloudBackupService.shared.backup(force: false) }
            CloudBackupService.scheduleBackgroundRefresh()
        }
    }

    func show(_ message: String, icon: String = "checkmark.circle.fill", style: Toast.Style = .success) {
        toast = Toast(message: message, icon: icon, style: style)
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: - Recipes

    func recipe(_ id: UUID) -> Recipe? { data.recipe(id) }

    func save(_ recipe: Recipe, previous: Recipe?) {
        let clean = RecipeOps.sanitized(recipe, previous: previous)
        mutate { $0.upsert(clean) }
    }

    func delete(_ recipe: Recipe) {
        mutate { $0.delete(recipe: recipe.id) }
        cleanupOrphanPhotos()
        show("Ricetta eliminata", icon: "trash.fill", style: .info)
    }

    @discardableResult
    func duplicate(_ recipe: Recipe) -> Recipe {
        let copy = recipe.duplicated()
        mutate { $0.recipes.append(copy) }
        show("Ricetta duplicata", icon: "plus.square.on.square")
        return copy
    }

    func toggleFavorite(_ id: UUID) {
        mutate { d in
            if let i = d.recipes.firstIndex(where: { $0.id == id }) { d.recipes[i].favorite.toggle() }
        }
    }

    func markCooked(_ id: UUID) {
        mutate { d in
            if let i = d.recipes.firstIndex(where: { $0.id == id }) {
                d.recipes[i].timesCooked += 1
                d.recipes[i].lastCookedAt = Date()
            }
        }
    }

    /// "Salva come variante": new recipe from the session.
    @discardableResult
    func saveVariant(_ session: ScaleSession, title: String) -> Recipe {
        let v = session.makeVariant(title: title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title)
        mutate { $0.recipes.append(v) }
        show("Variante salvata", icon: "square.on.square.badge.person.crop")
        return v
    }

    // MARK: - Shopping list

    func category(for ing: RecipeIngredient) -> IngredientCategory {
        if let id = ing.catalogID, let c = Catalog.item(id, in: data) { return c.category }
        return Catalog.existing(named: ing.name, in: pool)?.category ?? .other
    }

    func addToShopping(_ session: ScaleSession, only ids: Set<UUID>? = nil) {
        let items = session.ingredients.filter { ids?.contains($0.id) ?? true }
        // Computed before `mutate`: the closure reads `data` (no overlapping access).
        let list = ShoppingList.add(items, recipeTitle: session.original.displayTitle, to: data.shopping, categories: { self.category(for: $0) })
        mutate { $0.shopping = list }
        show("Aggiunti alla spesa (\(items.count))", icon: "cart.fill.badge.plus")
    }

    // MARK: - Pool

    func ingredient(_ id: String) -> CatalogIngredient? { Catalog.item(id, in: data) }

    func saveIngredient(_ item: CatalogIngredient) {
        mutate { d in
            if item.isSeed {
                if let seed = Catalog.seed.first(where: { $0.id == item.id }), seed == item {
                    d.seedOverrides[item.id] = nil
                } else {
                    d.seedOverrides[item.id] = item
                }
            } else if let i = d.customIngredients.firstIndex(where: { $0.id == item.id }) {
                d.customIngredients[i] = item
            } else {
                d.customIngredients.append(item)
            }
        }
    }

    func deleteIngredient(_ item: CatalogIngredient) {
        mutate { d in
            if item.isSeed {
                d.seedOverrides[item.id] = nil
                if !d.hiddenSeeds.contains(item.id) { d.hiddenSeeds.append(item.id) }
            } else {
                d.customIngredients.removeAll { $0.id == item.id }
            }
        }
    }

    func restoreHiddenSeeds() {
        mutate { $0.hiddenSeeds = [] }
    }

    // MARK: - Photos

    /// Saves a photo (JPEG, max 1600 px) and returns its file name.
    func savePhoto(_ image: UIImage) -> String? {
        let name = "\(UUID().uuidString.lowercased()).jpg"
        guard let jpeg = image.resizedForStorage(maxSide: 1600).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try jpeg.write(to: AppFiles.photo(name), options: .atomic)
            return name
        } catch {
            errorMessage = "Non riesco a salvare la foto: \(error.localizedDescription)"
            return nil
        }
    }

    func image(_ name: String) -> UIImage? {
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let img = UIImage(contentsOfFile: AppFiles.photo(name).path) else { return nil }
        imageCache.setObject(img, forKey: name as NSString)
        return img
    }

    /// Removes photo files no recipe uses (after deleting or editing).
    func cleanupOrphanPhotos(keeping extra: Set<String> = []) {
        guard isLoaded else { return }
        let used = data.photoNames.union(extra)
        Task.detached(priority: .utility) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: AppFiles.photos.path)) ?? []
            for n in names where !used.contains(n) {
                try? FileManager.default.removeItem(at: AppFiles.photo(n))
            }
        }
    }

    private func photoData(_ names: some Sequence<String>) -> [String: Data] {
        var out: [String: Data] = [:]
        for n in names { out[n] = try? Data(contentsOf: AppFiles.photo(n)) }
        return out
    }

    // MARK: - Export / import

    func backupData(includePhotos: Bool) throws -> Data {
        let file = BackupFile(data: data, photos: includePhotos ? photoData(data.photoNames) : nil)
        return try file.encoded(pretty: true)
    }

    var backupFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "Ricettario-backup-\(f.string(from: Date())).json"
    }

    enum ImportMode { case merge, replace }

    func importBackup(_ raw: Data, mode: ImportMode) {
        do {
            let file = try BackupFile.decode(raw)
            writePhotos(file.photoData)
            switch mode {
            case .merge:
                let m = DataMerge.merge(data, with: file.data)
                mutate { $0 = m.data }
                show("Importate \(m.added) ricette, aggiornate \(m.updated)", icon: "square.and.arrow.down.fill")
            case .replace:
                apply(file)
            }
        } catch BackupError.wrongApp {
            if let share = try? RecipeShareFile.decode(raw) { pendingShare = PendingShare(file: share) } else { errorMessage = BackupError.wrongApp.errorDescription }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Replaces everything with a backup (manual import or iCloud restore).
    func apply(_ file: BackupFile) {
        let replaced = DataMerge.replace(data, with: file.data)
        mutate { $0 = replaced }
        cleanupOrphanPhotos()
        show("Backup ripristinato: \(data.recipes.count) ricette", icon: "arrow.counterclockwise.circle.fill")
    }

    private func writePhotos(_ photos: [String: Data]) {
        for (name, d) in photos where !name.contains("/") {
            let url = AppFiles.photo(name)
            if !FileManager.default.fileExists(atPath: url.path) { try? d.write(to: url, options: .atomic) }
        }
    }

    /// Temporary `.ricetta` file for the share sheet (written on demand).
    func writeShareFile(for recipeID: UUID) throws -> URL {
        guard let recipe = data.recipe(recipeID) else { throw BackupError.unreadable }
        let file = RecipeShareFile(recipe: recipe, data: data, photos: photoData(recipe.photoNames))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file.fileName)
        try file.encoded().write(to: url, options: .atomic)
        return url
    }

    func importShared(_ share: RecipeShareFile) {
        // Photos get new names: never overwrite the user's files.
        var names: [String: String] = [:]
        for (old, b64) in share.photos {
            guard let d = Data(base64Encoded: b64) else { continue }
            let new = "\(UUID().uuidString.lowercased()).jpg"
            if (try? d.write(to: AppFiles.photo(new), options: .atomic)) != nil { names[old] = new }
        }
        let result = DataMerge.importShared(share, into: data, photoNames: names)
        mutate { $0 = result.data }
        tab = .recipes
        recipesPath = NavigationPath()
        recipesPath.append(result.recipe.id)
        show("Ricetta aggiunta", icon: "square.and.arrow.down.fill")
    }

    /// Files opened with the app (".ricetta" or a backup JSON).
    func handle(url: URL) {
        guard url.isFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else {
            errorMessage = "Non riesco a leggere il file."
            return
        }
        if let share = try? RecipeShareFile.decode(raw) {
            pendingShare = PendingShare(file: share)
        } else if (try? BackupFile.decode(raw)) != nil {
            importBackup(raw, mode: .merge)
        } else {
            errorMessage = "Il file non è una ricetta di Ricettario."
        }
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout RicettarioSettings) -> Void) {
        mutate { change(&$0.settings) }
    }
}

extension UIImage {
    func resizedForStorage(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide else { return self }
        let scale = maxSide / side
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
