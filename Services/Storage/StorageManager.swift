//
//  StorageManager.swift
//  Dropies
//
//  Gestionnaire centralisé de persistance des données.
//  Orchestre les opérations de haut niveau sur `eleves.json`, `settings.json`
//  et l'arborescence des dossiers élèves.
//

import Foundation
import Observation

@Observable
public final class StorageManager: @unchecked Sendable {
    public var activeProvider: StorageProvider
    public var isLoading: Bool = false
    public var lastErrorMessage: String?

    // MARK: - Cache Local Déterministe pour Mode Hors-Ligne
    public let localCacheURL: URL
    public let localCacheProvider: LocalStorageProvider

    public init(activeProvider: StorageProvider = DropboxStorageProvider()) {
        self.activeProvider = activeProvider

        // Emplacement dédié du cache local déterministe (Application Support ou Documents)
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let cacheDir = appSupport.appendingPathComponent("DroopiesCache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        self.localCacheURL = cacheDir
        self.localCacheProvider = LocalStorageProvider(rootURL: cacheDir)
    }

    public func setProvider(_ provider: StorageProvider) {
        self.activeProvider = provider
    }

    // MARK: - Résolution de l'URL du dossier racine (Source)
    public var rootURL: URL {
        get {
            if let local = activeProvider as? LocalStorageProvider, let url = local.rootURL {
                return url
            }
            // Emplacement par défaut : Documents/Source
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
            return docs.appendingPathComponent("Source")
        }
        set {
            if let local = activeProvider as? LocalStorageProvider {
                local.setRootURL(newValue)
            } else {
                let local = LocalStorageProvider(rootURL: newValue)
                self.activeProvider = local
            }
        }
    }

    /// Résout l'URL locale absolue pour un chemin relatif.
    /// Si le fournisseur actif est Local, utilise rootURL ; sinon (Dropbox/Cloud/Hors-ligne),
    /// résout directement dans le cache local (localCacheURL).
    public func localURL(for relativePath: String) -> URL {
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let local = activeProvider as? LocalStorageProvider, let root = local.rootURL {
            return clean.isEmpty ? root : root.appendingPathComponent(clean)
        }
        return clean.isEmpty ? localCacheURL : localCacheURL.appendingPathComponent(clean)
    }

    // MARK: - Gestion de `Configuration/eleves.json`

    /// Charge et décode la liste officielle des élèves depuis `Configuration/eleves.json`
    /// (Miroir transparent : lit depuis le Cloud et met en cache local, ou lit directement depuis le cache local si hors-ligne).
    public func loadStudents() async throws -> [Student] {
        isLoading = true
        defer { isLoading = false }

        // S'assurer que le dossier Configuration existe dans le cache local
        try? await localCacheProvider.createDirectory(at: "Configuration")

        // 1. Si en ligne avec un compte Cloud distant, interroger Dropbox
        if NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) {
            try? await activeProvider.createDirectory(at: "Configuration")

            if let data = try? await activeProvider.readData(at: "Configuration/eleves.json") {
                // Mettre immédiatement en cache local pour l'accès hors-ligne
                try? await localCacheProvider.writeData(data, to: "Configuration/eleves.json")

                let decoder = JSONDecoder()
                if let students = try? decoder.decode([Student].self, from: data) {
                    if (try? await activeProvider.itemExists(at: "eleves.json")) == true {
                        try? await activeProvider.deleteItem(at: "eleves.json")
                    }
                    return students
                }
            }

            // Migration automatique depuis l'ancienne racine si existante
            if let legacyData = try? await activeProvider.readData(at: "eleves.json") {
                let decoder = JSONDecoder()
                if let students = try? decoder.decode([Student].self, from: legacyData) {
                    try? await activeProvider.writeData(legacyData, to: "Configuration/eleves.json")
                    try? await localCacheProvider.writeData(legacyData, to: "Configuration/eleves.json")
                    try? await activeProvider.deleteItem(at: "eleves.json")
                    return students
                }
            }
        }

        // 2. Si hors-ligne (ou échec Cloud), lire depuis le cache local déterministe
        if let localData = try? await localCacheProvider.readData(at: "Configuration/eleves.json") {
            let decoder = JSONDecoder()
            if let students = try? decoder.decode([Student].self, from: localData) {
                print("[StorageManager] Base élèves chargée depuis le cache local (\(students.count) élèves).")
                return students
            }
        }

        // 3. Fallback en mode développement LocalStorageProvider
        if let local = activeProvider as? LocalStorageProvider {
            if let data = try? await local.readData(at: "Configuration/eleves.json") {
                if let students = try? JSONDecoder().decode([Student].self, from: data) {
                    return students
                }
            }
        }

        return []
    }

