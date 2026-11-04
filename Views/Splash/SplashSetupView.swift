//
//  SplashSetupView.swift
//  Droopies
//
//  Écran de démarrage et assistant de vérification Cloud (Splash & Cloud Setup).
//  Fonctionne 100 % en Cloud (Dropbox, OneDrive, Nextcloud, Google Drive) sans aucun mode local.
//  Vérifie le compte, configure le dossier Source dans le Cloud,
//  et bascule automatiquement vers l'interface principale dès que tout est prêt.
//

import SwiftUI
import AuthenticationServices

public struct SplashSetupView: View {
    @Bindable public var appState: AppState
    public var onFinish: () -> Void

    @State private var selectedProviderType: AppSettings.StorageProviderType = .dropbox
    @State private var rootFolder: String = ""

    // Boîte de dialogue de sélection du dossier Dropbox dans le Cloud
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
    @State private var isDataLoaded: Bool = false

    @State private var errorMessage: String? = nil

    public init(appState: AppState, onFinish: @escaping () -> Void) {
        self.appState = appState
        self.onFinish = onFinish
    }

    /// Calcul de progression fluide (0.0 -> 1.0)
    private var progressValue: Double {
        if isDataLoaded && isFolderValidated && isCloudConnected {
            return 1.0
        } else if isFolderValidated && isCloudConnected {
            return 0.75
        } else if isCloudConnected {
            return 0.50
        } else {
            return 0.25
        }
    }

    private var progressLabel: String {
        if isDataLoaded && isFolderValidated && isCloudConnected {
            return "Environnement prêt • Ouverture de Droopies..."
        } else if isLoadingData {
            return "Chargement de vos évaluations et copies..."
        } else if isCheckingFolder {
            return "Vérification de l'arborescence du dossier Source dans votre Cloud..."
        } else if isFolderValidated {
            return "Dossier Source prêt dans votre Cloud"
        } else if isConnectingCloud || isCheckingCloud {
            return "Connexion sécurisée à votre compte Cloud..."
        } else if isCloudConnected {
            return "Compte connecté • En attente du dossier Source"
        } else {
            return "Veuillez connecter votre compte Cloud pour continuer"
        }
    }

