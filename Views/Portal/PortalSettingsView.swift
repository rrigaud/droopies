//
//  PortalSettingsView.swift
//  Droopies
//
//  Configuration, prévisualisation directe et synchronisation du Portail Web Élèves autonome
//  (Compatible à 100 % avec le modèle cryptographique AES-256 et les 2 thèmes de Droopy v5).
//

import SwiftUI
import CryptoKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct PortalSettingsView: View {
    @Bindable public var appState: AppState

    // États du formulaire
    @State private var portalUrl: String = ""
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var selectedTheme: String = "emeraude"
    @State private var selectedIconMode: String = "default" // "default" ou "custom"

    // Sauvegarde en direct (Auto-Save en tâche de fond)
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var isAutoSaving: Bool = false
    @State private var showSavedBadge: Bool = false

    // États de vérification en ligne & synchronisation
    @State private var onlineStatus: OnlineAccessState = .checking
    @State private var dataSyncStatus: DataSyncState = .checking
    @State private var syncCheckTask: Task<Void, Never>? = nil

    // Gestion de l'icône personnalisée (Configuration/Icone Portail.png)
    @State private var customAvatarData: Data? = nil
    @State private var showIconSourcePopover: Bool = false
    @State private var isNativeFilePickerPresented: Bool = false
    @State private var isCloudPickerPresented: Bool = false
    @State private var isUploadingIcon: Bool = false

    // Génération
    @State private var isGenerating: Bool = false
    @State private var generationProgress: Double = 0.0
    @State private var generationStatusText: String = ""
    @State private var lastGenerationResult: PortalGenerationResult?
    @State private var errorMessage: String?
    @State private var showErrorAlert: Bool = false

    // Flag pour ignorer les triggers onChange lors du chargement initial
    @State private var isInitialLoading: Bool = true

    // MARK: - Enums d'état

    public enum OnlineAccessState: Equatable {
        case noUrl
        case checking
        case online
        case unreachable(String)
    }

    public enum DataSyncState: Equatable {
        case checking
        case generating
        case upToDateOnline(String)
        case generatedReadyToUpload
        case needsGeneration
        case noStudents
    }

    // MARK: - Thèmes visuels

    public struct ThemeOption: Identifiable {
        public let id: String
        public let name: String
        public let dotColor: Color
        public let accentColor: Color
        public let buttonTextColor: Color
    }

    public let availableThemes: [ThemeOption] = [
        ThemeOption(
            id: "emeraude",
            name: "Émeraude",
            dotColor: Color(red: 16/255, green: 185/255, blue: 129/255), // #10b981
            accentColor: Color(red: 16/255, green: 185/255, blue: 129/255),
            buttonTextColor: Color(red: 2/255, green: 44/255, blue: 34/255)   // #022c22
        ),
        ThemeOption(
            id: "azur",
            name: "Azur",
            dotColor: Color(red: 56/255, green: 189/255, blue: 248/255), // #38bdf8
            accentColor: Color(red: 56/255, green: 189/255, blue: 248/255),
            buttonTextColor: Color(red: 8/255, green: 47/255, blue: 73/255)   // #082f49
        )
    ]

    public init(appState: AppState) {
        self.appState = appState
    }

    private var currentTheme: ThemeOption {
        availableThemes.first(where: { $0.id == selectedTheme }) ?? availableThemes[0]
    }

    // MARK: - Vue Principale

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // 0. En-tête de page Liquid Glass
                portalPageHeader

                // 1. Bloc d'information et de réassurance tout en haut
                portalIntroBanner

                // 2. URL du Portail Web & États de synchronisation en ligne
                portalHeaderSection

                if isGenerating {
                    generationProgressBanner
                }

                // 3. Bloc de Personnalisation du Portail (Thème, Icône, Titres & Auto-Save)
                customizationBlockSection

                // 4. Bannière de succès après génération (si présente)
                if let result = lastGenerationResult {
                    generationSuccessBanner(result: result)
                }

                // 5. Aperçu du Portail Web pour les élèves (en dernier)
                portalLivePreviewSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 74)
            .padding(.bottom, 36)
        }
        .background(Color.clear)
        .fileImporter(
            isPresented: $isNativeFilePickerPresented,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            handleNativeIconImport(result: result)
        }
        .sheet(isPresented: $isCloudPickerPresented) {
            CloudImagePickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: "Configuration"
            ) { downloadedData in
                handleCloudIconSelected(data: downloadedData)
            }
        }
        .onAppear {
            loadInitialSettings()
        }
        .onChange(of: title) { _, _ in
            if !isInitialLoading { scheduleDebouncedAutoSave() }
        }
        .onChange(of: subtitle) { _, _ in
            if !isInitialLoading { scheduleDebouncedAutoSave() }
        }
        .onChange(of: appState.isOnline) { _, isOnline in
            if isOnline {
                Task { await checkOnlineAndSyncStatus() }
            }
        }
        .onChange(of: appState.triggerPortalGeneration) { _, newCount in
            if newCount > 0 {
                generatePortalAction()
            }
        }
        .alert("Erreur", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Une erreur est survenue.")
        }
    }

    // MARK: - 0. En-tête de page Liquid Glass

    private var portalPageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Portail de connexion des élèves")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Génération, personnalisation et hébergement du portail autonome chiffré")
                .font(.system(size: 13.5))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - 1. Bloc d'information & Sécurité (Tout en haut)

    private var portalIntroBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(currentTheme.accentColor.opacity(0.16))
                    .frame(width: 44, height: 44)

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(currentTheme.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Portail Web Élèves Autonome & Chiffré")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("AES-256")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(currentTheme.accentColor.opacity(0.18))
                    .foregroundColor(currentTheme.accentColor)
                    .clipShape(Capsule())
                }

                Text("Droopies génère un portail de connexion à destination des élèves. Cette page Web ne nécessite aucun serveur, il suffit de déposer le dossier généré (**Portail-Web**) sur un hébergeur en ligne (de nombreux hébergeurs gratuits existent comme Netlify par exemple). Toutes les données contenues dans ce portail sont sécurisées et chiffrées de bout en bout en AES-256 (dérivation de clé PBKDF2 à 10 000 itérations), garantissant une confidentialité totale.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(Color(white: 0.5, opacity: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(currentTheme.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 2. En-tête : URL du Portail Web & États de synchronisation

    private var portalHeaderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("URL & SYNCHRONISATION DU PORTAIL")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)

            ViewThatFits(in: .horizontal) {
                // Layout 1 ligne pour écrans larges et normaux (iPad paysage, Mac)
                HStack(alignment: .center, spacing: 12) {
                    urlInputField
                    onlineStatusBadge
                }

                // Layout compact de repli pour écrans très étroits
                VStack(alignment: .leading, spacing: 8) {
                    urlInputField
                    onlineStatusBadge
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.5, opacity: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var urlInputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundColor(.secondary)

            TextField("URL du portail (ex: https://mon-etablissement.fr/droopies)", text: $portalUrl)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit {
                    savePortalUrlAndCheck()
                }

            if !portalUrl.isEmpty {
                Button {
                    portalUrl = ""
                    savePortalUrlAndCheck()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                savePortalUrlAndCheck()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Enregistrer l'URL et actualiser la vérification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.5, opacity: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .disabled(!appState.isOnline)
        .opacity(appState.isOnline ? 1.0 : 0.6)
    }

    // Bouton 1 : État d'accessibilité du portail en ligne
    @ViewBuilder
    private var onlineStatusBadge: some View {
        if !appState.isOnline {
            HStack(spacing: 6) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Hors-ligne")
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.14))
            .foregroundColor(.orange)
            .clipShape(Capsule())
        } else {
            switch onlineStatus {
            case .checking:
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Accès au portail...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(Capsule())

            case .online:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Portail en ligne")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.14))
                .foregroundColor(.green)
                .clipShape(Capsule())

            case .unreachable:
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Portail non accessible")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
                .foregroundColor(.red)
                .clipShape(Capsule())

            case .noUrl:
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                    Text("URL non renseignée")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bannière de Progression pendant la Génération

    @ViewBuilder
    private var generationProgressBanner: some View {
        HStack(spacing: 12) {
            ProgressView(value: generationProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 160)

            Text(generationStatusText.isEmpty ? "Génération du portail en cours..." : generationStatusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Text("\(Int(generationProgress * 100)) %")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(currentTheme.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(currentTheme.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 3. Bloc de Personnalisation du Portail

    private var customizationBlockSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Text("Personnalisation du Portail")
                    .font(.headline)

                if !appState.isOnline {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Lecture seule (Hors-ligne)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }
            }

            // A. Thème visuel du portail (SelectButton compact natif Liquid Glass)
            VStack(alignment: .leading, spacing: 8) {
                Text("Thème visuel du portail")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    ForEach(availableThemes) { theme in
                        let isSelected = (selectedTheme == theme.id)
                        Button {
                            selectedTheme = theme.id
                            triggerImmediateAutoSave()
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.dotColor)
                                    .frame(width: 10, height: 10)

                                Text(theme.name)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(theme.accentColor.opacity(0.18))
                                    : AnyShapeStyle(Color.primary.opacity(0.05))
                            )
                            .foregroundColor(isSelected ? theme.accentColor : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? theme.accentColor : Color.primary.opacity(0.12), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // B. Icône du portail (SelectButton : Chouette par défaut vs Personnalisée)
            VStack(alignment: .leading, spacing: 8) {
                Text("Icône du portail")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    // Option 1 : Chouette par défaut
                    let isDefault = (selectedIconMode == "default" || customAvatarData == nil)
                    Button {
                        selectedIconMode = "default"
                        triggerImmediateAutoSave()
                    } label: {
                        HStack(spacing: 8) {
                            if let owlData = PortalDefaultIcon.pngData {
                                CustomAvatarImageView(data: owlData)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            Text("Icône par défaut")
                                .font(.system(size: 13, weight: isDefault ? .bold : .medium, design: .rounded))

                            if isDefault {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isDefault
                                ? AnyShapeStyle(currentTheme.accentColor.opacity(0.18))
                                : AnyShapeStyle(Color.primary.opacity(0.05))
                        )
                        .foregroundColor(isDefault ? currentTheme.accentColor : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isDefault ? currentTheme.accentColor : Color.primary.opacity(0.12), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)

                    // Option 2 : Icône personnalisée (si présente dans Configuration/Icone Portail.png)
                    if let customData = customAvatarData {
                        let isCustom = (selectedIconMode == "custom")
                        Button {
                            selectedIconMode = "custom"
                            triggerImmediateAutoSave()
                        } label: {
                            HStack(spacing: 8) {
                                CustomAvatarImageView(data: customData)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text("Icône personnalisée")
                                    .font(.system(size: 13, weight: isCustom ? .bold : .medium, design: .rounded))

                                if isCustom {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }

                                Button {
                                    resetCustomAvatar()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Supprimer l'icône personnalisée")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isCustom
                                    ? AnyShapeStyle(currentTheme.accentColor.opacity(0.18))
                                    : AnyShapeStyle(Color.primary.opacity(0.05))
                            )
                            .foregroundColor(isCustom ? currentTheme.accentColor : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(isCustom ? currentTheme.accentColor : Color.primary.opacity(0.12), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Option 3 : Ajouter une icône personnalisée...
                    Button {
                        showIconSourcePopover = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: customAvatarData == nil ? "plus" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text(customAvatarData == nil ? "Ajouter une icône personnalisée..." : "Remplacer l'icône...")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.10))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.blue.opacity(0.30), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showIconSourcePopover, arrowEdge: .top) {
                        iconSourcePopoverContent
                    }

                    Spacer()
                }
            }

            // C. Titre du Portail Web & Sous-titre descriptif / Établissement (Sur la même ligne)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Titre du Portail Web")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Portail Élèves", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sous-titre descriptif / Établissement")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Évaluations & Documents de la classe", text: $subtitle)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Fallback vertical si l'écran est très étroit
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Titre du Portail Web")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Portail Élèves", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sous-titre descriptif / Établissement")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("Évaluations & Documents de la classe", text: $subtitle)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // D. Pied du bloc : Sauvegarde en direct (Auto-Save)
            HStack(alignment: .center) {
                Spacer()

                if !appState.isOnline {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                        Text("Personnalisation modifiable en ligne uniquement (stockée sur Dropbox)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.orange)
                } else {
                    // Indicateur de sauvegarde en direct en tâche de fond
                    HStack(spacing: 6) {
                        if isAutoSaving {
                            ProgressView()
                                .controlSize(.small)
                            Text("Enregistrement...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if showSavedBadge {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Modifications enregistrées")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("Enregistrement automatique en direct")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.65))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: isAutoSaving)
                    .animation(.easeInOut(duration: 0.25), value: showSavedBadge)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color(white: 0.5, opacity: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .disabled(!appState.isOnline)
        .opacity(appState.isOnline ? 1.0 : 0.72)
    }

    private var iconSourcePopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choisir une icône")
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            Text("L'image sera enregistrée dans Configuration/Icone Portail.png et utilisée pour l'en-tête et l'icône PWA du portail web.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 8) {
                // Option 1 : Sur cet appareil
                Button {
                    showIconSourcePopover = false
                    isNativeFilePickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .font(.body)
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sur cet appareil")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Depuis vos photos ou fichiers locaux")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                // Option 2 : Sur Dropbox / OneDrive / etc.
                let providerType = appState.storageManager.activeProvider.providerType
                Button {
                    showIconSourcePopover = false
                    isCloudPickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: providerType.iconName)
                            .font(.body)
                            .foregroundColor(providerType == .dropbox ? .blue : (providerType == .googleDrive ? .green : .purple))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sur \(providerType.displayName)")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("Parcourir votre espace Cloud actif")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    // MARK: - 4. Bannière de succès après génération

    private func generationSuccessBanner(result: PortalGenerationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(currentTheme.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Portail Web généré avec succès !")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(result.studentCount) élèves chiffrés en AES-256 (PBKDF2 10k itérations)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    lastGenerationResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(currentTheme.accentColor)
                        .font(.caption)
                    Text("Emplacement :")
                        .font(.caption.bold())
                    Text("Dossier Source > Exports > Portail-Web")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }

                Text("Votre portail statique autonome (HTML, CSS, WebCrypto JS, Service Worker) est prêt. Pour le mettre en ligne, transférez simplement ce dossier sur votre hébergement ou glissez-le sur Netlify Drop / Cloudflare Pages.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.5, opacity: 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(currentTheme.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(currentTheme.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - 5. Aperçu du Portail Web pour les élèves (En dernier)

    private var portalLivePreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Aperçu du Portail Web pour les élèves", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(currentTheme.accentColor)
                        .frame(width: 8, height: 8)
                    Text(currentTheme.name)
                        .font(.caption.bold())
                        .foregroundColor(currentTheme.accentColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(currentTheme.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }

            portalLivePreviewCard
        }
    }

    private var portalLivePreviewCard: some View {
        let isAzur = (selectedTheme == "azur")
        let bgGradient = isAzur
            ? RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 12/255, green: 74/255, blue: 110/255),
                    Color(red: 23/255, green: 37/255, blue: 84/255),
                    Color(red: 2/255, green: 6/255, blue: 23/255)
                ]),
                center: .top,
                startRadius: 20,
                endRadius: 400
            )
            : RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 6/255, green: 78/255, blue: 59/255),
                    Color(red: 2/255, green: 44/255, blue: 34/255),
                    Color(red: 2/255, green: 6/255, blue: 23/255)
                ]),
                center: .top,
                startRadius: 20,
                endRadius: 400
            )

        return VStack(spacing: 20) {

            // Avatar squircle flottant
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(currentTheme.accentColor.opacity(0.18))
                        .frame(width: 88, height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(currentTheme.accentColor.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 8)

                    // Affichage de l'icône choisie (Personnalisée si sélectionnée, ou Chouette par défaut)
                    if selectedIconMode == "custom", let customData = customAvatarData {
                        CustomAvatarImageView(data: customData)
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if let owlData = PortalDefaultIcon.pngData {
                        CustomAvatarImageView(data: owlData)
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                // Ombre pulsante au sol
                Ellipse()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 68, height: 8)
                    .blur(radius: 3)
            }
            .padding(.top, 10)

            // Titre et sous-titre
            VStack(spacing: 4) {
                Text(title.isEmpty ? "Portail Élèves" : title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)

                Text(subtitle.isEmpty ? "Évaluations & Documents de la classe" : subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.85))
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
            }

            // Faux formulaire de connexion Droopy v5
            VStack(alignment: .leading, spacing: 14) {
                // Header de la carte
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ESPACE RÉSERVÉ")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(currentTheme.accentColor)
                            .tracking(0.5)

                        Text("Connexion à votre dossier")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("AES 256")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(currentTheme.accentColor.opacity(0.2))
                    .foregroundColor(currentTheme.accentColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(currentTheme.accentColor.opacity(0.4), lineWidth: 1)
                    )
                }
                .padding(.bottom, 6)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1),
                    alignment: .bottom
                )

                // Champ Identifiant élève
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(currentTheme.accentColor)
                        Text("IDENTIFIANT ÉLÈVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.85))
                            .tracking(0.5)
                    }

                    HStack {
                        Text("Votre identifiant")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.35))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                    Text("Transmis par votre enseignant")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.leading, 2)
                }

                // Champ Mot de passe
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(currentTheme.accentColor)
                        Text("MOT DE PASSE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.85))
                            .tracking(0.5)
                    }

                    HStack {
                        Text("••••••••")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.55))
                        Spacer()
                        Image(systemName: "eye.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                    Text("Cliquez sur l'icône de l'œil pour vérifier votre saisie")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.leading, 2)
                }

                // Bouton Ouvrir mon dossier
                HStack(spacing: 8) {
                    Text("OUVRIR MON DOSSIER")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.5)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(currentTheme.buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(currentTheme.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: currentTheme.accentColor.opacity(0.35), radius: 6, x: 0, y: 3)
                .padding(.top, 4)

                // Footer PWA
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(currentTheme.accentColor)
                            .frame(width: 6, height: 6)
                        Text("Connexion directe & hors-ligne")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    Spacer()
                    Text("📲 Installer l'application")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(currentTheme.accentColor)
                }
                .padding(.top, 8)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1),
                    alignment: .top
                )
            }
            .frame(maxWidth: 350)
            .padding(22)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(bgGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(currentTheme.accentColor.opacity(0.3), lineWidth: 1.5)
        )
    }

    // MARK: - Actions & Logique de Sauvegarde en direct (Auto-Save)

    private func loadInitialSettings() {
        portalUrl = appState.settings.portalUrl
        title = appState.settings.portalTitle
        subtitle = appState.settings.portalSubtitle
        selectedTheme = appState.settings.portalTheme.isEmpty ? "emeraude" : appState.settings.portalTheme
        selectedIconMode = appState.settings.portalIcon.isEmpty ? "default" : appState.settings.portalIcon

        Task {
            let data = await appState.storageManager.loadPortalIconData()
            await MainActor.run {
                self.customAvatarData = data
                if data == nil && self.selectedIconMode == "custom" {
                    self.selectedIconMode = "default"
                }
                self.isInitialLoading = false
            }
            await checkOnlineAndSyncStatus()
        }
    }

    private func scheduleDebouncedAutoSave() {
        guard appState.isOnline else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms de temporisation
            guard !Task.isCancelled else { return }
            await performAutoSave()
        }
    }

    private func triggerImmediateAutoSave() {
        guard appState.isOnline else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            await performAutoSave()
        }
    }

    private func performAutoSave() async {
        guard appState.isOnline else { return }
        await MainActor.run { isAutoSaving = true }

        var updated = appState.settings
        updated.portalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalTheme = selectedTheme
        updated.portalIcon = selectedIconMode
        updated.touchModification()

        try? await appState.storageManager.saveSettings(updated)

        await MainActor.run {
            self.appState.settings = updated
            self.isAutoSaving = false
            self.showSavedBadge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showSavedBadge = false
            }
        }

        await checkOnlineAndSyncStatus()
    }

    private func savePortalUrlAndCheck() {
        guard appState.isOnline else { return }
        var updated = appState.settings
        updated.portalUrl = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.touchModification()
        Task {
            try? await appState.storageManager.saveSettings(updated)
            await MainActor.run {
                self.appState.settings = updated
            }
            await checkOnlineAndSyncStatus()
        }
    }

    private func generatePortalAction() {
        let provider = appState.storageManager.activeProvider
        guard provider.isConnected else {
            errorMessage = "Aucun service cloud connecté. Veuillez vérifier votre connexion."
            showErrorAlert = true
            return
        }

        guard !appState.students.isEmpty else {
            errorMessage = "Veuillez d'abord importer ou ajouter des élèves avant de générer le portail."
            showErrorAlert = true
            return
        }

        isGenerating = true
        appState.isPortalGenerating = true
        dataSyncStatus = .generating
        generationProgress = 0.0
        generationStatusText = "Initialisation..."

        var updated = appState.settings
        updated.portalUrl = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalTheme = selectedTheme
        updated.portalIcon = selectedIconMode
        updated.touchModification()

        let useCustom = (selectedIconMode == "custom" && customAvatarData != nil)

        Task {
            do {
                try await appState.storageManager.saveSettings(updated)
                let result = try await PortalGeneratorService.shared.generatePortal(
                    provider: provider,
                    students: appState.students,
                    title: updated.portalTitle,
                    subtitle: updated.portalSubtitle,
                    theme: updated.portalTheme,
                    useCustomIcon: useCustom
                ) { progress, status in
                    Task { @MainActor in
                        self.generationProgress = progress
                        self.generationStatusText = status
                    }
                }

                var finalSettings = updated
                finalSettings.portalLastGeneratedAt = result.generatedAt
                try await appState.storageManager.saveSettings(finalSettings)

                await MainActor.run {
                    self.appState.settings = finalSettings
                    self.isGenerating = false
                    self.appState.isPortalGenerating = false
                    self.appState.isPortalUpdateNeeded = false
                    self.lastGenerationResult = result
                    self.dataSyncStatus = .generatedReadyToUpload
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.appState.isPortalGenerating = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    self.dataSyncStatus = .needsGeneration
                }
            }
        }
    }

    // MARK: - Vérification En Ligne & Synchronisation

    private func checkOnlineAndSyncStatus() async {
        guard appState.isOnline else {
            await MainActor.run {
                self.onlineStatus = .noUrl
                self.dataSyncStatus = .checking
            }
            return
        }
        syncCheckTask?.cancel()
        let task = Task {
            await performOnlineAndSyncStatusCheck()
        }
        syncCheckTask = task
        _ = await task.result
    }

    private func performOnlineAndSyncStatusCheck() async {
        guard !appState.students.isEmpty else {
            await MainActor.run {
                self.onlineStatus = .noUrl
                self.dataSyncStatus = .noStudents
            }
            return
        }

        var cleanUrl = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanUrl.isEmpty {
            if !cleanUrl.lowercased().hasPrefix("http://") && !cleanUrl.lowercased().hasPrefix("https://") {
                cleanUrl = "https://" + cleanUrl
            }
            while cleanUrl.hasSuffix("/") {
                cleanUrl.removeLast()
            }
        }

        // Si aucune URL n'est renseignée
        if cleanUrl.isEmpty {
            let exportsMatchLocal = await checkExportsMatchesDroopies()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.onlineStatus = .noUrl
                self.dataSyncStatus = exportsMatchLocal ? .generatedReadyToUpload : .needsGeneration
            }
            return
        }

        await MainActor.run {
            self.onlineStatus = .checking
            self.dataSyncStatus = .checking
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 6.0
        let session = URLSession(configuration: config)

        var onlineAccessible = false
        var onlineMatchesLocal = false
        var onlineVersionDate: String? = nil

        // 1. Tenter de lire version.json en ligne
        if let vUrl = URL(string: "\(cleanUrl)/version.json") {
            if let (data, resp) = try? await session.data(from: vUrl),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                onlineAccessible = true
                onlineMatchesLocal = checkVersionMatchesDroopies(versionData: data)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let up = json["updatedAt"] as? String {
                    onlineVersionDate = up
                }
            }
        }

        // 2. Si pas de version.json, tenter scripts/data.js
        if !onlineAccessible, let dUrl = URL(string: "\(cleanUrl)/scripts/data.js") {
            if let (data, resp) = try? await session.data(from: dUrl),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                onlineAccessible = true
                if let js = String(data: data, encoding: .utf8) {
                    onlineMatchesLocal = compareDataJsWithLocalStudents(js)
                }
                if let lastMod = http.value(forHTTPHeaderField: "Last-Modified") {
                    onlineVersionDate = lastMod
                }
            }
        }

        // 3. Fallback d'accessibilité : index.html
        if !onlineAccessible, let idxUrl = URL(string: "\(cleanUrl)/index.html") {
            if let (_, resp) = try? await session.data(from: idxUrl),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                onlineAccessible = true
            }
        }

        guard !Task.isCancelled else { return }

        let resolvedOnlineStatus: OnlineAccessState = onlineAccessible ? .online : .unreachable("Portail non accessible")

        let resolvedSyncStatus: DataSyncState
        if onlineMatchesLocal {
            let dateText: String
            if let vDate = onlineVersionDate {
                dateText = formattedDate(vDate)
            } else if let lastGen = appState.settings.portalLastGeneratedAt {
                dateText = formattedDate(lastGen)
            } else {
                let df = DateFormatter()
                df.dateStyle = .short
                df.timeStyle = .short
                df.locale = Locale(identifier: "fr_FR")
                dateText = df.string(from: Date())
            }
            resolvedSyncStatus = .upToDateOnline(dateText)
        } else {
            // Le portail en ligne n'est pas à jour ou pas encore déployé.
            // On vérifie si le dossier local Exports/Portail-Web correspond à la configuration Droopies actuelle
            let exportsMatchLocal = await checkExportsMatchesDroopies()
            guard !Task.isCancelled else { return }
            if exportsMatchLocal {
                resolvedSyncStatus = .generatedReadyToUpload
            } else {
                resolvedSyncStatus = .needsGeneration
            }
        }

        await MainActor.run {
            self.onlineStatus = resolvedOnlineStatus
            self.dataSyncStatus = resolvedSyncStatus
            self.appState.isPortalUpdateNeeded = (resolvedSyncStatus == .needsGeneration)
        }
    }

    private func checkExportsMatchesDroopies() async -> Bool {
        guard !appState.students.isEmpty else { return false }

        // 1. Priorité à version.json (métadonnées complètes : thème, titre, sous-titre, icône, élèves)
        if let versionData = try? await appState.storageManager.activeProvider.readData(at: "Exports/Portail-Web/version.json") {
            return checkVersionMatchesDroopies(versionData: versionData)
        }

        // 2. Fallback rétrocompatible : scripts/data.js
        if let exportData = try? await appState.storageManager.activeProvider.readData(at: "Exports/Portail-Web/scripts/data.js"),
           let exportJs = String(data: exportData, encoding: .utf8) {
            return compareDataJsWithLocalStudents(exportJs)
        }

        return false
    }

    private func checkVersionMatchesDroopies(versionData: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: versionData) as? [String: Any] else { return false }

        // 1. Thème sélectionné (Émeraude vs Azur)
        let expectedTheme = selectedTheme.isEmpty ? "emeraude" : selectedTheme
        let generatedTheme = (json["theme"] as? String) ?? ""
        if !generatedTheme.isEmpty && generatedTheme != expectedTheme {
            return false
        }

        // 2. Titre principal
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedTitle = cleanTitle.isEmpty ? "Portail Élèves" : cleanTitle
        let generatedTitle = (json["title"] as? String) ?? ""
        if !generatedTitle.isEmpty && generatedTitle != expectedTitle {
            return false
        }

        // 3. Sous-titre descriptif / Établissement
        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedSubtitle = cleanSubtitle.isEmpty ? "Évaluations & Documents de la classe" : cleanSubtitle
        let generatedSubtitle = (json["subtitle"] as? String) ?? ""
        if !generatedSubtitle.isEmpty && generatedSubtitle != expectedSubtitle {
            return false
        }

        // 4. Mode d'icône (défaut vs personnalisée)
        let generatedIconMode = (json["iconMode"] as? String) ?? "default"
        if generatedIconMode != selectedIconMode {
            return false
        }

        // 5. Empreinte exacte des élèves (identifiant, mot de passe, nom, classe)
        let studentHashString = appState.students
            .sorted(by: { $0.id < $1.id })
            .map { "\($0.login.lowercased()):\($0.password):\($0.name):\($0.classe)" }
            .joined(separator: "|")
        let currentStudentsDigest = SHA256.hash(data: Data(studentHashString.utf8)).map { String(format: "%02x", $0) }.joined()

        if let generatedDigest = json["studentsDigest"] as? String, !generatedDigest.isEmpty {
            if generatedDigest != currentStudentsDigest {
                return false
            }
        } else if let studentCount = json["studentCount"] as? Int {
            if studentCount != appState.students.count {
                return false
            }
        }

        return true
    }

    private func compareDataJsWithLocalStudents(_ jsContent: String) -> Bool {
        guard !appState.students.isEmpty else { return false }

        // Extraction des h (SHA-256 des identifiants élèves)
        let pattern = #""h"\s*:\s*"([a-fA-F0-9]{64})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(jsContent.startIndex..<jsContent.endIndex, in: jsContent)
        let matches = regex.matches(in: jsContent, options: [], range: range)
        let extractedHashes = Set(matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: jsContent) else { return nil }
            return String(jsContent[r]).lowercased()
        })

        let localHashes = Set(appState.students.map { s in
            let normLogin = s.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let digest = SHA256.hash(data: Data(normLogin.utf8))
            return digest.map { String(format: "%02x", $0) }.joined().lowercased()
        })

        guard extractedHashes == localHashes else { return false }

        // Vérification du titre principal
        let cleanTitle = appState.settings.portalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedTitle = cleanTitle.isEmpty ? "Portail Élèves" : cleanTitle
        if let titleJson = try? String(data: JSONEncoder().encode(expectedTitle), encoding: .utf8) {
            if !jsContent.contains(titleJson) {
                return false
            }
        }

        return true
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        display.locale = Locale(identifier: "fr_FR")
        return display.string(from: date)
    }

    // MARK: - Gestion de l'icône personnalisée (Configuration/Icone Portail.png)

    private func handleNativeIconImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else { return }
                saveImportedIcon(data: data)
            } catch {
                errorMessage = "Erreur de lecture de l'image : \(error.localizedDescription)"
                showErrorAlert = true
            }

        case .failure(let error):
            errorMessage = "Sélection annulée : \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func handleCloudIconSelected(data: Data) {
        guard !data.isEmpty else { return }
        saveImportedIcon(data: data)
    }

    private func saveImportedIcon(data: Data) {
        guard appState.isOnline else { return }
        isUploadingIcon = true
        Task {
            do {
                try await appState.storageManager.savePortalIconData(data)
                var updated = appState.settings
                updated.portalIcon = "custom"
                updated.touchModification()
                try? await appState.storageManager.saveSettings(updated)

                await MainActor.run {
                    self.customAvatarData = data
                    self.selectedIconMode = "custom"
                    self.appState.settings = updated
                    self.isUploadingIcon = false
                    self.showSavedBadge = true
                }
                await checkOnlineAndSyncStatus()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erreur d'enregistrement de l'icône : \(error.localizedDescription)"
                    self.showErrorAlert = true
                    self.isUploadingIcon = false
                }
            }
        }
    }

    private func resetCustomAvatar() {
        guard appState.isOnline else { return }
        isUploadingIcon = true
        Task {
            do {
                try await appState.storageManager.deletePortalIcon()
                var updated = appState.settings
                updated.portalIcon = "default"
                updated.touchModification()
                try? await appState.storageManager.saveSettings(updated)

                await MainActor.run {
                    self.customAvatarData = nil
                    self.selectedIconMode = "default"
                    self.appState.settings = updated
                    self.isUploadingIcon = false
                    self.showSavedBadge = true
                }
                await checkOnlineAndSyncStatus()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erreur lors de la suppression de l'icône : \(error.localizedDescription)"
                    self.showErrorAlert = true
                    self.isUploadingIcon = false
                }
            }
        }
    }
}

// MARK: - Composant Image Multiplateforme (iOS & macOS)

private struct CustomAvatarImageView: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
        }
        #endif
    }
}
