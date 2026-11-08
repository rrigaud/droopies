//
//  OfflineSyncEngine.swift
//  Droopies
//
//  Moteur de synchronisation intelligent et résilient (Mode Hors-Ligne + Cloud)
//  Applique les 3 règles déterministes convenues pour les copies d'évaluation :
//  1. Téléchargement Cloud ➔ iPad : Télécharge les nouveaux devoirs non encore présents
//     (ignore si déjà présent sous forme brute ou corrigée).
//  2. Envoi iPad ➔ Cloud : N'envoie que les devoirs modifiés ou marqués CORRIGE_.
//  3. Règle de Nettoyage : Dès qu'une version `CORRIGE_X.pdf` existe, supprime `X.pdf` (sur Cloud et en local).
//

import Foundation
import Observation

/// État de synchronisation granulaire d'un fichier PDF d'évaluation
public enum ScanSyncStatus: Equatable, Sendable {
    case verifying      // Vérification Cloud Dropbox en cours
    case synced         // 🟢 Synchronisé et à jour avec Dropbox
    case offline        // 🟡 Mode hors-ligne / Cache local disponible
    case downloading    // 🟣 Téléchargement d'une nouvelle version Cloud
    case uploading      // 🔵 Envoi d'annotations ou renommage vers Dropbox
}

@Observable
public final class OfflineSyncEngine: @unchecked Sendable {
    public static let shared = OfflineSyncEngine()

    public var isSyncing: Bool = false
    public var lastSyncDate: Date? = nil
    public var lastSyncMessage: String? = nil
    public var pendingUploadCount: Int = 0
    public var fileSyncStatuses: [String: ScanSyncStatus] = [:]

    private init() {}

