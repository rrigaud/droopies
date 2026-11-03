//
//  SplashSetupView.swift
//  Dropies
//
//  Écran de démarrage et assistant de configuration initiale (Splash & Cloud Setup).
//  Vérifie les 3 piliers essentiels :
//  1. Connexion au compte Cloud (Dropbox)
//  2. Sélection et validation du dossier Source (/Droopy)
//  3. Chargement de l'environnement (eleves.json, classes, scans et backups)
//

import SwiftUI

public struct SplashSetupView: View {
    @Bindable public var appState: AppState
    public var onFinish: () -> Void

    @State private var dropboxToken: String = ""
    @State private var rootFolder: String = "/Droopy"

    // États de progression des 3 étapes
    @State private var isCheckingCloud: Bool = false
    @State private var cloudStatusMessage: String? = nil
    @State private var isCloudConnected: Bool = false

    @State private var isCheckingFolder: Bool = false
    @State private var folderStatusMessage: String? = nil
    @State private var isFolderValidated: Bool = false

    @State private var isLoadingData: Bool = false
    @State private var dataStatusMessage: String? = nil
    @State private var isDataLoaded: Bool = false

    @State private var errorMessage: String? = nil
    @State private var showTokenHelp: Bool = false

    public init(appState: AppState, onFinish: @escaping () -> Void) {
        self.appState = appState
        self.onFinish = onFinish
    }

    private var canEnterApp: Bool {
        isCloudConnected && isFolderValidated && isDataLoaded
    }

