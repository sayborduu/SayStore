import Foundation
import CoreData
import Zip

// MARK: - Storage Mode

enum BackupStorageMode: String, Codable, CaseIterable {
    case fullApp
    case urlOnly

    var label: String {
        switch self {
        case .fullApp: return "Full App"
        case .urlOnly: return "URL Only"
        }
    }
}

// MARK: - BackupAppItem

struct BackupAppItem: Codable, Identifiable, Hashable {
    let uuid: String
    let name: String
    let version: String
    let identifier: String
    let isSigned: Bool
    let sourceURL: String?
    let date: Date?
    let icon: String?
    var isSelected: Bool
    var storageMode: BackupStorageMode

    var id: String { uuid }

    var canUseURLOnly: Bool {
        guard let sourceURL, !sourceURL.isEmpty else { return false }
        return URL(string: sourceURL) != nil
    }
}

extension BackupAppItem {
    init(signed: Signed) {
        self.uuid = signed.uuid ?? UUID().uuidString
        self.name = signed.name ?? "Unknown"
        self.version = signed.version ?? "Unknown"
        self.identifier = signed.identifier ?? "Unknown"
        self.isSigned = true
        self.sourceURL = signed.source?.absoluteString
        self.date = signed.date
        self.icon = signed.icon
        self.isSelected = true
        self.storageMode = .fullApp
    }

    init(imported: Imported) {
        self.uuid = imported.uuid ?? UUID().uuidString
        self.name = imported.name ?? "Unknown"
        self.version = imported.version ?? "Unknown"
        self.identifier = imported.identifier ?? "Unknown"
        self.isSigned = false
        self.sourceURL = imported.source?.absoluteString
        self.date = imported.date
        self.icon = imported.icon
        self.isSelected = true
        self.storageMode = .fullApp
    }
}

// MARK: - BackupCertificateItem

struct BackupCertificateItem: Codable, Identifiable, Hashable {
    let uuid: String
    let nickname: String?
    let appIDName: String?
    let expiration: Date?
    var isSelected: Bool

    var id: String { uuid }
}

extension BackupCertificateItem {
    init(cert: CertificatePair) {
        self.uuid = cert.uuid ?? UUID().uuidString
        self.nickname = cert.nickname
        self.expiration = cert.expiration
        self.isSelected = true
        if let decoded = Storage.shared.getProvisionFileDecoded(for: cert) {
            self.appIDName = decoded.AppIDName
        } else {
            self.appIDName = nil
        }
    }
}

// MARK: - BackupSourceItem

struct BackupSourceItem: Codable, Identifiable, Hashable {
    let identifier: String
    let name: String?
    let sourceURL: String?
    var isSelected: Bool

    var id: String { identifier }
}

extension BackupSourceItem {
    init(source: AltSource) {
        self.identifier = source.identifier ?? UUID().uuidString
        self.name = source.name
        self.sourceURL = source.sourceURL?.absoluteString
        self.isSelected = true
    }
}

// MARK: - BackupContents

struct BackupContents: Codable {
    let apps: [BackupAppItem]
    let certificates: [BackupCertificateItem]
    let sources: [BackupSourceItem]
    let includesSettings: Bool
    let includesArchives: Bool
}

// MARK: - Backup

struct Backup: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let name: String
    let fileSize: Int64
    let appCount: Int
    let signedAppCount: Int
    let importedAppCount: Int
    let certificateCount: Int
    let sourceCount: Int
    let includesSettings: Bool
    let includesArchives: Bool
}

// MARK: - RestoreResult

struct RestoreResult {
    let appsRestored: Int
    let appsSkipped: Int
    let certificatesRestored: Int
    let sourcesAdded: Int
    let settingsRestored: Bool
}

// MARK: - BackupManager

