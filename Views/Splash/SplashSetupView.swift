//
//  SplashSetupView.swift
//  Dropies
//
//  Écran de démarrage et assistant de configuration initiale (Splash & Cloud Setup).
//  Permet de :
//  1. Choisir son Cloud (Dropbox, Nextcloud, OneDrive, Google Drive)
//  2. Connecter son compte Cloud
//  3. Sélectionner ou créer son dossier Source librement via l'explorateur
//  4. Charger et synchroniser l'environnement scolaire
//

import SwiftUI
import AuthenticationServices

public struct SplashSetupView: View {
    @Bindable public var appState: AppState
    public var onFinish: () -> Void

    @State private var selectedProviderType: AppSettings.StorageProviderType = .dropbox
    @State private var rootFolder: String = ""

    // Boîte de dialogue de sélection du dossier
    @State private var showFolderPicker: Bool = false

    // États de connexion Cloud
    @State private var isConnectingCloud: Bool = false
    @State private var isCheckingCloud: Bool = false
    @State private var cloudStatusMessage: String? = nil
    @State private var isCloudConnected: Bool = false
    @State private var connectedUserDisplayName: String? = nil
    @State private var connectedUserEmail: String? = nil

    // Réglages avancés (App Key personnalisée)
    @State private var showAdvancedAppKey: Bool = false
    @State private var customAppKey: String = ""

    @State private var isCheckingFolder: Bool = false
    @State private var folderStatusMessage: String? = nil
    @State private var isFolderValidated: Bool = false

    @State private var isLoadingData: Bool = false
    @State private var dataStatusMessage: String? = nil
    @State private var isDataLoaded: Bool = false