    public var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Barre de progression native supérieure
                    VStack(spacing: 8) {
                        ProgressView(value: progressValue, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                            .frame(maxWidth: 460)

                        HStack {
                            Text(progressLabel)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(Int(progressValue * 100)) %")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                        .frame(maxWidth: 460)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                    // MARK: - En-tête avec Mascotte Officielle Droopy
                    VStack(spacing: 10) {
                        DroopiesMascotView(size: 80, hasShadow: true, isAnimated: true)

                        VStack(spacing: 4) {
                            Text("Droopies")
                                .font(.system(size: 30, weight: .bold, design: .rounded))

                            Text("Studio Numérique Enseignant • 100% Cloud")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // MARK: - Carte Principale de Configuration Cloud
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Choix du service Cloud
                        cloudProviderSelectorSection

                        Divider()

                        // 2. Connexion au compte Cloud sélectionné
                        cloudAccountConnectionSection

                        // 3. Choix du dossier Source dans l'arborescence Cloud
                        if isCloudConnected {
                            Divider()
                            sourceFolderPickerSection
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
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            let providerToUse: StorageProvider = (appState.storageManager.activeProvider as? DropboxStorageProvider) ?? DropboxStorageProvider()
            CloudFolderPickerSheet(
                provider: providerToUse,
                initialPath: ""
            ) { chosenPath in
                self.rootFolder = chosenPath
                UserDefaults.standard.set(chosenPath, forKey: "droopies_selected_folder")
                if let dropbox = providerToUse as? DropboxStorageProvider {
                    self.appState.storageManager.setProvider(dropbox)
                }
                Task {
                    await applyAndValidateSourceFolder(chosenPath)
                }
            }
        }
        .task {
            await autoDetectExistingConnection()
        }
    }

    // MARK: - Section 1 : Choix du Service Cloud

    private var cloudProviderSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Service Cloud :")
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
                UserDefaults.standard.set(type.rawValue, forKey: "droopies_selected_provider")
                if type == .dropbox {
                    Task { await autoDetectExistingConnection() }
                } else {
                    isCloudConnected = false
                    cloudStatusMessage = "\(label) sera activé très prochainement. Veuillez utiliser Dropbox pour le moment."
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
                // Compte connecté
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
                // Non connecté : 1-clic connexion
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connectez votre compte Dropbox en 1 clic pour gérer vos évaluations directement dans le Cloud :")
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
                            Text("Par défaut, Droopies utilise l'App Key officielle intégrée. Vous pouvez renseigner votre propre clé de Scoped App créée sur la console Dropbox :")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("App Key personnalisée (ex: cpb97d4akmmhn3j)", text: $customAppKey)
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

    // MARK: - Section 3 : Dossier Source dans l'Arborescence Cloud

    private var sourceFolderPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isFolderValidated ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: isFolderValidated ? "checkmark" : "folder.badge.gearshape")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFolderValidated ? .green : .orange)
                }

                Text("3. Dossier Source dans votre Cloud")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingFolder || isLoadingData {
                    ProgressView().scaleEffect(0.8)
                } else if isFolderValidated {
                    BadgeView("Configuré", style: .success)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if rootFolder.isEmpty {
                    Text("Choisissez le dossier où Droopies organisera vos évaluations dans Dropbox (ex: \(AppSettings.currentSchoolYear) ou un dossier de test) :")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 10) {
                        // Action 1-clic : Année scolaire en cours (Recommandé)
                        Button {
                            let targetYear = "/\(AppSettings.currentSchoolYear)"
                            Task {
                                await applyAndValidateSourceFolder(targetYear)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Créer le dossier de l'année scolaire : \(AppSettings.currentSchoolYear)")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))

                        // Action 2 : Parcourir / Choisir un autre dossier (dossier de test, etc.)
                        Button {
                            showFolderPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Parcourir ou choisir un autre dossier (Dossier Test, etc.)...")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundColor(.blue)
                                Text(URL(fileURLWithPath: rootFolder).lastPathComponent.isEmpty ? "Racine Dropbox" : URL(fileURLWithPath: rootFolder).lastPathComponent)
                                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Spacer()

                            Button {
                                showFolderPicker = true
                            } label: {
                                Label("Modifier", systemImage: "shippingbox.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Chemin Cloud : \(rootFolder.isEmpty ? "/" : rootFolder)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let msg = folderStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(isFolderValidated ? .green : .secondary)
                    }
                }
            }
            .padding(.leading, 36)
        }
    }

    // MARK: - Logique d'initialisation & actions

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
                    self.connectedUserDisplayName = info.name
                    self.connectedUserEmail = info.email
                    self.cloudStatusMessage = "\(info.name) (\(info.email))"
                    self.rootFolder = provider.rootFolderPath
                }

                // Si un dossier était déjà mémorisé, on le vérifie et on bascule directement !
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

                    // Si aucun dossier n'est configuré, ouvrir directement l'explorateur modal Dropbox
                    if self.rootFolder.isEmpty {
                        self.showFolderPicker = true
                    }
                }

                if !rootFolder.isEmpty {
                    await applyAndValidateSourceFolder(rootFolder)
                }
            } catch {
                await MainActor.run {
                    self.isConnectingCloud = false
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
                self.rootFolder = ""
                UserDefaults.standard.removeObject(forKey: "droopies_selected_folder")
            }
        }
    }

    private func applyAndValidateSourceFolder(_ folderPath: String) async {
        isCheckingFolder = true
        defer { isCheckingFolder = false }

        let cleanPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            dropbox.configure(
                appKey: dropbox.appKey,
                refreshToken: dropbox.refreshToken,
                accessToken: dropbox.accessToken,
                rootFolderPath: cleanPath
            )
        }

        do {
            // S'assurer que les 4 dossiers obligatoires existent dans le dossier source sur Dropbox
            try await appState.storageManager.ensureSourceFolderStructure()

            await MainActor.run {
                self.rootFolder = cleanPath
                self.isFolderValidated = true
                let displayName = URL(fileURLWithPath: cleanPath).lastPathComponent.isEmpty ? "Racine" : URL(fileURLWithPath: cleanPath).lastPathComponent
                self.folderStatusMessage = "Dossier Cloud '\(displayName)' initialisé avec succès"
            }

            // Chargement des données d'élèves et réglages
            await loadEnvironmentData()

            // TRANSITION AUTOMATIQUE : Si tout est validé, on efface le SplashScreen et on ouvre l'app !
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s pour apprécier la barre à 100%
            await MainActor.run {
                self.onFinish()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Erreur configuration dossier Cloud : \(error.localizedDescription)"
            }
        }
    }

    private func loadEnvironmentData() async {
        isLoadingData = true
        defer { isLoadingData = false }

        await appState.loadInitialData()

        await MainActor.run {
            self.isDataLoaded = true
        }
    }
}