    /// Enregistre la liste des élèves dans `Configuration/eleves.json` avec indentation propre (2 espaces)
    /// Persiste toujours dans le cache local, et pousse vers le Cloud si en ligne.
    public func saveStudents(_ students: [Student]) async throws {
        isLoading = true
        defer { isLoading = false }

        try? await localCacheProvider.createDirectory(at: "Configuration")

        // Réattribution d'ID croissants propres et déduplication stricte des identifiants
        var seenIds = Set<Int>()
        var nextAvailableId = 1
        var cleaned: [Student] = []
        for s in students {
            var copy = s
            if copy.id <= 0 || seenIds.contains(copy.id) {
                while seenIds.contains(nextAvailableId) {
                    nextAvailableId += 1
                }
                copy.id = nextAvailableId
            }
            seenIds.insert(copy.id)
            if copy.id >= nextAvailableId {
                nextAvailableId = copy.id + 1
            }
            cleaned.append(copy)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cleaned)

        // Sauvegarde impérative dans le cache local
        try await localCacheProvider.writeData(data, to: "Configuration/eleves.json")

        // Sauvegarde vers le Cloud si en ligne
        if NetworkMonitor.shared.isOnline {
            try? await activeProvider.createDirectory(at: "Configuration")
            try await activeProvider.writeData(data, to: "Configuration/eleves.json")

            if (try? await activeProvider.itemExists(at: "eleves.json")) == true {
                try? await activeProvider.deleteItem(at: "eleves.json")
            }
        }
    }

    // MARK: - Gestion de `Configuration/settings.json`

    /// Charge la configuration du portail depuis `Configuration/settings.json` (ou crée le fichier par défaut s'il est manquant)
    public func loadSettings() async throws -> AppSettings {
        try? await localCacheProvider.createDirectory(at: "Configuration")

        // 1. Tenter depuis le Cloud si en ligne
        if NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) {
            try? await activeProvider.createDirectory(at: "Configuration")
            if let data = try? await activeProvider.readData(at: "Configuration/settings.json") {
                try? await localCacheProvider.writeData(data, to: "Configuration/settings.json")
                if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                    if (try? await activeProvider.itemExists(at: "settings.json")) == true {
                        try? await activeProvider.deleteItem(at: "settings.json")
                    }
                    return settings
                }
            }