    @State private var errorMessage: String? = nil

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
                VStack(spacing: 24) {
                    // MARK: - En-tête avec Mascotte Officielle Droopy v5
                    VStack(spacing: 12) {
                        DropiesMascotView(size: 84, hasShadow: true, isAnimated: true)
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
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Choix du Cloud
                        cloudProviderSelectorSection

                        Divider()

                        // 2. Connexion au compte Cloud sélectionné
                        cloudAccountConnectionSection

                        // 3. Choix du dossier Source (Explorateur de dossiers)
                        if isCloudConnected {
                            Divider()
                            sourceFolderPickerSection
                        }

                        // 4. Chargement des données
                        if isFolderValidated {
                            Divider()
                            dataLoadingStatusSection
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
                    .frame(maxWidth: 600)

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
        .sheet(isPresented: $showFolderPicker) {
            CloudFolderPickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: rootFolder
            ) { chosenPath in
                self.rootFolder = chosenPath
                Task {
                    await applyAndValidateSourceFolder(chosenPath)
                }
            }
        }
        .task {
            await autoDetectExistingConnection()
        }
    }

    // MARK: - Section 1 : Sélecteur de Cloud

    private var cloudProviderSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Sélectionnez votre Cloud de stockage :")
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                cloudOptionChip(type: .dropbox, label: "Dropbox", color: Color(red: 0.0, green: 0.38, blue: 1.0))
                cloudOptionChip(type: .nextcloud, label: "Nextcloud", color: Color(red: 0.0, green: 0.51, blue: 0.79))
                cloudOptionChip(type: .oneDrive, label: "OneDrive", color: Color(red: 0.0, green: 0.47, blue: 0.83))
                cloudOptionChip(type: .googleDrive, label: "Google Drive", color: Color(red: 0.0, green: 0.67, blue: 0.28))
            }
        }
    }

    @ViewBuilder
    private func cloudOptionChip(type: AppSettings.StorageProviderType, label: String, color: Color) -> some View {
        let isSelected = selectedProviderType == type
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProviderType = type
                UserDefaults.standard.set(type.rawValue, forKey: "dropies_selected_provider")
                if type != .dropbox {
                    isCloudConnected = false
                    cloudStatusMessage = "\(label) sera disponible très prochainement. Veuillez utiliser Dropbox pour le moment."
                } else {
                    Task { await autoDetectExistingConnection() }
                }
            }
        } label: {
            VStack(spacing: 8) {
                CloudBrandIconView(type: type, size: 28, isSelected: isSelected)
                    .frame(height: 28)

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: color.opacity(0.4), radius: 8, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 2 : Connexion Compte

    private var cloudAccountConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isCloudConnected ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 32, height: 32)
                    if isCloudConnected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        CloudBrandIconView(type: selectedProviderType, size: 18)
                    }
                }

                Text("2. Connexion au compte \(selectedProviderType.displayName)")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingCloud || isConnectingCloud {
                    ProgressView().scaleEffect(0.8)
                } else if isCloudConnected {
                    BadgeView("Connecté", style: .success)
                } else {
                    BadgeView("Non connecté", style: .warning)
                }
            }

            if selectedProviderType != .dropbox {
                Text("\(selectedProviderType.displayName) sera activé dans la prochaine mise à jour.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 36)
            } else if isCloudConnected {
                // Compte connecté : affichage clair de l'enseignant et bouton de déconnexion
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title2)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedUserDisplayName ?? "Enseignant Dropbox")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        Text(connectedUserEmail ?? "Compte actif et synchronisé")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Déconnecter") {
                        disconnectDropbox()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
                .padding(.leading, 36)
            } else {
                // NON CONNECTÉ : Un seul bouton d'action principal en 1 clic
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connectez votre compte Dropbox en 1 clic pour activer la synchronisation de vos devoirs et partages :")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        connectWithDropbox1Click()
                    } label: {
                        HStack(spacing: 8) {
                            if isConnectingCloud {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                Text("Connexion en cours...")
                                    .font(.headline.bold())
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Se connecter avec Dropbox")
                                    .font(.headline.bold())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))
                    .disabled(isConnectingCloud || isCheckingCloud)

                    // Option avancée dépliable : App Key personnalisée si l'enseignant le souhaite
                    DisclosureGroup(isExpanded: $showAdvancedAppKey) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Par défaut, Dropies utilise l'App Key officielle intégrée. Vous pouvez renseigner votre propre clé de Scoped App créée sur la console Dropbox :")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("App Key personnalisée (ex: mjjyt774vxkg22i)", text: $customAppKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))

                                if !customAppKey.isEmpty {
                                    Button("Effacer") {
                                        customAppKey = ""
                                        DropboxOAuthManager.shared.effectiveAppKey = ""
                                    }
                                    .font(.caption2)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Options avancées (App Key personnalisée)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 36)
            }
        }
    }

    // MARK: - Section 3 : Sélecteur de Dossier Source

    private var sourceFolderPickerSection: some View {
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

                Text("3. Dossier Source dans le Cloud")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingFolder {
                    ProgressView().scaleEffect(0.8)
                } else if isFolderValidated {
                    BadgeView("Validé", style: .success)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Choisissez librement le dossier qui contiendra vos évaluations et vos élèves :")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if rootFolder.isEmpty {
                        Text("Aucun dossier sélectionné")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(rootFolder)
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label(rootFolder.isEmpty ? "Parcourir le Cloud..." : "Changer de dossier...", systemImage: "folder.badge.plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let msg = folderStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(isFolderValidated ? .green : .secondary)
                }
            }
            .padding(.leading, 36)
        }
    }

    // MARK: - Section 4 : Chargement des données

    private var dataLoadingStatusSection: some View {
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

                Text("4. Chargement de l'environnement")
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

    // MARK: - Logique d'initialisation & actions

    private func autoDetectExistingConnection() async {
        isCheckingCloud = true
        defer { isCheckingCloud = false }

        // Récupérer le type de cloud mémorisé
        if let savedType = UserDefaults.standard.string(forKey: "dropies_selected_provider"),
           let prov = AppSettings.StorageProviderType(rawValue: savedType) {
            self.selectedProviderType = prov
        }

        let provider = DropboxStorageProvider()
        if provider.isConnected {
            do {
                let info = try await provider.testConnection()
                await MainActor.run {
                    self.appState.storageManager.setProvider(provider)
                    self.isCloudConnected = true
                    self.connectedUserDisplayName = info.name
                    self.connectedUserEmail = info.email
                    self.cloudStatusMessage = "\(info.name) (\(info.email))"
                    self.rootFolder = provider.rootFolderPath
                }
                if !provider.rootFolderPath.isEmpty && provider.rootFolderPath != "/Droopy" {
                    await applyAndValidateSourceFolder(provider.rootFolderPath)
                }
            } catch {
                await MainActor.run {
                    self.isCloudConnected = false
                }
            }
        }
    }

    private func connectWithDropbox1Click() {
        isConnectingCloud = true
        errorMessage = nil

        Task {
            do {
                let keyToUse = customAppKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customAppKey
                let session = try await DropboxOAuthManager.shared.signInWithDropbox(customAppKey: keyToUse)

                let provider = DropboxStorageProvider()
                provider.configure(session: session, rootFolderPath: rootFolder)

                await MainActor.run {
                    self.appState.storageManager.setProvider(provider)
                    self.isCloudConnected = true
                    self.connectedUserDisplayName = session.displayName
                    self.connectedUserEmail = session.email
                    self.cloudStatusMessage = "\(session.displayName) (\(session.email))"
                    self.isConnectingCloud = false
                }

                if !rootFolder.isEmpty && rootFolder != "/Droopy" {
                    await applyAndValidateSourceFolder(rootFolder)
                } else {
                    // Ouvrir automatiquement l'explorateur de dossiers
                    await MainActor.run {
                        self.showFolderPicker = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.isConnectingCloud = false
                    // Si l'utilisateur a annulé, ne pas afficher d'erreur anxiogène
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.errorMessage = "Échec de connexion Dropbox : \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func disconnectDropbox() {
        Task {
            let provider = DropboxStorageProvider()
            try? await provider.disconnect()
            await MainActor.run {
                self.isCloudConnected = false
                self.connectedUserDisplayName = nil
                self.connectedUserEmail = nil
                self.cloudStatusMessage = nil
                self.isFolderValidated = false
                self.isDataLoaded = false
            }
        }
    }

    private func applyAndValidateSourceFolder(_ folderPath: String) async {
        isCheckingFolder = true
        defer { isCheckingFolder = false }

        let cleanPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider else { return }

        dropbox.configure(
            appKey: dropbox.appKey,
            refreshToken: dropbox.refreshToken,
            accessToken: dropbox.accessToken,
            rootFolderPath: cleanPath
        )

        do {
            // S'assurer que les 4 dossiers obligatoires existent dans le dossier source
            try await appState.storageManager.ensureSourceFolderStructure()

            await MainActor.run {
                self.rootFolder = cleanPath
                self.isFolderValidated = true
                self.folderStatusMessage = "Dossier Source '\(cleanPath)' configuré avec succès"
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
