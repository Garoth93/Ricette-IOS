import Foundation

/// Minimal JSON persistence for any `Codable` value (atomic writes).
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL
    public let compact: Bool

    public init(url: URL, compact: Bool = false) {
        self.url = url
        self.compact = compact
    }

    /// nil when the file does not exist yet.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder.decode(Value.self, from: Data(contentsOf: url))
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder(compact: compact).encode(value).write(to: url, options: .atomic)
    }

    public static func encoder(compact: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case wrongApp
    case unreadable
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .wrongApp: return "Questo file non è un backup di Ricettario."
        case .unreadable: return "File non leggibile."
        case .newerVersion: return "Il file è stato creato da una versione più recente dell'app: aggiornala e riprova."
        }
    }
}

/// Versioned backup file (JSON). In iCloud the photos are separate files
/// next to it; the manual export embeds them in base64 (`photos`).
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let appName = "Ricettario"

    public var version: Int
    public var app: String
    public var exportedAt: Date
    public var data: RicettarioData
    /// File name → base64 JPEG (manual export only).
    public var photos: [String: String]?

    public init(data: RicettarioData, photos: [String: Data]? = nil, now: Date = Date()) {
        version = Self.currentVersion
        app = Self.appName
        exportedAt = now
        self.data = data
        self.photos = photos?.mapValues { $0.base64EncodedString() }
    }

    public func encoded(pretty: Bool = false) throws -> Data {
        try JSONFileStore<BackupFile>.encoder(compact: !pretty).encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        guard let file = try? JSONFileStore<BackupFile>.decoder.decode(BackupFile.self, from: data) else {
            if (try? RecipeShareFile.decode(data)) != nil { throw BackupError.wrongApp }
            throw BackupError.unreadable
        }
        guard file.app == appName else { throw BackupError.wrongApp }
        guard file.version <= currentVersion else { throw BackupError.newerVersion }
        return file
    }

    public var photoData: [String: Data] {
        (photos ?? [:]).compactMapValues { Data(base64Encoded: $0) }
    }
}

/// One recipe shared with someone else (`.ricetta` file): recipe, the
/// user's pool entries it uses and its photos.
public struct RecipeShareFile: Codable, Equatable, Sendable {
    public static let fileExtension = "ricetta"

    public var app: String
    public var kind: String
    public var version: Int
    public var recipe: Recipe
    public var ingredients: [CatalogIngredient]
    public var photos: [String: String]

    public init(recipe: Recipe, data: RicettarioData, photos: [String: Data]) {
        app = BackupFile.appName
        kind = "recipe"
        version = 1
        self.recipe = recipe
        let ids = Set(recipe.ingredients.compactMap(\.catalogID))
        ingredients = data.customIngredients.filter { ids.contains($0.id) }
        self.photos = photos.mapValues { $0.base64EncodedString() }
    }

    public func encoded() throws -> Data { try JSONFileStore<RecipeShareFile>.encoder(compact: false).encode(self) }

    public static func decode(_ data: Data) throws -> RecipeShareFile {
        guard let f = try? JSONFileStore<RecipeShareFile>.decoder.decode(RecipeShareFile.self, from: data),
              f.app == BackupFile.appName, f.kind == "recipe" else { throw BackupError.unreadable }
        return f
    }

    /// File name for sharing: "Lasagne alla bolognese.ricetta".
    public var fileName: String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let t = recipe.displayTitle.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "\(t.isEmpty ? "Ricetta" : t).\(Self.fileExtension)"
    }
}

/// Import strategies.
public enum DataMerge {
    /// Adds the recipes and pool entries of a backup to the current data:
    /// same id → the most recently modified wins. Shopping list and
    /// settings stay those of the phone.
    public static func merge(_ current: RicettarioData, with incoming: RicettarioData) -> (data: RicettarioData, added: Int, updated: Int) {
        var out = current
        var added = 0, updated = 0
        for r in incoming.recipes {
            if let i = out.recipes.firstIndex(where: { $0.id == r.id }) {
                if r.updatedAt > out.recipes[i].updatedAt {
                    out.recipes[i] = r
                    updated += 1
                }
            } else {
                out.recipes.append(r)
                added += 1
            }
        }
        for c in incoming.customIngredients where !out.customIngredients.contains(where: { $0.id == c.id }) {
            out.customIngredients.append(c)
        }
        for (k, v) in incoming.seedOverrides where out.seedOverrides[k] == nil { out.seedOverrides[k] = v }
        return (out, added, updated)
    }