            // Migration automatique
            if let legacyData = try? await activeProvider.readData(at: "settings.json") {
                if let settings = try? JSONDecoder().decode(AppSettings.self, from: legacyData) {
                    try? await activeProvider.writeData(legacyData, to: "Configuration/settings.json")
                    try? await localCacheProvider.writeData(legacyData, to: "Configuration/settings.json")
                    try? await activeProvider.deleteItem(at: "settings.json")
                    return settings
                }
            }
        }

        // 2. Si hors-ligne ou échec Cloud, lire le cache local
        if let localData = try? await localCacheProvider.readData(at: "Configuration/settings.json") {
            if let settings = try? JSONDecoder().decode(AppSettings.self, from: localData) {
                return settings
            }
        }

        // 3. Configuration par défaut
        let defaultSettings = AppSettings()
        try? await saveSettings(defaultSettings)
        return defaultSettings
    }

    /// Sauvegarde les préférences dans `Configuration/settings.json`
    public func saveSettings(_ settings: AppSettings) async throws {
        try? await localCacheProvider.createDirectory(at: "Configuration")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)

        try await localCacheProvider.writeData(data, to: "Configuration/settings.json")

        if NetworkMonitor.shared.isOnline {
            try? await activeProvider.createDirectory(at: "Configuration")
            try await activeProvider.writeData(data, to: "Configuration/settings.json")
            if (try? await activeProvider.itemExists(at: "settings.json")) == true {
                try? await activeProvider.deleteItem(at: "settings.json")
            }
        }
    }

    // MARK: - Gestion de l'icône personnalisée du portail (`Configuration/Icone Portail.png`)

    /// Charge les données de l'icône personnalisée du portail si disponible
    public func loadPortalIconData() async -> Data? {
        try? await localCacheProvider.createDirectory(at: "Configuration")

        if NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) {
            if let data = try? await activeProvider.readData(at: "Configuration/Icone Portail.png"), !data.isEmpty {
                try? await localCacheProvider.writeData(data, to: "Configuration/Icone Portail.png")
                return data
            }
        }

        if let localData = try? await localCacheProvider.readData(at: "Configuration/Icone Portail.png"), !localData.isEmpty {
            return localData
        }

        return nil
    }

    /// Enregistre l'icône personnalisée du portail dans `Configuration/Icone Portail.png`
    public func savePortalIconData(_ data: Data) async throws {
        try? await localCacheProvider.createDirectory(at: "Configuration")
        try await localCacheProvider.writeData(data, to: "Configuration/Icone Portail.png")

        if NetworkMonitor.shared.isOnline {
            try? await activeProvider.createDirectory(at: "Configuration")
            try await activeProvider.writeData(data, to: "Configuration/Icone Portail.png")
        }
    }

    /// Rétablit l'icône par défaut en supprimant l'icône personnalisée
    public func deletePortalIcon() async throws {
        try? await localCacheProvider.deleteItem(at: "Configuration/Icone Portail.png")
        if NetworkMonitor.shared.isOnline {
            try? await activeProvider.deleteItem(at: "Configuration/Icone Portail.png")
        }
    }

    // MARK: - Création et vérification de l'arborescence

    /// S'assure que les dossiers racines standards existent dans le cache local et dans le Cloud si en ligne
    public func ensureSourceFolderStructure(onProgress: (@Sendable (Double, String) -> Void)? = nil) async throws {
        let directories = [
            "Configuration",
            "Documents",
            "Evaluations",
            "Evaluations/A corriger",
            "Evaluations/Backup",
            "Evaluations/Eleves",
            "Exports"
        ]

        // 1. Toujours s'assurer de l'arborescence dans le cache local (immédiat et non-bloquant)
        for (idx, dir) in directories.enumerated() {
            try? await localCacheProvider.createDirectory(at: dir)
            let prog = Double(idx + 1) / Double(directories.count)
            onProgress?(prog, "Dossier \(dir) vérifié en local")
        }

        // Si hors-ligne ou si le fournisseur actif est local, s'arrêter ici
        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else {
            return
        }

        // 2. En ligne : vérification Cloud groupée
        let existingRoot = (try? await activeProvider.listContents(at: "")) ?? []
        let existingRootNames = Set(existingRoot.filter { $0.isDirectory }.map { $0.name.lowercased() })

        for (idx, dir) in directories.enumerated() {
            let parts = dir.split(separator: "/").map(String.init)
            let isTopLevel = (parts.count == 1)

            // Si le dossier racine existe déjà, on évite un aller-retour réseau inutile
            if isTopLevel && existingRootNames.contains(dir.lowercased()) {
                let prog = Double(idx + 1) / Double(directories.count)
                onProgress?(prog, "Dossier \(dir) vérifié dans le Cloud")
                continue
            }

            try? await activeProvider.createDirectory(at: dir)
            let prog = Double(idx + 1) / Double(directories.count)
            onProgress?(prog, "Dossier \(dir) initialisé dans le Cloud")
        }
    }

    /// Crée immédiatement le dossier physique d'un élève dans le Cloud et génère son lien de partage
    public func ensureSingleStudentFolder(_ student: Student) async throws -> Student {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return student }
        try await ensureSourceFolderStructure()

        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else {
            return student
        }

        let classFolder = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))"
        let studentFolder = "\(classFolder)/\(student.folderName)"

        // 1. Créer le dossier s'il n'existe pas
        try await activeProvider.createDirectory(at: studentFolder)

        // 2. Générer ou récupérer immédiatement le lien partagé si manquant
        var copy = student
        if copy.urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let link = try await activeProvider.createSharedLink(for: studentFolder)
                copy.urlDropbox = link
            } catch {
                print("Avertissement génération lien partagé pour \(student.name): \(error)")
            }
        }
        return copy
    }

    /// Synchronisation automatique continue : Détecte les dossiers ou partages manquants,
    /// les génère et persiste `eleves.json` dans le Cloud, avec retour de progression élève par élève.
    public func autoSyncAllStudents(
        students: [Student],
        onProgress: (@Sendable (Int, Int, Student, String) -> Void)? = nil
    ) async throws -> [Student] {
        guard !students.isEmpty else { return [] }
        try await ensureSourceFolderStructure()

        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else {
            print("[StorageManager] Synchronisation fine des dossiers élèves ignorée en mode hors-ligne.")
            return students
        }

        var updatedStudents = students
        var hasChanges = false

        // Optimisation majeure : Regrouper par classe pour n'effectuer qu'une seule requête par classe
        let classNames = Set(students.compactMap { $0.classe.isEmpty ? nil : Student.sanitizeFolderName($0.classe) })
        var classContentsCache: [String: Set<String>] = [:]

        for className in classNames {
            let classFolder = "Evaluations/Eleves/\(className)"
            try? await activeProvider.createDirectory(at: classFolder)
            if let items = try? await activeProvider.listContents(at: classFolder) {
                classContentsCache[className] = Set(items.filter { $0.isDirectory }.map { $0.name.lowercased() })
            } else {
                classContentsCache[className] = []
            }
        }

        for (index, student) in students.enumerated() {
            guard !student.classe.isEmpty && !student.name.isEmpty else {
                onProgress?(index + 1, students.count, student, "Élève validé")
                continue
            }

            let cleanClass = Student.sanitizeFolderName(student.classe)
            let classFolder = "Evaluations/Eleves/\(cleanClass)"
            let studentFolder = "\(classFolder)/\(student.folderName)"
            let existingInClass = classContentsCache[cleanClass] ?? []

            // 1. Vérifier si le dossier physique existe déjà dans le cache local de la classe
            let folderAlreadyExists = existingInClass.contains(student.folderName.lowercased())
            if !folderAlreadyExists {
                onProgress?(index + 1, students.count, student, "Création du dossier Cloud pour \(student.name)...")
                try? await activeProvider.createDirectory(at: studentFolder)
                classContentsCache[cleanClass]?.insert(student.folderName.lowercased())
            }

            // 2. S'assurer de l'existence du lien de partage actif
            if updatedStudents[index].urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onProgress?(index + 1, students.count, student, "Génération du lien partagé pour \(student.name)...")
                if let link = try? await activeProvider.createSharedLink(for: studentFolder) {
                    updatedStudents[index].urlDropbox = link
                    hasChanges = true
                }
            }

            onProgress?(index + 1, students.count, student, "\(student.name) (\(student.classe))")
        }

        if hasChanges {
            try await saveStudents(updatedStudents)
        }
        return updatedStudents
    }

    /// Vérifie si le dossier de l'élève existe réellement dans le stockage distant/local
    public func studentFolderExists(_ student: Student) async -> Bool {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return false }
        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else { return true }
        let path = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))/\(student.folderName)"
        return (try? await activeProvider.itemExists(at: path)) ?? false
    }

    /// Supprime le dossier Cloud d'un élève
    public func deleteStudentFolder(_ student: Student) async throws {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return }
        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else { return }
        let path = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))/\(student.folderName)"
        try? await activeProvider.deleteItem(at: path)
    }

    /// Compte le nombre de copies présentes dans le dossier Cloud de l'élève
    public func countStudentCopies(for student: Student) async -> Int {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return 0 }
        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else { return 0 }
        let path = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))/\(student.folderName)"
        guard let items = try? await activeProvider.listContents(at: path) else { return 0 }
        return items.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }.count
    }

    public func ensureStudentFolders(students: [Student]) async throws -> [Student] {
        return try await autoSyncAllStudents(students: students)
    }

    /// Vérifie si le dossier d'un élève existe physiquement
    public func checkStudentFolderExists(for student: Student) async -> Bool {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return false }
        guard NetworkMonitor.shared.isOnline, !(activeProvider is LocalStorageProvider) else { return true }
        let path = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))/\(student.folderName)"
        return (try? await activeProvider.itemExists(at: path)) ?? false
    }

    // MARK: - Gestion des Scans dans `Evaluations/A corriger`

    public struct ScanItem: Identifiable, Hashable, Sendable {
        public var id: String { path }
        public var name: String
        public var path: String
        public var isCorrected: Bool

        /// URL locale du fichier PDF
        public var fileURL: URL {
            URL(fileURLWithPath: path)
        }

        /// Nom de fichier brut sans préfixe d'état (ex: "CORRIGE_DS1.pdf" -> "DS1.pdf")
        public var rawFileName: String {
            if name.hasPrefix("CORRIGE_") {
                return String(name.dropFirst("CORRIGE_".count))
            } else if name.hasPrefix("Finished_") {
                return String(name.dropFirst("Finished_".count))
            }
            return name
        }

        /// Titre lisible affiché à l'enseignant (sans préfixe CORRIGE_ ni extension .pdf pour économiser l'espace)
        public var cleanTitle: String {
            var title = rawFileName
            if title.lowercased().hasSuffix(".pdf") {
                title = String(title.dropLast(4))
            }
            return title
        }
    }

    /// Liste immédiatement tous les fichiers PDF en cache local de manière synchrone (0 ms, disponible dès l'init de la vue)
    public func listLocalScansSync() -> [ScanItem] {
        let folder = "Evaluations/A corriger"
        let folderURL = localURL(for: folder)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { fileURL in
                let name = fileURL.lastPathComponent
                let isCorr = name.hasPrefix("CORRIGE_") || name.hasPrefix("Finished_")
                return ScanItem(name: name, path: "\(folder)/\(name)", isCorrected: isCorr)
            }
            .sorted { $0.name < $1.name }
    }

    /// Liste immédiatement tous les fichiers PDF en cache local (0 ms de latence, zéro blocage réseau).
    public func listLocalScans() async throws -> [ScanItem] {
        try? await localCacheProvider.createDirectory(at: "Evaluations/A corriger")
        let providerToUse: StorageProvider = (activeProvider is LocalStorageProvider) ? activeProvider : localCacheProvider
        let items = (try? await providerToUse.listContents(at: "Evaluations/A corriger")) ?? []
        return items
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
            .map { item in
                let isCorr = item.name.hasPrefix("CORRIGE_") || item.name.hasPrefix("Finished_")
                return ScanItem(name: item.name, path: item.path, isCorrected: isCorr)
            }
            .sorted { $0.name < $1.name }
    }

    /// Liste tous les fichiers PDF en attente ou corrigés dans `Evaluations/A corriger`
    /// (Interroge le cache local sécurisé, et synchronise au préalable avec le Cloud si en ligne).
    public func listScans() async throws -> [ScanItem] {
        try? await localCacheProvider.createDirectory(at: "Evaluations/A corriger")

        if NetworkMonitor.shared.isOnline && !(activeProvider is LocalStorageProvider) {
            // Lancer la synchronisation déterministe en arrière-plan
            await OfflineSyncEngine.shared.performSync(storageManager: self, isOnline: true)
        }

        let providerToUse: StorageProvider = (activeProvider is LocalStorageProvider) ? activeProvider : localCacheProvider
        let items = (try? await providerToUse.listContents(at: "Evaluations/A corriger")) ?? []
        return items
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
            .map { item in
                let isCorr = item.name.hasPrefix("CORRIGE_") || item.name.hasPrefix("Finished_")
                return ScanItem(name: item.name, path: item.path, isCorrected: isCorr)
            }
            .sorted { $0.name < $1.name }
    }

    /// Marque un scan comme "CORRIGÉ" en préfixant son nom par `CORRIGE_`
    public func markScan(scan: ScanItem, asCorrected: Bool) async throws {
        let currentDir = "Evaluations/A corriger"
        let newName: String
        if asCorrected {
            newName = scan.name.hasPrefix("CORRIGE_") ? scan.name : "CORRIGE_\(scan.name)"
        } else {
            newName = scan.rawFileName
        }
        guard newName != scan.name else { return }

        // 1. Renommer dans le cache local
        try? await localCacheProvider.moveItem(from: "\(currentDir)/\(scan.name)", to: "\(currentDir)/\(newName)")

        // 2. Si en ligne, renommer également dans le Cloud et déclencher le nettoyage Règle 3
        if NetworkMonitor.shared.isOnline && !(activeProvider is LocalStorageProvider) {
            try? await activeProvider.moveItem(from: "\(currentDir)/\(scan.name)", to: "\(currentDir)/\(newName)")
            Task.detached {
                await OfflineSyncEngine.shared.performSync(storageManager: self, isOnline: true)
            }
        }
    }

    // MARK: - Gestion des Évaluations passées (`Evaluations/Backup`)

    public struct ExistingBackup: Identifiable, Hashable, Sendable {
        public var id: String { fileName }
        public var fileName: String
        public var path: String
        public var date: Date?
        public var className: String
        public var evaluationTitle: String
    }

    /// Liste les évaluations déjà distribuées archivées dans `Evaluations/Backup`
    public func listExistingBackups() async throws -> [ExistingBackup] {
        try await ensureSourceFolderStructure()
        let items = try await activeProvider.listContents(at: "Evaluations/Backup")
        return items
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
            .compactMap { item in
                guard let parsed = Evaluation.parseBackupFileName(item.name) else { return nil }
                return ExistingBackup(
                    fileName: item.name,
                    path: item.path,
                    date: parsed.date,
                    className: parsed.className,
                    evaluationTitle: parsed.title
                )
            }
            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }

    // MARK: - Détection des élèves ayant déjà une évaluation

    /// Vérifie si un élève a déjà un PDF d'évaluation dans son dossier
    public func studentHasEvaluation(student: Student, evaluationTitle: String) async -> Bool {
        let classDir = Student.sanitizeFolderName(student.classe)
        let studentDir = student.folderName
        let path = "Evaluations/Eleves/\(classDir)/\(studentDir)"
        guard let files = try? await activeProvider.listContents(at: path) else { return false }
        let cleanTitle = Student.sanitizeFolderName(evaluationTitle).lowercased()
        return files.contains { file in
            let cleanFileName = file.name.lowercased()
            return cleanFileName.contains(cleanTitle) && cleanFileName.hasSuffix(".pdf")
        }
    }
}