    public var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 28) {
                    // MARK: - En-tête avec Mascotte Officielle Droopy v5
                    VStack(spacing: 12) {
                        DropiesMascotView(size: 88, hasShadow: true, isAnimated: true)
                            .padding(.top, 16)

                        VStack(spacing: 4) {
                            Text("Dropies")
                                .font(.system(size: 32, weight: .bold, design: .rounded))

                            Text("Studio Numérique Enseignant • iPadOS & macOS")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // MARK: - Carte Principale de Configuration & Diagnostic
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Vérification de l'environnement")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // --- ÉTAPE 1 : Compte Cloud Dropbox ---
                        step1CloudAccountCard

                        // --- ÉTAPE 2 : Dossier Source Dropbox ---
                        if isCloudConnected {
                            step2SourceFolderCard
                        }

                        // --- ÉTAPE 3 : Chargement des Données ---
                        if isFolderValidated {
                            step3DataLoadingCard
                        }

                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 22, strokeOpacity: 0.45)
                    .frame(maxWidth: 580)

                    // MARK: - Bouton d'entrée dans l'application
                    VStack(spacing: 12) {
                        if canEnterApp {
                            Button {
                                onFinish()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Accéder à Dropies")
                                        .font(.headline.bold())
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                }
                            }
                            .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen))
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button {
                            // Secours : Mode local hors-ligne
                            appState.storageManager.setProvider(LocalStorageProvider())
                            Task {
                                await appState.loadInitialData()
                                onFinish()
                            }
                        } label: {
                            Text("Continuer en mode local hors-ligne (Démo)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            await autoDetectExistingConnection()
        }
    }

    // MARK: - Étape 1 : Compte Cloud Dropbox

    private var step1CloudAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isCloudConnected ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: isCloudConnected ? "checkmark" : "shippingbox.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isCloudConnected ? .green : .blue)
                }

                Text("1. Compte Cloud (Dropbox)")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingCloud {
                    ProgressView().scaleEffect(0.8)
                } else if isCloudConnected {
                    BadgeView("Connecté", style: .success)
                } else {
                    BadgeView("À configurer", style: .warning)
                }
            }

            if isCloudConnected {
                Text(cloudStatusMessage ?? "Compte Dropbox actif")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 36)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Collez votre Jeton d'accès Dropbox (Token Développeur ou OAuth) :")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        SecureField("sl.u...", text: $dropboxToken)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            connectWithDropboxToken()
                        } label: {
                            Text("Connecter")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
                        .disabled(dropboxToken.trimmingCharacters(in: .whitespaces).isEmpty || isCheckingCloud)
                    }

                    Button {
                        withAnimation { showTokenHelp.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                            Text("Comment obtenir mon token Dropbox en 1 minute ?")
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    if showTokenHelp {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Rendez-vous sur dropbox.com/developers/apps")
                            Text("2. Cliquez sur votre application Droopy (Scoped App)")
                            Text("3. Onglet 'Settings' ➔ Bouton 'Generate' sous Generated access token")
                            Text("4. Copiez et collez la clé ici.")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 36)
            }
        }
    }

    // MARK: - Étape 2 : Dossier Source

    private var step2SourceFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isFolderValidated ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: isFolderValidated ? "checkmark" : "folder.badge.gearshape")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFolderValidated ? .green : .orange)
                }

                Text("2. Dossier Source Cloud")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingFolder {
                    ProgressView().scaleEffect(0.8)
                } else if isFolderValidated {
                    BadgeView("Validé", style: .success)
                }
            }

            HStack {
                TextField("Ex: /Droopy", text: $rootFolder)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Button {
                    Task { await validateRootFolder() }
                } label: {
                    Text("Valider")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }
            .padding(.leading, 36)

            if let msg = folderStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(isFolderValidated ? .green : .secondary)
                    .padding(.leading, 36)
            }
        }
    }

    // MARK: - Étape 3 : Chargement des Données

    private var step3DataLoadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isDataLoaded ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: isDataLoaded ? "checkmark" : "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isDataLoaded ? .green : .purple)
                }

                Text("3. Chargement de l'environnement")
                    .font(.subheadline.bold())

                Spacer()

                if isLoadingData {
                    ProgressView().scaleEffect(0.8)
                } else if isDataLoaded {
                    BadgeView("Synchronisé", style: .success)
                }
            }

            if let msg = dataStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 36)
            }
        }
    }

    // MARK: - Logique d'initialisation & vérification

    private func autoDetectExistingConnection() async {
        isCheckingCloud = true
        defer { isCheckingCloud = false }

        let provider = DropboxStorageProvider()
        if provider.isConnected {
            do {
                let info = try await provider.testConnection()
                await MainActor.run {
                    self.appState.storageManager.setProvider(provider)
                    self.isCloudConnected = true
                    self.cloudStatusMessage = "Connecté : \(info.name) (\(info.email))"
                    self.rootFolder = provider.rootFolderPath
                }
                await validateRootFolder()
            } catch {
                await MainActor.run {
                    self.isCloudConnected = false
                }
            }
        }
    }

    private func connectWithDropboxToken() {
        let cleanToken = dropboxToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        isCheckingCloud = true
        errorMessage = nil

        Task {
            let provider = DropboxStorageProvider(accessToken: cleanToken, rootFolderPath: rootFolder)
            provider.configure(accessToken: cleanToken, rootFolderPath: rootFolder)

            do {
                let info = try await provider.testConnection()
                await MainActor.run {
                    self.appState.storageManager.setProvider(provider)
                    self.isCloudConnected = true
                    self.cloudStatusMessage = "Connecté : \(info.name) (\(info.email))"
                    self.isCheckingCloud = false
                }
                await validateRootFolder()
            } catch {
                await MainActor.run {
                    self.isCheckingCloud = false
                    self.errorMessage = "Échec de connexion Dropbox : vérifiez votre jeton."
                }
            }
        }
    }

    private func validateRootFolder() async {
        isCheckingFolder = true
        defer { isCheckingFolder = false }

        let cleanRoot = rootFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider else { return }

        dropbox.configure(
            appKey: dropbox.appKey,
            refreshToken: dropbox.refreshToken,
            accessToken: dropbox.accessToken,
            rootFolderPath: cleanRoot
        )

        do {
            // Vérifier si le dossier existe, sinon le créer
            let exists = try await dropbox.itemExists(at: "")
            if !exists {
                try await dropbox.createDirectory(at: "")
            }

            // S'assurer que les sous-dossiers fondamentaux existent
            if try await !dropbox.itemExists(at: "Classes") {
                try? await dropbox.createDirectory(at: "Classes")
            }
            if try await !dropbox.itemExists(at: "Evaluations/A corriger") {
                try? await dropbox.createDirectory(at: "Evaluations/A corriger")
            }
            if try await !dropbox.itemExists(at: "Evaluations/Backup") {
                try? await dropbox.createDirectory(at: "Evaluations/Backup")
            }

            await MainActor.run {
                self.isFolderValidated = true
                self.folderStatusMessage = "Dossier racine '\(cleanRoot)' validé sur Dropbox"
            }
            await loadEnvironmentData()
        } catch {
            await MainActor.run {
                self.errorMessage = "Erreur dossier : \(error.localizedDescription)"
            }
        }
    }

    private func loadEnvironmentData() async {
        isLoadingData = true
        defer { isLoadingData = false }

        await appState.loadInitialData()

        await MainActor.run {
            self.isDataLoaded = true
            let studCount = self.appState.students.count
            let classCount = self.appState.classes.count
            self.dataStatusMessage = "\(studCount) élève(s) synchronisé(s) • \(classCount) classe(s) prête(s)"
        }
    }
}