    /// Exécute un cycle complet de synchronisation bidirectionnelle des copies et de la configuration
    public func performSync(storageManager: StorageManager, isOnline: Bool) async {
        guard isOnline else {
            print("[OfflineSyncEngine] Appareil hors-ligne, synchronisation Cloud ignorée.")
            return
        }

        guard !isSyncing else {
            print("[OfflineSyncEngine] Synchronisation déjà en cours...")
            return
        }

        isSyncing = true
        lastSyncMessage = "Synchronisation des devoirs..."
        defer {
            isSyncing = false
        }

        do {
            // S'assurer de la présence des dossiers en local et dans le Cloud
            try? await storageManager.ensureSourceFolderStructure()
            try? await storageManager.localCacheProvider.createDirectory(at: "Evaluations/A corriger")
            try? await storageManager.localCacheProvider.createDirectory(at: "Configuration")

            // MARK: - 1. Miroir de la Configuration (eleves.json, settings.json, icône)
            await syncConfigurationFiles(storageManager: storageManager)

            // MARK: - 2. Synchronisation des Copies (Evaluations/A corriger)
            await syncEvaluationCopies(storageManager: storageManager)

            await MainActor.run {
                self.lastSyncDate = Date()
                self.lastSyncMessage = "Synchronisé avec le Cloud"
            }
        } catch {
            print("[OfflineSyncEngine] Erreur cycle de synchronisation : \(error)")
            await MainActor.run {
                self.lastSyncMessage = "Erreur synchro : \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 1. Miroir des fichiers de Configuration

    private func syncConfigurationFiles(storageManager: StorageManager) async {
        let configFiles = [
            "Configuration/eleves.json",
            "Configuration/settings.json",
            "Configuration/Icone Portail.png"
        ]

        for path in configFiles {
            // Si le fichier existe sur le Cloud, rafraîchir la copie locale dans le cache
            if let cloudData = try? await storageManager.activeProvider.readData(at: path) {
                try? await storageManager.localCacheProvider.writeData(cloudData, to: path)
            } else if let localData = try? await storageManager.localCacheProvider.readData(at: path) {
                // Si le fichier existe en local mais pas sur le Cloud, le pousser vers le Cloud
                try? await storageManager.activeProvider.writeData(localData, to: path)
            }
        }
    }

    // MARK: - 2. Synchronisation Déterministe des Copies (Evaluations/A corriger)

    private func syncEvaluationCopies(storageManager: StorageManager) async {
        let folder = "Evaluations/A corriger"

        // Récupérer le contenu du Cloud et du Cache local
        let cloudItems = (try? await storageManager.activeProvider.listContents(at: folder)) ?? []
        let cloudFiles = cloudItems.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }

        let localItems = (try? await storageManager.localCacheProvider.listContents(at: folder)) ?? []
        let localFiles = localItems.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }

        let localNames = Set(localFiles.map { $0.name })
        let cloudNames = Set(cloudFiles.map { $0.name })

        // ─────────────────────────────────────────────────────────────
        // RÈGLE 1 : Téléchargement Cloud ➔ iPad
        // Ne télécharger X.pdf que si ni X.pdf ni CORRIGE_X.pdf n'existe en local
        // ─────────────────────────────────────────────────────────────
        for cloudFile in cloudFiles {
            let baseName = cloudFile.name.hasPrefix("CORRIGE_")
                ? String(cloudFile.name.dropFirst("CORRIGE_".count))
                : cloudFile.name
            let correctedName = "CORRIGE_\(baseName)"

            let alreadyInCache = localNames.contains(cloudFile.name) || localNames.contains(correctedName)
            let matchingLocal = localFiles.first(where: { $0.name == cloudFile.name })
            let isCloudNewer: Bool
            if let localDate = matchingLocal?.modifiedDate, let cloudDate = cloudFile.modifiedDate {
                isCloudNewer = cloudDate > localDate.addingTimeInterval(2)
            } else {
                isCloudNewer = false
            }

            if !alreadyInCache || isCloudNewer {
                print("[OfflineSyncEngine] ⬇️ Téléchargement du devoir en cache : \(cloudFile.name) (nouveau ou plus récent sur Dropbox)")
                await MainActor.run {
                    self.fileSyncStatuses[cloudFile.name] = .downloading
                }
                let cloudPath = "\(folder)/\(cloudFile.name)"
                if let data = try? await storageManager.activeProvider.readData(at: cloudPath) {
                    try? await storageManager.localCacheProvider.writeData(data, to: cloudPath)
                }
                await MainActor.run {
                    self.fileSyncStatuses[cloudFile.name] = .synced
                }
            }
        }

        // Rafraîchir l'inventaire local après téléchargements
        let updatedLocalItems = (try? await storageManager.localCacheProvider.listContents(at: folder)) ?? []
        let updatedLocalFiles = updatedLocalItems.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }

        // ─────────────────────────────────────────────────────────────
        // RÈGLE 2 : Envoi iPad ➔ Cloud
        // Uploader les fichiers locaux nouveaux ou modifiés plus récemment
        // ─────────────────────────────────────────────────────────────
        for localFile in updatedLocalFiles {
            let localPath = "\(folder)/\(localFile.name)"
            let matchingCloud = cloudFiles.first(where: { $0.name == localFile.name })

            var shouldUpload = false
            if matchingCloud == nil {
                // Le fichier n'existe pas sur le Cloud (ex: nouveau CORRIGE_... créé hors-ligne)
                shouldUpload = true
            } else if let localDate = localFile.modifiedDate, let cloudDate = matchingCloud?.modifiedDate {
                // Si la version locale a été modifiée plus récemment (stylet)
                if localDate > cloudDate.addingTimeInterval(2) {
                    shouldUpload = true
                }
            }

            if shouldUpload {
                print("[OfflineSyncEngine] ⬆️ Upload du devoir corrigé/annoté vers Dropbox : \(localFile.name)")
                await MainActor.run {
                    self.fileSyncStatuses[localFile.name] = .uploading
                }
                if let data = try? await storageManager.localCacheProvider.readData(at: localPath) {
                    try? await storageManager.activeProvider.writeData(data, to: localPath)
                }
                await MainActor.run {
                    self.fileSyncStatuses[localFile.name] = .synced
                }
            }
        }

        // ─────────────────────────────────────────────────────────────
        // RÈGLE 3 : Nettoyage Déterministe (Votre règle d'or)
        // Dès que CORRIGE_X.pdf existe, supprimer l'ancien X.pdf non corrigé
        // ─────────────────────────────────────────────────────────────
        await performRule3Cleanup(storageManager: storageManager, folder: folder)

        // Marquer tous les fichiers confirmés comme synchronisés
        await MainActor.run {
            for file in updatedLocalFiles {
                if self.fileSyncStatuses[file.name] == nil || self.fileSyncStatuses[file.name] == .verifying {
                    self.fileSyncStatuses[file.name] = .synced
                }
            }
            for file in cloudFiles {
                if self.fileSyncStatuses[file.name] == nil || self.fileSyncStatuses[file.name] == .verifying {
                    self.fileSyncStatuses[file.name] = .synced
                }
            }
        }
    }

    /// Règle 3 : Supprime tout X.pdf brut si CORRIGE_X.pdf existe dans le même dossier
    private func performRule3Cleanup(storageManager: StorageManager, folder: String) async {
        // Nettoyage sur le Cloud
        let cloudItems = (try? await storageManager.activeProvider.listContents(at: folder)) ?? []
        let cloudFiles = cloudItems.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
        let cloudNames = Set(cloudFiles.map { $0.name })

        for file in cloudFiles where file.name.hasPrefix("CORRIGE_") {
            let rawName = String(file.name.dropFirst("CORRIGE_".count))
            if cloudNames.contains(rawName) {
                print("[OfflineSyncEngine] 🧹 Règle 3 Cloud : Suppression de l'ancienne version brute '\(rawName)' remplacée par '\(file.name)'")
                try? await storageManager.activeProvider.deleteItem(at: "\(folder)/\(rawName)")
            }
        }

        // Nettoyage en Local (iPad Cache)
        let localItems = (try? await storageManager.localCacheProvider.listContents(at: folder)) ?? []
        let localFiles = localItems.filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
        let localNames = Set(localFiles.map { $0.name })

        for file in localFiles where file.name.hasPrefix("CORRIGE_") {
            let rawName = String(file.name.dropFirst("CORRIGE_".count))
            if localNames.contains(rawName) {
                print("[OfflineSyncEngine] 🧹 Règle 3 Local : Suppression de l'ancienne version brute '\(rawName)' remplacée par '\(file.name)'")
                try? await storageManager.localCacheProvider.deleteItem(at: "\(folder)/\(rawName)")
            }
        }
    }
}
