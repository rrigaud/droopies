//
//  SplashSetupView.swift
//  Droopies
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
import UniformTypeIdentifiers

public struct SplashSetupView: View {
    @Bindable public var appState: AppState
    public var onFinish: () -> Void

    @State private var selectedProviderType: AppSettings.StorageProviderType = .dropbox
    @State private var rootFolder: String = ""

    // Boîte de dialogue de sélection du dossier Dropbox
    @State private var showFolderPicker: Bool = false

    // Sélecteur natif Apple (Fichiers / Finder)
    @State private var showNativeFolderPicker: Bool = false

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
                        DroopiesMascotView(size: 84, hasShadow: true, isAnimated: true)
                            .padding(.top, 16)

                        VStack(spacing: 4) {
                            Text("Droopies")
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

                        // 3. Choix du dossier Source (Sélecteur Natif Apple)
                        if isCloudConnected || selectedProviderType == .local {
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
                                    Text("Accéder à Droopies")
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
        .fileImporter(
            isPresented: $showNativeFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                guard selectedURL.startAccessingSecurityScopedResource() else {
                    self.errorMessage = "Permission d'accès au dossier refusée par Apple."
                    return
                }

                // Persistance du bookmark de sécurité Apple
                #if os(macOS)
                let creationOptions: URL.BookmarkCreationOptions = .withSecurityScope
                #else
                let creationOptions: URL.BookmarkCreationOptions = []
                #endif
                if let bookmarkData = try? selectedURL.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmarkData, forKey: "droopies_local_folder_bookmark")
                }

                let folderPath = selectedURL.path
                self.rootFolder = folderPath
                UserDefaults.standard.set(folderPath, forKey: "droopies_selected_folder")

                // Si l'utilisateur est connecté à Dropbox et que le dossier sélectionné est dans son Dropbox local,
                // on adapte la configuration Dropbox
                if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
                    if let range = folderPath.range(of: "/Dropbox") {
                        let sub = String(folderPath[range.upperBound...])
                        let remotePath = sub.isEmpty ? "" : (sub.hasPrefix("/") ? sub : "/\(sub)")
                        dropbox.configure(
                            appKey: dropbox.appKey,
                            refreshToken: dropbox.refreshToken,
                            accessToken: dropbox.accessToken,
                            rootFolderPath: remotePath
                        )
                    }
                }

                // Utiliser LocalStorageProvider pour un accès direct, rapide et fiable au dossier sélectionné
                let localProvider = LocalStorageProvider(rootURL: selectedURL)
                self.appState.storageManager.setProvider(localProvider)

                self.isCloudConnected = true
                self.connectedUserDisplayName = selectedURL.lastPathComponent
                self.connectedUserEmail = "Dossier synchronisé (Finder / Fichiers)"
                self.cloudStatusMessage = "\(selectedURL.lastPathComponent) (Accès système natif)"

                Task {
                    await applyAndValidateSourceFolder(folderPath)
                }