class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published var backups: [Backup] = []
    @Published var contentsCache: [UUID: BackupContents] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        loadBackups()
    }

    private var metadataURL: URL {
        FileManager.default.backups.appendingPathComponent("backups.json")
    }

    func loadBackups() {
        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? decoder.decode([Backup].self, from: data) else {
            backups = []
            return
        }
        backups = loaded.sorted(by: { $0.date > $1.date })
    }

    private func saveMetadata() {
        try? FileManager.default.createDirectoryIfNeeded(at: FileManager.default.backups)
        try? encoder.encode(backups).write(to: metadataURL, options: .atomic)
    }

    func backupFileURL(for backup: Backup) -> URL {
        FileManager.default.backups.appendingPathComponent("\(backup.id.uuidString).zip")
    }

    func readContents(for backup: Backup) -> BackupContents? {
        if let cached = contentsCache[backup.id] {
            return cached
        }
        let zipURL = backupFileURL(for: backup)
        guard FileManager.default.fileExists(atPath: zipURL.path) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BackupRead_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectoryIfNeeded(at: tempDir)
            try Zip.unzipFile(zipURL, destination: tempDir, overwrite: true, password: nil)
            let contentsURL = tempDir.appendingPathComponent("contents.json")
            guard let data = try? Data(contentsOf: contentsURL) else { return nil }
            let contents = try decoder.decode(BackupContents.self, from: data)
            contentsCache[backup.id] = contents
            return contents
        } catch {
            return nil
        }
    }

    func createBackup(
        name: String,
        signedApps: [BackupAppItem],
        importedApps: [BackupAppItem],
        certificates: [BackupCertificateItem],
        sources: [BackupSourceItem],
        includeSettings: Bool,
        includeArchives: Bool
    ) async throws -> Backup {
        let id = UUID()
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("BackupWork_\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectoryIfNeeded(at: workDir)

        defer { try? FileManager.default.removeItem(at: workDir) }

        var totalApps = 0
        var totalSigned = 0
        var totalImported = 0

        let selectedSigned = signedApps.filter { $0.isSelected }
        let selectedImported = importedApps.filter { $0.isSelected }
        let selectedCerts = certificates.filter { $0.isSelected }
        let selectedSources = sources.filter { $0.isSelected }

        // Signed Apps
        if !selectedSigned.isEmpty {
            let appsDir = workDir.appendingPathComponent("signed")
            try FileManager.default.createDirectoryIfNeeded(at: appsDir)
            for item in selectedSigned {
                if item.storageMode == .fullApp {
                    let uuidDir = appsDir.appendingPathComponent(item.uuid)
                    try FileManager.default.createDirectoryIfNeeded(at: uuidDir)
                    let appURL = FileManager.default.signed(item.uuid)
                    if let appBundle = FileManager.default.getPath(in: appURL, for: "app") {
                        let dest = uuidDir.appendingPathComponent(appBundle.lastPathComponent)
                        try FileManager.default.copyItem(at: appBundle, to: dest)
                    }
                }
            }
            let appsListURL = appsDir.appendingPathComponent("apps.json")
            let listData = try encoder.encode(selectedSigned)
            try listData.write(to: appsListURL)
            totalSigned = selectedSigned.count
        }

        // Imported Apps
        if !selectedImported.isEmpty {
            let appsDir = workDir.appendingPathComponent("imported")
            try FileManager.default.createDirectoryIfNeeded(at: appsDir)
            for item in selectedImported {
                if item.storageMode == .fullApp {
                    let uuidDir = appsDir.appendingPathComponent(item.uuid)
                    try FileManager.default.createDirectoryIfNeeded(at: uuidDir)
                    let appURL = FileManager.default.unsigned(item.uuid)
                    if let appBundle = FileManager.default.getPath(in: appURL, for: "app") {
                        let dest = uuidDir.appendingPathComponent(appBundle.lastPathComponent)
                        try FileManager.default.copyItem(at: appBundle, to: dest)
                    }
                }
            }
            let appsListURL = appsDir.appendingPathComponent("apps.json")
            let listData = try encoder.encode(selectedImported)
            try listData.write(to: appsListURL)
            totalImported = selectedImported.count
        }

        totalApps = totalSigned + totalImported

        // Certificates
        if !selectedCerts.isEmpty {
            let certsDir = workDir.appendingPathComponent("certificates")
            try FileManager.default.createDirectoryIfNeeded(at: certsDir)
            for item in selectedCerts {
                let uuidDir = certsDir.appendingPathComponent(item.uuid)
                try FileManager.default.createDirectoryIfNeeded(at: uuidDir)
                let srcDir = FileManager.default.certificates(item.uuid)
                if let p12 = FileManager.default.getPath(in: srcDir, for: "p12") {
                    try FileManager.default.copyItem(at: p12, to: uuidDir.appendingPathComponent(p12.lastPathComponent))
                }
                if let provision = FileManager.default.getPath(in: srcDir, for: "mobileprovision") {
                    try FileManager.default.copyItem(at: provision, to: uuidDir.appendingPathComponent(provision.lastPathComponent))
                }
            }
            let certsListURL = certsDir.appendingPathComponent("certs.json")
            let listData = try encoder.encode(selectedCerts)
            try listData.write(to: certsListURL)
        }

        // Sources
        if !selectedSources.isEmpty {
            let sourcesURL = workDir.appendingPathComponent("sources.json")
            let listData = try encoder.encode(selectedSources)
            try listData.write(to: sourcesURL)
        }

        // Settings
        if includeSettings {
            let settings = _exportSettings()
            let settingsURL = workDir.appendingPathComponent("settings.json")
            try settings.write(to: settingsURL)
        }

        // Archives
        if includeArchives {
            let archivesDir = workDir.appendingPathComponent("archives")
            try FileManager.default.createDirectoryIfNeeded(at: archivesDir)
            if let contents = try? FileManager.default.contentsOfDirectory(at: FileManager.default.archives, includingPropertiesForKeys: nil) {
                for url in contents {
                    try FileManager.default.copyItem(at: url, to: archivesDir.appendingPathComponent(url.lastPathComponent))
                }
            }
        }

        // contents.json
        let contents = BackupContents(
            apps: selectedSigned + selectedImported,
            certificates: selectedCerts,
            sources: selectedSources,
            includesSettings: includeSettings,
            includesArchives: includeArchives
        )
        let contentsData = try encoder.encode(contents)
        try contentsData.write(to: workDir.appendingPathComponent("contents.json"))

        // zip
        let zipURL = FileManager.default.backups.appendingPathComponent("\(id.uuidString).zip")
        try FileManager.default.createDirectoryIfNeeded(at: FileManager.default.backups)

        try await Zip.zipFiles(
            paths: [workDir],
            zipFilePath: zipURL,
            password: nil,
            compression: ZipCompression.allCases[ArchiveHandler.getCompressionLevel()]
        )

        let fileSize = (try FileManager.default.attributesOfItem(atPath: zipURL.path))[.size] as? Int64 ?? 0

        let backup = Backup(
            id: id,
            date: Date(),
            name: name,
            fileSize: fileSize,
            appCount: totalApps,
            signedAppCount: totalSigned,
            importedAppCount: totalImported,
            certificateCount: selectedCerts.count,
            sourceCount: selectedSources.count,
            includesSettings: includeSettings,
            includesArchives: includeArchives
        )

        await MainActor.run {
            contentsCache[id] = contents
            backups.append(backup)
            backups.sort(by: { $0.date > $1.date })
            saveMetadata()
        }

        return backup
    }

    func restoreBackup(_ backup: Backup) async throws -> RestoreResult {
        let zipURL = backupFileURL(for: backup)
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("BackupRestore_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectoryIfNeeded(at: workDir)

        defer { try? FileManager.default.removeItem(at: workDir) }

        try Zip.unzipFile(zipURL, destination: workDir, overwrite: true, password: nil)

        var appsRestored = 0
        var appsSkipped = 0
        var certificatesRestored = 0
        var sourcesAdded = 0
        var settingsRestored = false

        // --- Restore Signed Apps ---
        let signedAppsDir = workDir.appendingPathComponent("signed")
        if FileManager.default.fileExists(atPath: signedAppsDir.path) {
            let appsListURL = signedAppsDir.appendingPathComponent("apps.json")
            if let data = try? Data(contentsOf: appsListURL) {
                let apps = (try? decoder.decode([BackupAppItem].self, from: data)) ?? []
                for item in apps {
                    let uuidDir = FileManager.default.signed(item.uuid)
                    try FileManager.default.createDirectoryIfNeeded(at: uuidDir)
                    if item.storageMode == .fullApp {
                        let srcUUIDDir = signedAppsDir.appendingPathComponent(item.uuid)
                        if let appBundle = FileManager.default.getPath(in: srcUUIDDir, for: "app") {
                            let dest = uuidDir.appendingPathComponent(appBundle.lastPathComponent)
                            try? FileManager.default.removeItem(at: dest)
                            try FileManager.default.copyItem(at: appBundle, to: dest)
                        }
                    }
                    let sourceURL: URL? = item.sourceURL.flatMap { URL(string: $0) }
                    let context = Storage.shared.context
                    let fetch: NSFetchRequest<Signed> = Signed.fetchRequest()
                    fetch.predicate = NSPredicate(format: "uuid == %@", item.uuid)
                    if let existing = try? context.fetch(fetch).first {
                        existing.name = item.name
                        existing.version = item.version
                        existing.identifier = item.identifier
                        existing.icon = item.icon
                        existing.date = item.date ?? Date()
                        existing.source = sourceURL
                        appsSkipped += 1
                    } else {
                        let signed = Signed(context: context)
                        signed.uuid = item.uuid
                        signed.name = item.name
                        signed.version = item.version
                        signed.identifier = item.identifier
                        signed.icon = item.icon
                        signed.date = item.date ?? Date()
                        signed.source = sourceURL
                        appsRestored += 1
                    }
                }
                try? context.save()
            }
        }

        // restore
        let importedAppsDir = workDir.appendingPathComponent("imported")
        if FileManager.default.fileExists(atPath: importedAppsDir.path) {
            let appsListURL = importedAppsDir.appendingPathComponent("apps.json")
            if let data = try? Data(contentsOf: appsListURL) {
                let apps = (try? decoder.decode([BackupAppItem].self, from: data)) ?? []
                for item in apps {
                    let uuidDir = FileManager.default.unsigned(item.uuid)
                    try FileManager.default.createDirectoryIfNeeded(at: uuidDir)
                    if item.storageMode == .fullApp {
                        let srcUUIDDir = importedAppsDir.appendingPathComponent(item.uuid)
                        if let appBundle = FileManager.default.getPath(in: srcUUIDDir, for: "app") {
                            let dest = uuidDir.appendingPathComponent(appBundle.lastPathComponent)
                            try? FileManager.default.removeItem(at: dest)
                            try FileManager.default.copyItem(at: appBundle, to: dest)
                        }
                    }
                    let sourceURL: URL? = item.sourceURL.flatMap { URL(string: $0) }
                    let context = Storage.shared.context
                    let fetch: NSFetchRequest<Imported> = Imported.fetchRequest()
                    fetch.predicate = NSPredicate(format: "uuid == %@", item.uuid)
                    if let existing = try? context.fetch(fetch).first {
                        existing.name = item.name
                        existing.version = item.version
                        existing.identifier = item.identifier
                        existing.icon = item.icon
                        existing.date = item.date ?? Date()
                        existing.source = sourceURL
                        appsSkipped += 1
                    } else {
                        let imported = Imported(context: context)
                        imported.uuid = item.uuid
                        imported.name = item.name
                        imported.version = item.version
                        imported.identifier = item.identifier
                        imported.icon = item.icon
                        imported.date = item.date ?? Date()
                        imported.source = sourceURL
                        appsRestored += 1
                    }
                }
                try? context.save()
            }
        }

        let certsDir = workDir.appendingPathComponent("certificates")
        if FileManager.default.fileExists(atPath: certsDir.path) {
            let certsListURL = certsDir.appendingPathComponent("certs.json")
            if let data = try? Data(contentsOf: certsListURL) {
                let items = (try? decoder.decode([BackupCertificateItem].self, from: data)) ?? []
                for item in items {
                    let srcUUIDDir = certsDir.appendingPathComponent(item.uuid)
                    let dstUUIDDir = FileManager.default.certificates(item.uuid)
                    try FileManager.default.createDirectoryIfNeeded(at: dstUUIDDir)
                    if let p12 = FileManager.default.getPath(in: srcUUIDDir, for: "p12") {
                        try? FileManager.default.removeItem(at: dstUUIDDir.appendingPathComponent(p12.lastPathComponent))
                        try FileManager.default.copyItem(at: p12, to: dstUUIDDir.appendingPathComponent(p12.lastPathComponent))
                    }
                    if let provision = FileManager.default.getPath(in: srcUUIDDir, for: "mobileprovision") {
                        try? FileManager.default.removeItem(at: dstUUIDDir.appendingPathComponent(provision.lastPathComponent))
                        try FileManager.default.copyItem(at: provision, to: dstUUIDDir.appendingPathComponent(provision.lastPathComponent))
                    }
                    let context = Storage.shared.context
                    let fetch: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
                    fetch.predicate = NSPredicate(format: "uuid == %@", item.uuid)
                    if (try? context.fetch(fetch).first) == nil {
                        let cert = CertificatePair(context: context)
                        cert.uuid = item.uuid
                        cert.nickname = item.nickname
                        cert.expiration = item.expiration
                        cert.date = Date()
                        certificatesRestored += 1
                    }
                }
                try? context.save()
            }
        }

        let sourcesURL = workDir.appendingPathComponent("sources.json")
        if let data = try? Data(contentsOf: sourcesURL) {
            let items = (try? decoder.decode([BackupSourceItem].self, from: data)) ?? []
            for item in items {
                if let urlString = item.sourceURL, let url = URL(string: urlString) {
                    let context = Storage.shared.context
                    let fetch: NSFetchRequest<AltSource> = AltSource.fetchRequest()
                    fetch.predicate = NSPredicate(format: "identifier == %@", item.identifier)
                    if (try? context.fetch(fetch).first) == nil {
                        let source = AltSource(context: context)
                        source.identifier = item.identifier
                        source.name = item.name
                        source.sourceURL = url
                        source.date = Date()
                        sourcesAdded += 1
                    }
                }
            }
            try? context.save()
        }

        let settingsURL = workDir.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            _importSettings(settings)
            settingsRestored = true
        }

        return RestoreResult(
            appsRestored: appsRestored,
            appsSkipped: appsSkipped,
            certificatesRestored: certificatesRestored,
            sourcesAdded: sourcesAdded,
            settingsRestored: settingsRestored
        )
    }

    func deleteBackup(_ backup: Backup) {
        try? FileManager.default.removeItem(at: backupFileURL(for: backup))
        contentsCache.removeValue(forKey: backup.id)
        backups.removeAll(where: { $0.id == backup.id })
        saveMetadata()
    }

    // MARK: - Settings Export/Import

    private func _exportSettings() -> Data {
        let keys = [
            "SayStore.compressionLevel",
            "SayStore.useShareSheetForArchiving",
            "SayStore.installationMethod",
            "SayStore.serverMethod",
            "SayStore.ipFix",
            "SayStore.userInterfaceStyle",
            "SayStore.userTintColor",
            "SayStore.shouldTintIcons",
            "SayStore.shouldChangeIconsBasedOffStyle",
            "SayStore.storeCellAppearance",
            "SayStore.sortOptionRawValue",
            "SayStore.sortAscending",
            "SayStore.useNovaDNSDynamic",
            "signing_options"
        ]
        var dict: [String: Any] = [:]
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = defaults.object(forKey: key) {
                dict[key] = value
            }
        }
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])) ?? Data()
    }

    private func _importSettings(_ dict: [String: Any]) {
        let defaults = UserDefaults.standard
        for (key, value) in dict {
            defaults.set(value, forKey: key)
        }
    }
}