    /// Replace: the backup data, keeping the revision counter increasing.
    public static func replace(_ current: RicettarioData, with incoming: RicettarioData) -> RicettarioData {
        var out = incoming
        out.revision = max(current.revision, incoming.revision) + 1
        return out
    }

    /// A shared recipe enters as a new recipe (new id if already present),
    /// with the user's pool entries it needs. Photo names are renamed
    /// through `photoNames` (old → new) when given.
    public static func importShared(_ file: RecipeShareFile, into current: RicettarioData,
                                    photoNames: [String: String] = [:], now: Date = Date()) -> (data: RicettarioData, recipe: Recipe) {
        var out = current
        var r = file.recipe
        if out.recipes.contains(where: { $0.id == r.id }) { r.id = UUID() }
        r.createdAt = now
        r.updatedAt = now
        r.favorite = false
        r.timesCooked = 0
        r.lastCookedAt = nil
        if let p = r.photo { r.photo = photoNames[p] ?? p }
        r.steps = r.steps.map { s in
            var s = s
            if let p = s.photo { s.photo = photoNames[p] ?? p }
            return s
        }
        // Pool entries: reuse one with the same name, else add.
        let pool = Catalog.pool(out)
        var remap: [String: String] = [:]
        for c in file.ingredients {
            if out.customIngredients.contains(where: { $0.id == c.id }) { continue }
            if let same = Catalog.existing(named: c.name, in: pool) { remap[c.id] = same.id } else { out.customIngredients.append(c) }
        }
        r.ingredients = r.ingredients.map { i in
            var i = i
            if let id = i.catalogID, let n = remap[id] { i.catalogID = n }
            return i
        }
        out.recipes.append(r)
        return (out, r)
    }
}

/// Automatic backups in iCloud Drive: shared container
/// `iCloud.com.garoth93.backup`, sub-folder "Ricettario", visible in Files.
///
/// Files: `Ricettario-backup-yyyy-MM-dd.json` (one per day, the last
/// `keepDaily` kept), `Ricettario-backup-latest.json`, and `photos/<name>`
/// written once (photos never change: a new photo gets a new name).
public enum CloudBackupPlan {
    public static let containerID = "iCloud.com.garoth93.backup"
    public static let folderName = "Ricettario"
    public static let latestName = "Ricettario-backup-latest.json"
    public static let prefix = "Ricettario-backup-"
    public static let photosFolder = "photos"
    public static let keepDaily = 30

    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        /// Day of the backup (nil for "latest").
        public var day: Date?
        public var isLatest: Bool { day == nil }
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func dailyName(for date: Date) -> String {
        "\(prefix)\(dayFormatter().string(from: date)).json"
    }

    /// iCloud placeholder of a file not downloaded yet: ".name.json.icloud".
    public static func realName(_ fileName: String) -> String {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return fileName }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    /// Backups found in the folder, newest first ("latest" on top).
    public static func entries(fromFileNames names: [String]) -> [Entry] {
        let f = dayFormatter()
        var latest: Entry?
        var daily: [Entry] = []
        for raw in Set(names.map(realName)) {
            if raw == latestName {
                latest = Entry(name: raw, day: nil)
            } else if raw.hasPrefix(prefix), raw.hasSuffix(".json") {
                let stamp = String(raw.dropFirst(prefix.count).dropLast(5))
                if let d = f.date(from: stamp) { daily.append(Entry(name: raw, day: d)) }
            }
        }
        daily.sort { $0.day! > $1.day! }
        return (latest.map { [$0] } ?? []) + daily
    }

    /// Daily files beyond the newest `keep`.
    public static func namesToPrune(_ names: [String], keep: Int = keepDaily) -> [String] {
        let daily = entries(fromFileNames: names).filter { !$0.isLatest }
        return daily.count > keep ? daily[keep...].map(\.name) : []
    }

    /// Photos to upload: wanted ones not yet in iCloud.
    public static func missing(_ wanted: [String], existing: [String]) -> [String] {
        let have = Set(existing.map(realName))
        return wanted.filter { !have.contains($0) }
    }

    /// Fingerprint of the content (not of the moment): unchanged → no new
    /// backup needed.
    public static func fingerprint(_ backup: BackupFile) -> String {
        var b = backup
        b.exportedAt = Date(timeIntervalSince1970: 0)
        b.data.revision = 0
        guard let data = try? JSONFileStore<BackupFile>.encoder(compact: true).encode(b) else { return "" }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16) + "-" + String(data.count)
    }
}