            case .failure(let error):
                self.errorMessage = "Impossible de sélectionner le dossier : \(error.localizedDescription)"
            }
        }
        .task {
            await autoDetectExistingConnection()
        }
    }

    // MARK: - Section 1 : Sélecteur de Mode de Stockage

    private var cloudProviderSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Sélectionnez votre mode de stockage :")
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                cloudOptionChip(type: .local, label: "Finder / Fichiers", color: Color(red: 0.15, green: 0.55, blue: 0.85))
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
                if type == .local || type == .dropbox {
                    Task { await autoDetectExistingConnection() }
                } else {
                    isCloudConnected = false
                    cloudStatusMessage = "\(label) sera disponible très prochainement. Veuillez utiliser Finder / Fichiers ou Dropbox pour le moment."
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

            if selectedProviderType == .local {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accès direct au stockage système (macOS Finder / iPadOS Fichiers). Vous pouvez choisir n'importe quel dossier : votre dossier Dropbox synchronisé, un dossier iCloud Drive, ou un dossier local.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !rootFolder.isEmpty && isFolderValidated {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Dossier configuré : \(URL(fileURLWithPath: rootFolder).lastPathComponent)")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.leading, 36)
            } else if selectedProviderType != .dropbox {
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

    // MARK: - Section 3 : Sélecteur de Dossier Source

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

                Text("3. Dossier Source (Copies & Évaluations)")
                    .font(.subheadline.bold())

                Spacer()

                if isCheckingFolder {
                    ProgressView().scaleEffect(0.8)
                } else if isFolderValidated {
                    BadgeView("Validé", style: .success)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if rootFolder.isEmpty {
                    Text("Choisissez le dossier où Droopies créera et synchronisera vos évaluations, vos classes et vos élèves :")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Bouton Principal : Sélecteur Natif Apple
                    Button {
                        showNativeFolderPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Sélectionner le dossier Source (Finder / Fichiers Apple)")
                                .font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))

                    if selectedProviderType == .dropbox && isCloudConnected {
                        HStack {
                            Spacer()
                            Button {
                                showFolderPicker = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "cloud")
                                    Text("Ou parcourir l'arborescence Dropbox à distance...")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(URL(fileURLWithPath: rootFolder).lastPathComponent)
                                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Spacer()

                            Button {
                                showNativeFolderPicker = true
                            } label: {
                                Label("Changer (Finder / Fichiers)", systemImage: "folder")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)

                            if selectedProviderType == .dropbox && isCloudConnected {
                                Button {
                                    showFolderPicker = true
                                } label: {
                                    Image(systemName: "cloud")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .help("Parcourir Dropbox à distance")
                            }
                        }

                        Text(rootFolder)
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

        // 1. Vérifier si un dossier local (Finder / Fichiers Apple) a été configuré
        if let bookmarkData = UserDefaults.standard.data(forKey: "droopies_local_folder_bookmark") {
            var isStale = false
            #if os(macOS)
            let resolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let resolutionOptions: URL.BookmarkResolutionOptions = []
            #endif
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale),
               resolvedURL.startAccessingSecurityScopedResource() {
                let localProvider = LocalStorageProvider(rootURL: resolvedURL)
                await MainActor.run {
                    self.appState.storageManager.setProvider(localProvider)
                    self.selectedProviderType = .local
                    self.isCloudConnected = true
                    self.connectedUserDisplayName = resolvedURL.lastPathComponent
                    self.connectedUserEmail = "Dossier local / synchronisé"
                    self.cloudStatusMessage = "\(resolvedURL.lastPathComponent) (Accès système)"
                    self.rootFolder = resolvedURL.path
                }
                await applyAndValidateSourceFolder(resolvedURL.path)
                return
            }
        }

        // 2. Récupérer le type de cloud mémorisé
        if let savedType = UserDefaults.standard.string(forKey: "droopies_selected_provider"),
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

                    // Si aucun dossier n'est configuré, ouvrir directement le sélecteur natif Apple
                    if self.rootFolder.isEmpty {
                        self.showNativeFolderPicker = true
                    }
                }

                // Si un dossier était déjà préalablement choisi, le valider
                if !rootFolder.isEmpty {
                    await applyAndValidateSourceFolder(rootFolder)
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
                self.rootFolder = ""
            }
        }
    }

    private func applyAndValidateSourceFolder(_ folderPath: String) async {
        isCheckingFolder = true
        defer { isCheckingFolder = false }

        let cleanPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            var remotePath = cleanPath
            if cleanPath.contains("/Dropbox") {
                if let range = cleanPath.range(of: "/Dropbox") {
                    let sub = String(cleanPath[range.upperBound...])
                    remotePath = sub.isEmpty ? "" : (sub.hasPrefix("/") ? sub : "/\(sub)")
                }
            }
            dropbox.configure(
                appKey: dropbox.appKey,
                refreshToken: dropbox.refreshToken,
                accessToken: dropbox.accessToken,
                rootFolderPath: remotePath
            )
        }

        do {
            // S'assurer que les 4 dossiers obligatoires existent dans le dossier source
            try await appState.storageManager.ensureSourceFolderStructure()

            await MainActor.run {
                self.rootFolder = cleanPath
                self.isFolderValidated = true
                let displayName = URL(fileURLWithPath: cleanPath).lastPathComponent
                self.folderStatusMessage = "Dossier Source '\(displayName)' configuré avec succès"
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
