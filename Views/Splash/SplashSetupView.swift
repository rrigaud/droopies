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
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState
    public var isSwitcherMode: Bool
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

    /// Indique si l'appareil est au premier démarrage SANS Internet et SANS cache local
    @State private var isFirstLaunchOfflineBlocked: Bool = false

    /// Indique si l'écran d'assistant de configuration manuel (Mode 2) est affiché
    @State private var isShowingManualSetup: Bool = false

    @State private var isLoadingData: Bool = false
    @State private var isDataLoaded: Bool = false

    @State private var errorMessage: String? = nil

    public init(appState: AppState, isSwitcherMode: Bool = false, onFinish: @escaping () -> Void) {
        self.appState = appState
        self.isSwitcherMode = isSwitcherMode
        self.onFinish = onFinish
        self._isCheckingCloud = State(initialValue: false)
        self._isShowingManualSetup = State(initialValue: isSwitcherMode)
    }

    // Progression fluide et dynamique échelonnée étape par étape (0.05 -> 1.0)
    @State private var progressValue: Double = 0.05
    @State private var progressLabel: String = "Connexion sécurisée à votre compte Cloud..."

    @MainActor
    private func updateProgress(value: Double, label: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            self.progressValue = max(self.progressValue, min(1.0, value))
            self.progressLabel = label
        }
    }

    public var body: some View {
        ZStack {
            LiquidGlassBackground()

            if isFirstLaunchOfflineBlocked {
                // MARK: - Mode 0 : Premier Lancement Hors-Ligne (Bloqué au splashscreen avec explications)
                firstLaunchOfflineBlockedView
                    .transition(.opacity)
            } else if !isShowingManualSetup {
                // MARK: - Mode 1 : Splashscreen Épuré Plein Écran (Lancements normaux)
                VStack(spacing: 24) {
                    Spacer()

                    // Mascotte Droopies géante (Taille 160, flottante et respirante)
                    DroopiesMascotView(size: 160, hasShadow: true, isAnimated: true)

                    // Titre et sous-titre
                    VStack(spacing: 6) {
                        Text("Droopies")
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        Text("Studio Numérique Enseignant • 100% Cloud")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    // Barre de progression sous l'icône et ses sous-textes (hauteur doublée à 8pt)
                    splashProgressBar
                        .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .transition(.opacity)
            } else {
                // MARK: - Mode 2 : Configuration Cloud Manuelle (Premier lancement ou Switcher)
                ScrollView {
                    VStack(spacing: 24) {
                        if isSwitcherMode {
                            // En-tête mode switcher
                            HStack(spacing: 14) {
                                DroopiesMascotView(size: 48, hasShadow: true)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Changer de Service Cloud")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))

                                    Text("Sélectionnez votre espace Cloud ou configurez un nouveau serveur")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .frame(maxWidth: 600)
                            .padding(.top, 16)
                            .padding(.horizontal, 6)
                        } else {
                            // En-tête premier lancement avec Mascotte
                            VStack(spacing: 16) {
                                DroopiesMascotView(size: 160, hasShadow: true, isAnimated: true)
                                    .padding(.top, 24)

                                VStack(spacing: 4) {
                                    Text("Droopies")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))

                                    Text("Studio Numérique Enseignant • 100% Cloud")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                // Barre de progression
                                splashProgressBar
                                    .padding(.top, 4)
                            }
                        }

                        // Carte Principale de Configuration Cloud
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
                        .padding(.bottom, 36)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .onChange(of: NetworkMonitor.shared.isOnline) { _, isOnline in
            if isOnline && isFirstLaunchOfflineBlocked {
                print("[SplashSetupView] 🟢 Connexion Internet rétablie : tentative d'initialisation automatique.")
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isFirstLaunchOfflineBlocked = false
                    isCheckingCloud = true
                }
                Task {
                    await autoDetectExistingConnection()
                }
            }
        }
        .toolbar {
            if isSwitcherMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Mode 0 : Premier Lancement Hors-Ligne (Bloqué avec explications bienveillantes)

    private var firstLaunchOfflineBlockedView: some View {
        VStack(spacing: 24) {
            Spacer()

            DroopiesMascotView(size: 150, hasShadow: true, isAnimated: true)

            VStack(spacing: 6) {
                Text("Droopies")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Studio Numérique Enseignant • 100% Cloud")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: "wifi.slash")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Text("Connexion Internet requise pour l'initialisation")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("Droopies fonctionne directement avec votre espace Cloud. Lors du tout premier lancement sur cet appareil, une connexion Internet est indispensable pour configurer votre dossier enseignant et synchroniser vos classes.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Divider()

                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("En attente d'une connexion réseau (Wi-Fi ou câble)...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                Button {
                    Task {
                        await autoDetectExistingConnection()
                    }
                } label: {
                    Label("Réessayer la connexion", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
            }
            .padding(22)
            .glassCard(cornerRadius: 20, strokeOpacity: 0.35)
            .frame(maxWidth: 480)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Barre de Progression Native (Hauteur Doublée à 8pt)

    private var splashProgressBar: some View {
        VStack(spacing: 10) {
            GeometryReader { pGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "0284C7"), Color(hex: "38BDF8")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, pGeo.size.width * CGFloat(progressValue)))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progressValue)
                }
            }
            .frame(maxWidth: 380)
            .frame(height: 8)

            HStack {
                Text(progressLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text("\(Int(progressValue * 100)) %")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "0284C7"))
            }
            .frame(maxWidth: 380)
            .frame(height: 18)
        }
    }

    // MARK: - Section 1 : Choix du Service Cloud

    private var cloudProviderSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                }

                Text("1. Choix du service Cloud")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                Spacer()

                BadgeView(selectedProviderType.displayName, style: .success)
            }

            HStack(spacing: 8) {
                cloudOptionChip(type: .dropbox, label: "Dropbox", color: Color(red: 0.0, green: 0.38, blue: 1.0))
                cloudOptionChip(type: .nextcloud, label: "Nextcloud", color: Color(red: 0.0, green: 0.51, blue: 0.79))
                cloudOptionChip(type: .oneDrive, label: "OneDrive", color: Color(red: 0.0, green: 0.47, blue: 0.83))
                cloudOptionChip(type: .googleDrive, label: "Google Drive", color: Color(red: 0.0, green: 0.67, blue: 0.28))
            }
            .padding(.leading, 36)
        }
    }

    @ViewBuilder
    private func cloudOptionChip(type: AppSettings.StorageProviderType, label: String, color: Color) -> some View {
        let isSelected = selectedProviderType == type
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProviderType = type
                UserDefaults.standard.set(type.rawValue, forKey: "droopies_selected_provider")
                if type != .dropbox {
                    isCloudConnected = false
                    cloudStatusMessage = "\(label) sera activé très prochainement. Veuillez utiliser Dropbox pour le moment."
                }
            }
            if type == .dropbox {
                Task { await autoDetectExistingConnection() }
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

            if selectedProviderType == .nextcloud {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connecter votre espace Nuage Éducation (Nextcloud WebDAV) :")
                        .font(.caption.bold())
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        TextField("URL du serveur (ex: https://nuage03.apps.education.fr/...)", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        HStack(spacing: 8) {
                            TextField("Identifiant enseignant", text: .constant(""))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)

                            SecureField("Mot de passe d'application", text: .constant(""))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                        Text("Connecteur Nuage Éducation en cours d'intégration native.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.leading, 36)
            } else if selectedProviderType == .oneDrive {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connecter votre compte Microsoft 365 Éducation :")
                        .font(.caption.bold())
                        .foregroundColor(.primary)

                    Button {} label: {
                        HStack(spacing: 8) {
                            Image(systemName: "server.rack")
                            Text("Se connecter avec Microsoft")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
                    .disabled(true)
                    .opacity(0.6)

                    Text("Le support Microsoft OneDrive sera activé dans la prochaine mise à jour.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.leading, 36)
            } else if selectedProviderType == .googleDrive {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connecter votre compte Google Workspace Éducation :")
                        .font(.caption.bold())
                        .foregroundColor(.primary)

                    Button {} label: {
                        HStack(spacing: 8) {
                            Image(systemName: "triangle.fill")
                            Text("Se connecter avec Google")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
                    .disabled(true)
                    .opacity(0.6)

                    Text("Le support Google Drive sera activé dans la prochaine mise à jour.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color.green.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .frame(width: 32, height: 32)
                    Image(systemName: isFolderValidated ? "checkmark" : "folder.badge.gearshape")
                        .font(.system(size: 14, weight: .bold))
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
                                CloudBrandIconView(type: selectedProviderType, size: 18)
                                Text(URL(fileURLWithPath: rootFolder).lastPathComponent.isEmpty ? "Racine \(selectedProviderType.displayName)" : URL(fileURLWithPath: rootFolder).lastPathComponent)
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
                                Label("Modifier", systemImage: "folder")
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

                    if isFolderValidated && isCloudConnected {
                        Button {
                            Task {
                                await applyAndValidateSourceFolder(rootFolder)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(isSwitcherMode ? "Basculer sur ce Cloud & Charger l'environnement" : "Ouvrir Droopies avec cet environnement")
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.leading, 36)
        }
    }

    // MARK: - Logique d'initialisation & actions

    @MainActor
    private func autoDetectExistingConnection() async {
        isCheckingCloud = true
        defer { isCheckingCloud = false }

        if CommandLine.arguments.contains("-testOfflineFirstLaunch") {
            NetworkMonitor.shared.isForcedOffline = true
        }

        let isSimulatedFresh = CommandLine.arguments.contains("-testOfflineFirstLaunch")
        let isOnline = isSimulatedFresh ? false : NetworkMonitor.shared.isOnline

        let provider = DropboxStorageProvider()
        let hasCache = isSimulatedFresh ? false : ((try? await appState.storageManager.localCacheProvider.itemExists(at: "Configuration/eleves.json")) ?? false)
        let hasSession = isSimulatedFresh ? false : provider.isConnected

        // MARK: - CAS 1 : Hors-Ligne
        if !isOnline {
            print("[SplashSetupView] Démarrage hors-ligne détecté.")
            if hasCache || hasSession {
                // Mode Hors-Ligne normal en classe : lecture du cache local
                updateProgress(value: 0.40, label: "Mode Hors-Ligne • Lecture du cache local...")
                await appState.loadInitialData { progress, label in
                    Task { @MainActor in
                        self.updateProgress(value: 0.40 + (progress * 0.60), label: label)
                    }
                }
                updateProgress(value: 1.0, label: "Mode Hors-Ligne prêt • Studio de correction actif")
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.onFinish()
                return
            } else {
                // Premier Lancement Hors-Ligne (appareil vierge sans compte ni cache local)
                print("[SplashSetupView] Premier lancement hors-ligne sans données : attente de connexion Internet.")
                self.isFirstLaunchOfflineBlocked = true
                self.isCheckingCloud = false
                return
            }
        }

        // MARK: - CAS 2 : En Ligne
        self.isFirstLaunchOfflineBlocked = false

        // Si aucun compte Cloud n'est encore associé (premier démarrage en ligne)
        if !provider.isConnected {
            print("[SplashSetupView] Premier lancement en ligne : aucun compte Cloud lié, affichage de l'assistant.")
            self.isCloudConnected = false
            self.isCheckingCloud = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.isShowingManualSetup = true
            }
            return
        }

        // Compte déjà associé : vérification du compte et du dossier
        if !isShowingManualSetup {
            updateProgress(value: 0.10, label: "Connexion sécurisée à votre compte Cloud...")
        }

        do {
            let info = try await provider.testConnection()
            if !isShowingManualSetup {
                updateProgress(value: 0.20, label: "Compte Cloud vérifié (\(info.name))")
            }

            var savedFolder = provider.rootFolderPath
            if savedFolder.isEmpty {
                savedFolder = UserDefaults.standard.string(forKey: "droopies_selected_folder") ?? ""
            }
            let cleanSaved = savedFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Si le chemin sauvegardé est vide, "/", ou un ancien dossier par défaut obsolète,
            // il n'est pas considéré comme un sous-dossier source valide.
            if cleanSaved.isEmpty || savedFolder == "/Droopies" || savedFolder == "Droopies" || savedFolder == "/Droopy" || savedFolder == "Droopy" {
                savedFolder = ""
                provider.setRootFolderPath("")
                UserDefaults.standard.removeObject(forKey: "droopies_dropbox_root_path")
                UserDefaults.standard.removeObject(forKey: "droopies_selected_folder")
            }

            // Vérifier si le dossier mémorisé existe RÉELLEMENT sur Dropbox
            var folderExists = false
            if !savedFolder.isEmpty {
                if !isShowingManualSetup {
                    updateProgress(value: 0.30, label: "Accès au dossier Source '\(cleanSaved)'...")
                }
                folderExists = (try? await provider.folderExists(at: savedFolder)) ?? false
            }

            self.appState.storageManager.setProvider(provider)
            self.isCloudConnected = true
            self.connectedUserDisplayName = info.name
            self.connectedUserEmail = info.email
            self.cloudStatusMessage = "\(info.name) (\(info.email))"
            self.rootFolder = savedFolder
            self.isFolderValidated = folderExists
            if !folderExists {
                self.isDataLoaded = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.isShowingManualSetup = true
                }
            }

            // Transition automatique : uniquement au démarrage initial (Splashscreen froid) !
            if !isShowingManualSetup && !isSwitcherMode && folderExists && !savedFolder.isEmpty {
                await applyAndValidateSourceFolder(savedFolder)
            }
        } catch {
            print("[SplashSetupView] Test Cloud échoué (\(error.localizedDescription)). Vérification cache local...")
            if hasCache {
                updateProgress(value: 0.50, label: "Réseau distant indisponible • Basculement Hors-Ligne...")
                await appState.loadInitialData { progress, label in
                    Task { @MainActor in
                        self.updateProgress(value: 0.50 + (progress * 0.50), label: label)
                    }
                }
                updateProgress(value: 1.0, label: "Mode Hors-Ligne prêt • Studio de correction actif")
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.onFinish()
                return
            }

            self.isCloudConnected = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.isShowingManualSetup = true
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

    @MainActor
    private func applyAndValidateSourceFolder(_ folderPath: String) async {
        isCheckingFolder = true
        defer { isCheckingFolder = false }

        let cleanPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cleanPath, forKey: "droopies_selected_folder")
        UserDefaults.standard.set(cleanPath, forKey: "droopies_dropbox_root_path")
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            dropbox.setRootFolderPath(cleanPath)
        }

        do {
            updateProgress(value: 0.40, label: "Vérification de l'arborescence Cloud...")

            try await appState.storageManager.ensureSourceFolderStructure { subProgress, stepText in
                Task { @MainActor in
                    let mapped = 0.40 + (subProgress * 0.15) // 40% -> 55%
                    self.updateProgress(value: mapped, label: stepText)
                }
            }

            self.rootFolder = cleanPath
            self.isFolderValidated = true
            self.appState.currentRootFolderPath = cleanPath
            let displayName = URL(fileURLWithPath: cleanPath).lastPathComponent.isEmpty ? "Racine" : URL(fileURLWithPath: cleanPath).lastPathComponent
            self.folderStatusMessage = "Dossier Cloud '\(displayName)' initialisé avec succès"

            // Chargement et vérification élève par élève
            await loadEnvironmentData()

            updateProgress(value: 1.0, label: "Environnement prêt • Ouverture de Droopies...")

            // Transition : auto-finish en mode Splashscreen initial, ou fermeture de la modale en mode switcher
            if !isSwitcherMode {
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s pour apprécier la barre à 100%
                self.onFinish()
            } else {
                self.onFinish()
                self.dismiss()
            }
        } catch {
            self.errorMessage = "Erreur configuration dossier Cloud : \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadEnvironmentData() async {
        isLoadingData = true
        defer { isLoadingData = false }

        await appState.loadInitialData { progress, label in
            Task { @MainActor in
                let mapped = 0.55 + (progress * 0.40) // 55% -> 95%
                self.updateProgress(value: mapped, label: label)
            }
        }

        self.isDataLoaded = true
    }
}
