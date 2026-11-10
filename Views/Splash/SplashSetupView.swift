//
//  SplashSetupView.swift
//  Droopies
//
//  Écran de démarrage et assistant de vérification Cloud (Splash & Cloud Stepper).
//  Fonctionne 100 % en Cloud (Dropbox, Nextcloud, OneDrive, Google Drive).
//  - Au quotidien : splashscreen épuré plein écran (Logo + Titre + Progression 1-2s).
//  - Hors-ligne sans compte : écran informatif clair expliquant le besoin d'Internet.
//  - Premier démarrage en ligne : Assistant Stepper 3 étapes séquentiel fluide.
//

import SwiftUI
import AuthenticationServices

public struct SplashSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState
    public var isSwitcherMode: Bool
    public var onFinish: () -> Void

    // MARK: - Étape active du Stepper (1: Service, 2: Connexion, 3: Dossier)
    @State private var currentStep: Int = 1

    @State private var selectedProviderType: AppSettings.StorageProviderType? = nil
    @State private var rootFolder: String = ""

    private var effectiveProviderType: AppSettings.StorageProviderType {
        selectedProviderType ?? .dropbox
    }

    // Boîte de dialogue de sélection du dossier dans le Cloud
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

    /// Indique si l'écran d'assistant de configuration manuel (Mode Stepper) est affiché
    @State private var isShowingManualSetup: Bool = false

    @State private var isLoadingData: Bool = false
    @State private var isDataLoaded: Bool = false
    @State private var errorMessage: String? = nil

    // Progression fluide et dynamique échelonnée étape par étape (0.05 -> 1.0)
    @State private var progressValue: Double = 0.05
    @State private var progressLabel: String = "Connexion sécurisée à votre compte Cloud..."

    public init(appState: AppState, isSwitcherMode: Bool = false, onFinish: @escaping () -> Void) {
        self.appState = appState
        self.isSwitcherMode = isSwitcherMode
        self.onFinish = onFinish
        self._isCheckingCloud = State(initialValue: false)
        self._isShowingManualSetup = State(initialValue: isSwitcherMode)
        self._selectedProviderType = State(initialValue: isSwitcherMode ? appState.storageManager.activeProvider.providerType : nil)
    }

    @MainActor
    private func updateProgress(value: Double, label: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            self.progressValue = max(self.progressValue, min(1.0, value))
            self.progressLabel = label
        }
    }

    // MARK: - Vue Principale

    public var body: some View {
        ZStack {
            LiquidGlassBackground()

            if isFirstLaunchOfflineBlocked {
                // MARK: - CAS A2 : Premier Lancement Hors-Ligne (Informatif & Épuré)
                firstLaunchOfflineBlockedView
                    .transition(.opacity)
            } else if !isShowingManualSetup {
                // MARK: - CAS B1 & A1 : Splashscreen Épuré Plein Écran (Lancement Quotidien)
                splashMinimalView
                    .transition(.opacity)
            } else {
                // MARK: - CAS B2 : Assistant Stepper Séquentiel (3 étapes)
                stepperContainerView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            let providerToUse: StorageProvider = (appState.storageManager.activeProvider as? DropboxStorageProvider) ?? DropboxStorageProvider()
            CloudFolderPickerSheet(
                provider: providerToUse,
                initialPath: rootFolder
            ) { chosenPath in
                self.rootFolder = chosenPath
                self.isFolderValidated = true
                UserDefaults.standard.set(chosenPath, forKey: "droopies_selected_folder")
                if let dropbox = providerToUse as? DropboxStorageProvider {
                    self.appState.storageManager.setProvider(dropbox)
                }

                // Dès que le dossier est choisi : on masque le bloc de paramétrage
                // et on revient au splashscreen en mode "tout est prêt, on charge !"
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.isShowingManualSetup = false
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

    // MARK: - 1. Splashscreen Épuré Plein Écran (Normal)

    private var splashMinimalView: some View {
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

            // Barre de progression sous l'icône
            splashProgressBar
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - 2. Premier Lancement Hors-Ligne (Informatif, sans formulaire)

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
                        .frame(width: 60, height: 60)

                    Image(systemName: "wifi.slash")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Text("Connexion Internet requise")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Pour configurer Droopies et associer votre espace Cloud lors du premier démarrage sur cet appareil, veuillez connecter l'iPad à un réseau Internet (Wi-Fi ou partage de connexion).")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Divider()

                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Détection automatique dès la connexion...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(24)
            .glassCard(cornerRadius: 20, strokeOpacity: 0.35)
            .frame(maxWidth: 460)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - 3. Assistant Stepper 3 Étapes

    private var stepperContainerView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // En-tête : Mascotte Droopies + Titre
                if !isSwitcherMode {
                    VStack(spacing: 12) {
                        DroopiesMascotView(size: 110, hasShadow: true, isAnimated: true)
                            .padding(.top, 16)

                        VStack(spacing: 4) {
                            Text("Bienvenue sur Droopies")
                                .font(.system(size: 26, weight: .bold, design: .rounded))

                            Text("Configuration initiale de votre espace enseignant")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 14) {
                        DroopiesMascotView(size: 44, hasShadow: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Changer de Service Cloud")
                                .font(.system(size: 20, weight: .bold, design: .rounded))

                            Text("Associez un nouvel espace de stockage à Droopies")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: 580)
                    .padding(.top, 16)
                    .padding(.horizontal, 6)
                }

                // Carte Principale du Stepper
                VStack(alignment: .leading, spacing: 18) {
                    // Indicateur des 3 étapes (Breadcrumb)
                    stepperBreadcrumb

                    Divider()

                    // Contenu de l'étape active
                    Group {
                        switch currentStep {
                        case 1:
                            step1ProviderSection
                        case 2:
                            step2ConnectionSection
                        case 3:
                            step3FolderSection
                        default:
                            step1ProviderSection
                        }
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

                    Divider()

                    // Barre de navigation (Précédent / Suivant)
                    stepperNavigationBar
                }
                .padding(22)
                .glassCard(cornerRadius: 22, strokeOpacity: 0.45)
                .frame(maxWidth: 580)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Fil d'Ariane des 3 Étapes

    private var stepperBreadcrumb: some View {
        HStack(spacing: 8) {
            stepIndicatorItem(
                step: 1,
                title: "1. Service Cloud",
                isCompleted: currentStep > 1,
                isActive: currentStep == 1
            )

            stepSeparator(isCompleted: currentStep > 1)

            stepIndicatorItem(
                step: 2,
                title: "2. Compte",
                isCompleted: currentStep > 2 || (currentStep == 1 && isCloudConnected),
                isActive: currentStep == 2
            )

            stepSeparator(isCompleted: currentStep > 2)

            stepIndicatorItem(
                step: 3,
                title: "3. Dossier Source",
                isCompleted: isFolderValidated && !rootFolder.isEmpty,
                isActive: currentStep == 3
            )
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func stepIndicatorItem(step: Int, title: String, isCompleted: Bool, isActive: Bool) -> some View {
        Button {
            // Permettre la navigation directe vers les étapes franchies
            if step < currentStep || (step == 2 && isCloudConnected) || (step == 3 && isCloudConnected) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    currentStep = step
                }
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            isActive
                                ? Color(hex: "0284C7")
                                : (isCompleted ? Color.green : Color.primary.opacity(0.08))
                        )
                        .frame(width: 22, height: 22)

                    if isCompleted && !isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(step)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(isActive ? .white : (isCompleted ? .white : .secondary))
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .rounded))
                    .foregroundColor(isActive ? .primary : (isCompleted ? .primary : .secondary.opacity(0.8)))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stepSeparator(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.green.opacity(0.5) : Color.primary.opacity(0.12))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Étape 1 : Choix du Service Cloud

    private var step1ProviderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choisissez votre service Cloud")
                    .font(.headline.bold())
                    .foregroundColor(.primary)

                Text("Sélectionnez la plateforme Cloud où vous souhaitez stocker vos évaluations et vos classes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                cloudOptionChip(type: .dropbox, label: "Dropbox", color: Color(red: 0.0, green: 0.38, blue: 1.0))
                cloudOptionChip(type: .nextcloud, label: "Nextcloud", color: Color(red: 0.0, green: 0.51, blue: 0.79))
                cloudOptionChip(type: .oneDrive, label: "OneDrive", color: Color(red: 0.0, green: 0.47, blue: 0.83))
                cloudOptionChip(type: .googleDrive, label: "Google Drive", color: Color(red: 0.0, green: 0.67, blue: 0.28))
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Droopies fonctionne directement avec votre espace de stockage, sans intermédiaire ni serveur tiers (RGPD).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
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
        } label: {
            VStack(spacing: 8) {
                CloudBrandIconView(type: type, size: 28, isSelected: isSelected)
                    .frame(height: 28)

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: color.opacity(0.35), radius: 8, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Étape 2 : Connexion au Compte

    private var step2ConnectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connexion au compte \(effectiveProviderType.displayName)")
                    .font(.headline.bold())
                    .foregroundColor(.primary)

                Text("Autorisez Droopies à accéder à vos devoirs et évaluations dans votre espace.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if effectiveProviderType == .nextcloud {
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
            } else if effectiveProviderType == .oneDrive {
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
            } else if effectiveProviderType == .googleDrive {
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
            } else if isCloudConnected {
                // Compte connecté avec succès
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
                .padding(14)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
            } else {
                // Non connecté : Bouton 1-clic de connexion
                VStack(alignment: .leading, spacing: 12) {
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

                    // Option avancée dépliable : App Key personnalisée si souhaité
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
            }
        }
    }

    // MARK: - Étape 3 : Choix du Dossier Source

    private var step3FolderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dossier Source dans \(effectiveProviderType.displayName)")
                    .font(.headline.bold())
                    .foregroundColor(.primary)

                Text("Droopies a besoin d'un dossier dans votre espace pour y ranger vos devoirs scannés, annotations et corrections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if rootFolder.isEmpty {
                VStack(spacing: 12) {
                    // Action 1 : Année scolaire courante (1-clic direct)
                    Button {
                        let targetYear = "/\(AppSettings.currentSchoolYear)"
                        self.rootFolder = targetYear
                        self.isFolderValidated = true

                        // Dès le dossier choisi : masquer le stepper et basculer sur le splashscreen épuré
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isShowingManualSetup = false
                        }
                        Task {
                            await applyAndValidateSourceFolder(targetYear)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Créer le dossier de l'année scolaire : \(AppSettings.currentSchoolYear)")
                                    .font(.subheadline.bold())
                                Text("Recommandé • Initialise automatiquement la structure")
                                    .font(.caption2)
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))

                    // Action 2 : Parcourir l'arborescence Cloud
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 15))
                            Text("Parcourir et sélectionner un autre dossier...")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Dossier déjà sélectionné
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: rootFolder).lastPathComponent.isEmpty ? "Racine \(effectiveProviderType.displayName)" : URL(fileURLWithPath: rootFolder).lastPathComponent)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))

                            Text("Chemin Cloud : \(rootFolder)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            showFolderPicker = true
                        } label: {
                            Text("Modifier...")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Color.blue.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )

                    if let msg = folderStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(isFolderValidated ? .green : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - Barre de Navigation du Stepper (Précédent / Suivant / Terminer)

    private var stepperNavigationBar: some View {
        HStack {
            if currentStep > 1 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Précédent")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if isSwitcherMode {
                Button("Fermer") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            if currentStep == 1 {
                if selectedProviderType != nil {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentStep = 2
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Suivant")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
                    .transition(.scale.combined(with: .opacity))
                }
            } else if currentStep == 2 {
                if isCloudConnected {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentStep = 3
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Suivant")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
                    .transition(.scale.combined(with: .opacity))
                }
            } else if currentStep == 3 {
                if !rootFolder.isEmpty && isFolderValidated {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isShowingManualSetup = false
                        }
                        Task {
                            await applyAndValidateSourceFolder(rootFolder)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(isSwitcherMode ? "Valider le nouveau Cloud" : "Terminer & Ouvrir Droopies")
                        }
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Barre de Progression Native

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

    // MARK: - Logique d'initialisation & actions

    @MainActor
    private func autoDetectExistingConnection() async {
        isCheckingCloud = true
        defer { isCheckingCloud = false }

        if CommandLine.arguments.contains("-testStep1Selected") {
            self.selectedProviderType = .dropbox
            self.currentStep = 1
            self.isShowingManualSetup = true
            return
        }
        if CommandLine.arguments.contains("-testStep2") {
            self.selectedProviderType = .dropbox
            self.currentStep = 2
            self.isShowingManualSetup = true
            return
        }
        if CommandLine.arguments.contains("-testStep2Connected") {
            self.selectedProviderType = .dropbox
            self.isCloudConnected = true
            self.connectedUserDisplayName = "Enseignant Dropbox"
            self.connectedUserEmail = "enseignant@ac-academie.fr"
            self.currentStep = 2
            self.isShowingManualSetup = true
            return
        }
        if CommandLine.arguments.contains("-testStep3") {
            self.selectedProviderType = .dropbox
            self.isCloudConnected = true
            self.connectedUserDisplayName = "Enseignant Dropbox"
            self.connectedUserEmail = "enseignant@ac-academie.fr"
            self.currentStep = 3
            self.isShowingManualSetup = true
            return
        }
        if CommandLine.arguments.contains("-testSplash") {
            self.isShowingManualSetup = false
            self.isFirstLaunchOfflineBlocked = false
            self.updateProgress(value: 0.65, label: "Chargement des classes et élèves...")
            return
        }

        if CommandLine.arguments.contains("-testOfflineFirstLaunch") {
            NetworkMonitor.shared.isForcedOffline = true
        }

        let isSimulatedOfflineFresh = CommandLine.arguments.contains("-testOfflineFirstLaunch")
        let isSimulatedStepper = CommandLine.arguments.contains("-testStepper")

        let isOnline = isSimulatedOfflineFresh ? false : NetworkMonitor.shared.isOnline

        let provider = DropboxStorageProvider()
        let hasCache = (isSimulatedOfflineFresh || isSimulatedStepper) ? false : ((try? await appState.storageManager.localCacheProvider.itemExists(at: "Configuration/eleves.json")) ?? false)
        let hasSession = (isSimulatedOfflineFresh || isSimulatedStepper) ? false : provider.isConnected

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
        if !provider.isConnected || isSimulatedStepper {
            print("[SplashSetupView] Premier lancement en ligne : aucun compte Cloud lié, affichage du Stepper.")
            self.isCloudConnected = false
            self.isCheckingCloud = false
            self.currentStep = 1
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

            if cleanSaved.isEmpty || savedFolder == "/Droopies" || savedFolder == "Droopies" || savedFolder == "/Droopy" || savedFolder == "Droopy" {
                savedFolder = ""
                provider.setRootFolderPath("")
                UserDefaults.standard.removeObject(forKey: "droopies_dropbox_root_path")
                UserDefaults.standard.removeObject(forKey: "droopies_selected_folder")
            }

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
                self.currentStep = 3 // Le compte est connecté, on propose directement de choisir le dossier
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.isShowingManualSetup = true
                }
            }

            // Transition automatique : uniquement au démarrage normal avec dossier valide !
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
            self.currentStep = 1
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.currentStep = 2
                }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.isShowingManualSetup = true
                self.currentStep = 3
            }
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
