//
//  CSVImportWizardSheet.swift
//  Droopies
//
//  Assistant d'importation CSV immersif plein écran en 3 étapes :
//  1. Sélection du CSV (Appareil ou Cloud actif)
//  2. Sélection et correspondance des colonnes (Droopy v5)
//  3. Sélection des élèves, détection des en-têtes et importation progressive avec protection anti-doublons.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Types de colonnes CSV (Conforme Droopy v5)

public enum CSVColumnType: String, CaseIterable, Identifiable {
    case none = "none"
    case nom = "nom"
    case prenom = "prenom"
    case nomPrenom = "nom_prenom"
    case classe = "classe"
    case sexeMF = "sexe_mf"
    case sexeGF = "sexe_gf"
    case login = "login"
    case password = "password"
    case url = "url"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "(Ignorer)"
        case .nom: return "NOM"
        case .prenom: return "Prénom"
        case .nomPrenom: return "NOM Prénom"
        case .classe: return "Classe"
        case .sexeMF: return "Sexe (M/F)"
        case .sexeGF: return "Sexe (G/F)"
        case .login: return "Identifiant"
        case .password: return "Mot de passe"
        case .url: return "URL"
        }
    }

    public var icon: String {
        switch self {
        case .none: return "slash.circle"
        case .nom, .prenom, .nomPrenom: return "person.text.rectangle"
        case .classe: return "graduationcap"
        case .sexeMF, .sexeGF: return "person.2"
        case .login: return "person.badge.key"
        case .password: return "key"
        case .url: return "link"
        }
    }

    public var accentColor: Color {
        switch self {
        case .none: return .secondary
        case .nom, .prenom, .nomPrenom: return .blue
        case .classe: return .purple
        case .sexeMF, .sexeGF: return .pink
        case .login: return .orange
        case .password: return .indigo
        case .url: return .teal
        }
    }
}

// MARK: - Modèle d'élève candidat à l'import

public struct CandidateStudent: Identifiable {
    public let id = UUID()
    public let rawIndex: Int
    public var isSelected: Bool
    public let isSuspectedHeader: Bool
    public var name: String
    public var classe: String
    public var gender: Student.Gender
    public var login: String
    public var password: String
    public var urlDropbox: String
}

// MARK: - Modèle de Conflit de Doublon

public struct DuplicateConflict: Identifiable {
    public let id = UUID()
    public let candidate: CandidateStudent
    public let existingStudent: Student
    public let reason: String
}

// MARK: - Vue Principale : CSVImportWizardSheet

public struct CSVImportWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState

    // Stepper d'étapes (1, 2, 3)
    @State private var wizardStep: Int = 1

    // Fichier chargé
    @State private var loadedFileName: String = ""
    @State private var rawRows: [[String]] = []
    @State private var columnMappings: [CSVColumnType] = []

    // État Étape 1
    @State private var isFileImporterPresented: Bool = false
    @State private var isCloudPickerPresented: Bool = false
    @State private var showManualPasteArea: Bool = false
    @State private var manualCSVText: String = ""
    @State private var isLoadingFile: Bool = false
    @State private var errorMessage: String? = nil

    // État Étape 3
    @State private var candidates: [CandidateStudent] = []

    // Gestion des doublons
    @State private var pendingConflicts: [DuplicateConflict] = []
    @State private var activeConflictIndex: Int = 0
    @State private var showDuplicateResolver: Bool = false
    @State private var candidatesToActuallyImport: [CandidateStudent] = []

    // Progression de l'importation progressive
    @State private var isImporting: Bool = false
    @State private var importProgress: Double = 0.0
    @State private var importCurrentIndex: Int = 0
    @State private var importTotalCount: Int = 0
    @State private var currentProcessingStudentName: String = ""
    @State private var currentProcessingAction: String = ""
    @State private var importSuccessCount: Int = 0
    @State private var isImportFinished: Bool = false

    private let initialCSVText: String?
    private let initialFileName: String?
    private let initialStep: Int

    public init(appState: AppState, initialCSVText: String? = nil, initialFileName: String? = nil, initialStep: Int = 1) {
        self.appState = appState
        self.initialCSVText = initialCSVText
        self.initialFileName = initialFileName
        self.initialStep = initialStep
    }

    private var cloudName: String {
        appState.storageManager.activeProvider.providerType.displayName
    }

    public var body: some View {
        ZStack {
            // Fond verre liquide immersif
            LiquidGlassBackground()

            VStack(spacing: 0) {
                // Header supérieur flottant avec Stepper
                topFloatingHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider()
                    .opacity(0.4)

                // Contenu selon l'étape active
                ZStack {
                    switch wizardStep {
                    case 1:
                        step1FileSelectionView
                            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    case 2:
                        step2ColumnMappingView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case 3:
                        step3CandidateSelectionView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Overlay modal : Résolution des doublons
            if showDuplicateResolver, activeConflictIndex < pendingConflicts.count {
                duplicateResolverOverlay(conflict: pendingConflicts[activeConflictIndex])
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Overlay modal : Progression de l'importation progressive
            if isImporting {
                progressiveImportOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Spinner de chargement de fichier
            if isLoadingFile {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Analyse du fichier CSV en cours...")
                            .font(.subheadline.bold())
                    }
                    .padding(24)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleLocalFileImport(result: result)
        }
        .sheet(isPresented: $isCloudPickerPresented) {
            let configPath = appState.currentRootFolderPath.isEmpty
                ? "Configuration"
                : "\(appState.currentRootFolderPath)/Configuration"
            CloudCSVFilePickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: configPath
            ) { cloudFile in
                loadCloudCSVFile(cloudFile)
            }
        }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if let text = initialCSVText {
                loadCSV(text: text, sourceName: initialFileName ?? "Import.csv")
            }
        }
    }

    // MARK: - Header supérieur flottant avec Stepper

    private var topFloatingHeader: some View {
        HStack(alignment: .center) {
            // Bouton Fermer / Quitter
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Annuler")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .foregroundColor(.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            Spacer()

            // Stepper flottant 3 étapes
            HStack(spacing: 8) {
                stepperPill(
                    stepNumber: 1,
                    title: "1. Sélection du CSV",
                    icon: "doc.text",
                    isActive: wizardStep == 1,
                    isDone: wizardStep > 1
                )

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary.opacity(0.4))

                stepperPill(
                    stepNumber: 2,
                    title: "2. Données & Colonnes",
                    icon: "tablecells",
                    isActive: wizardStep == 2,
                    isDone: wizardStep > 2
                )

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary.opacity(0.4))

                stepperPill(
                    stepNumber: 3,
                    title: "3. Élèves",
                    icon: "person.3",
                    isActive: wizardStep == 3,
                    isDone: false
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)

            Spacer()

            // Espaceur symétrique pour centrer le stepper
            Color.clear
                .frame(width: 80, height: 32)
        }
    }

    private func stepperPill(stepNumber: Int, title: String, icon: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 13, weight: .bold))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isActive ? .bold : .regular))
                    .foregroundColor(isActive ? .white : .secondary)
            }

            Text(title)
                .font(.system(size: 13, weight: isActive ? .bold : .medium, design: .rounded))
                .foregroundColor(isActive ? .white : (isDone ? .primary : .secondary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Group {
                if isActive {
                    LinearGradient(
                        colors: [Color.blue, Color(hex: "0284C7")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else if isDone {
                    Color.green.opacity(0.12)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(Capsule())
        .shadow(color: isActive ? Color.blue.opacity(0.3) : .clear, radius: 6, y: 2)
    }

    // MARK: - ÉTAPE 1 : Sélection du CSV

    private var step1FileSelectionView: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Titre et explications
                VStack(spacing: 8) {
                    Text("Importer une liste d'élèves")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Sélectionnez votre fichier CSV ou TXT (export Pronote, Siècle, Onde ou tableur).")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                // Deux grandes cartes de sélection
                HStack(spacing: 24) {
                    // Carte 1 : Sur cet appareil
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 80, height: 80)

                                #if os(iOS)
                                Image(systemName: "ipad.and.arrow.forward")
                                    .font(.system(size: 38))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                #else
                                Image(systemName: "laptopcomputer.and.arrow.down")
                                    .font(.system(size: 38))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                #endif
                            }

                            VStack(spacing: 6) {
                                Text("Sur cet appareil")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)

                                Text("Fichiers locaux, iCloud Drive ou Téléchargements")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }

                            HStack(spacing: 6) {
                                Text("Parcourir")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        }
                        .frame(width: 280, height: 250)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(LinearGradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)

                    // Carte 2 : Sur le Cloud connecté (Dropbox, OneDrive...)
                    Button {
                        isCloudPickerPresented = true
                    } label: {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.05))
                                    .frame(width: 80, height: 80)

                                CloudBrandIconView(type: appState.storageManager.activeProvider.providerType, size: 44)
                            }

                            VStack(spacing: 6) {
                                Text("Sur \(cloudName)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)

                                Text("Naviguer et choisir un fichier directement dans votre stockage Cloud")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }

                            HStack(spacing: 6) {
                                Text("Explorer le Cloud")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.primary)
                            .clipShape(Capsule())
                        }
                        .frame(width: 280, height: 250)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }

                // Astuce d'organisation : Dossier Configuration
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dossier Configuration dans votre Cloud")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)

                        Text("Vous pouvez y glisser vos fichiers CSV d'élèves. Droopies accède directement au dossier Configuration !")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        isCloudPickerPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text("Ouvrir Configuration")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 584)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )

                // Option manuelle (Coller du texte brut)
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showManualPasteArea.toggle()
                        }
                    } label: {
                        Label(
                            showManualPasteArea ? "Masquer la saisie manuelle" : "Ou coller du texte CSV manuellement",
                            systemImage: showManualPasteArea ? "chevron.up" : "doc.on.clipboard"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showManualPasteArea {
                        VStack(alignment: .trailing, spacing: 8) {
                            TextEditor(text: $manualCSVText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 580, height: 110)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                            if !manualCSVText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    loadCSV(text: manualCSVText, sourceName: "Texte collé")
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("Analyser ce texte")
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - ÉTAPE 2 : Correspondance des Colonnes (Droopy v5)

    private var isStep2Valid: Bool {
        let hasClass = columnMappings.contains(.classe)
        let hasNomPrenom = columnMappings.contains(.nomPrenom)
        let hasNomAndPrenom = columnMappings.contains(.nom) && columnMappings.contains(.prenom)
        let hasNomOnly = columnMappings.contains(.nom)
        return hasClass && (hasNomPrenom || hasNomAndPrenom || hasNomOnly)
    }

    private var step2ColumnMappingView: some View {
        VStack(spacing: 0) {
            // Bandeau supérieur d'instructions et statut
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Correspondance des colonnes")
                            .font(.system(size: 18, weight: .bold))
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(loadedFileName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Text("Indiquez le contenu de chaque colonne pour que Droopies prépare les comptes élèves.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Statut de validation
                if isStep2Valid {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Champs requis identifiés")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Classe et Nom/Prénom requis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Bouton Suivant
                Button {
                    prepareCandidatesForStep3()
                } label: {
                    HStack(spacing: 6) {
                        Text("Suivant : Sélection des élèves")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if isStep2Valid {
                                LinearGradient(colors: [Color.blue, Color(hex: "0284C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: isStep2Valid ? Color.blue.opacity(0.3) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!isStep2Valid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Tableau horizontal avec les colonnes et les 5 premières lignes
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    let colCount = columnMappings.count
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        columnMappingCard(colIndex: colIdx)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Barre inférieure de retour
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        wizardStep = 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                        Text("Changer de fichier CSV")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(rawRows.count) lignes détectées dans le fichier")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func columnMappingCard(colIndex: Int) -> some View {
        let currentType = (colIndex < columnMappings.count) ? columnMappings[colIndex] : .none

        return VStack(alignment: .leading, spacing: 10) {
            // En-tête de la colonne : Numéro & Menu déroulant Droopy v5
            VStack(alignment: .leading, spacing: 4) {
                Text("COLONNE \(colIndex + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Menu {
                    ForEach(CSVColumnType.allCases) { type in
                        Button {
                            updateMapping(at: colIndex, to: type)
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                                if currentType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: currentType.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentType.accentColor)

                        Text(currentType.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentType == .none ? .secondary : .primary)

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(currentType.accentColor.opacity(currentType == .none ? 0.06 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(currentType.accentColor.opacity(currentType == .none ? 0.15 : 0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 5 premières lignes de prévisualisation pour cette colonne
            VStack(alignment: .leading, spacing: 6) {
                let previewLimit = min(5, rawRows.count)
                ForEach(0..<previewLimit, id: \.self) { rowIdx in
                    let val = (colIndex < rawRows[rowIdx].count) ? rawRows[rowIdx][colIndex] : ""
                    HStack {
                        Text(rowIdx == 0 ? "L1" : "L\(rowIdx + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 18, alignment: .leading)

                        Text(val.isEmpty ? "—" : val)
                            .font(.system(size: 12, weight: rowIdx == 0 ? .semibold : .regular))
                            .foregroundColor(val.isEmpty ? .secondary.opacity(0.4) : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(rowIdx == 0 ? 0.05 : 0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .frame(width: 190)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(currentType == .none ? Color.primary.opacity(0.08) : currentType.accentColor.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }

    private func updateMapping(at index: Int, to newType: CSVColumnType) {
        guard index < columnMappings.count else { return }
        columnMappings[index] = newType
    }

    // MARK: - ÉTAPE 3 : Sélection des Élèves

    private var selectedCount: Int {
        candidates.filter { $0.isSelected }.count
    }

    private var step3CandidateSelectionView: some View {
        VStack(spacing: 0) {
            // Barre d'outils supérieure de l'étape 3
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sélection des élèves à importer")
                        .font(.system(size: 18, weight: .bold))

                    Text("Vérifiez la liste. L'en-tête potentiel a été signalé pour que vous puissiez l'exclure si nécessaire.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Actions rapides de sélection
                HStack(spacing: 10) {
                    Button("Tout cocher") {
                        setAllSelection(to: true)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)

                    Text("•").foregroundColor(.secondary)

                    Button("Tout décocher") {
                        setAllSelection(to: false)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Compteur
                Text("\(selectedCount) / \(candidates.count) sélectionnés")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Tableau des élèves candidats
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, cand in
                        candidateRowView(index: index, candidate: cand)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Barre d'actions inférieure flottante
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        wizardStep = 2
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Précédent : Correspondance")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    initiateImportProcess()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(selectedCount > 1 ? "Importer les \(selectedCount) élèves sélectionnés" : "Importer l'élève sélectionné")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if selectedCount > 0 {
                                LinearGradient(colors: [Color.blue, Color(hex: "0284C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: selectedCount > 0 ? Color.blue.opacity(0.3) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func candidateRowView(index: Int, candidate: CandidateStudent) -> some View {
        let isHeader = candidate.isSuspectedHeader
        let isSelected = candidate.isSelected

        return HStack(spacing: 14) {
            // Checkbox
            Toggle("", isOn: Binding(
                get: { candidates[index].isSelected },
                set: { candidates[index].isSelected = $0 }
            ))
            .labelsHidden()

            // Index
            Text("#\(candidate.rawIndex)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 32, alignment: .leading)

            // Nom et Prénom
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(candidate.name.isEmpty ? "(Sans nom)" : candidate.name)
                        .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)

                    if isHeader && isSelected {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("En-tête probable")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                    } else if isHeader && !isSelected {
                        Text("(En-tête ignoré)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                if isHeader && isSelected {
                    Text("Cette première ligne ressemble à des titres de colonnes. Décochez-la si ce n'est pas un élève.")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Classe
            if !candidate.classe.isEmpty {
                BadgeView(candidate.classe, style: isSelected ? .info : .neutral)
                    .frame(width: 80, alignment: .center)
            } else {
                Text("—")
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
            }

            // Sexe
            Text(candidate.gender == .female ? "F" : "M")
                .font(.caption.bold())
                .foregroundColor(candidate.gender == .female ? .pink : .blue)
                .frame(width: 30, alignment: .center)

            // Identifiant
            Text(candidate.login.isEmpty ? "Auto-généré" : candidate.login)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(candidate.login.isEmpty ? .secondary.opacity(0.6) : .secondary)
                .frame(width: 140, alignment: .leading)

            // Mot de passe
            Text(candidate.password.isEmpty ? "Auto-généré" : candidate.password)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(candidate.password.isEmpty ? .secondary.opacity(0.6) : .secondary)
                .frame(width: 120, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Group {
                if isHeader && isSelected {
                    Color.red.opacity(0.12)
                } else if !isSelected {
                    Color.secondary.opacity(0.04)
                } else {
                    Color.primary.opacity(0.03)
                }
            }
        )
        .opacity(isSelected ? 1.0 : 0.5)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHeader && isSelected ? Color.red.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isHeader && isSelected ? 1.5 : 1)
        )
    }

    private func setAllSelection(to val: Bool) {
        for idx in 0..<candidates.count {
            candidates[idx].isSelected = val
        }
    }

    // MARK: - ÉTAPE 4 : Résolution des Doublons (Modal Overlay)

    private func duplicateResolverOverlay(conflict: DuplicateConflict) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 20) {
                // En-tête
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Doublon potentiel détecté (\(activeConflictIndex + 1) / \(pendingConflicts.count))")
                            .font(.system(size: 17, weight: .bold))
                        Text(conflict.reason)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }

                Text("Cet élève est déjà présent dans votre base de données Droopies. Souhaitez-vous l'ignorer ou l'importer en double ?")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Cartes comparatives
                HStack(spacing: 16) {
                    // Carte Élève déjà dans Droopies
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(.blue)
                            Text("Déjà dans Droopies")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                        }

                        Text(conflict.existingStudent.name)
                            .font(.system(size: 15, weight: .bold))

                        HStack(spacing: 8) {
                            BadgeView(conflict.existingStudent.classe, style: .info)
                            if !conflict.existingStudent.login.isEmpty {
                                Text("ID: \(conflict.existingStudent.login)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Dossier : \(conflict.existingStudent.folderName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.2), lineWidth: 1))

                    // Carte Élève du fichier CSV
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.orange)
                            Text("Dans le fichier CSV")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        Text(conflict.candidate.name)
                            .font(.system(size: 15, weight: .bold))

                        HStack(spacing: 8) {
                            BadgeView(conflict.candidate.classe, style: .warning)
                            if !conflict.candidate.login.isEmpty {
                                Text("ID: \(conflict.candidate.login)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Ligne #\(conflict.candidate.rawIndex) du fichier")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                }

                // Boutons d'action
                HStack(spacing: 12) {
                    Button {
                        resolveCurrentConflict(shouldImport: false)
                    } label: {
                        Text("Ignorer cet élève (Recommandé)")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        resolveCurrentConflict(shouldImport: true)
                    } label: {
                        Text("Importer quand même")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                if pendingConflicts.count > 1 {
                    Button("Ignorer tous les doublons restants") {
                        ignoreAllRemainingConflicts()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 580)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.3), radius: 25, y: 12)
            .padding(20)
        }
    }

    private func resolveCurrentConflict(shouldImport: Bool) {
        let current = pendingConflicts[activeConflictIndex]
        if !shouldImport {
            candidatesToActuallyImport.removeAll(where: { $0.id == current.candidate.id })
        }
        advanceConflictResolution()
    }

    private func ignoreAllRemainingConflicts() {
        for idx in activeConflictIndex..<pendingConflicts.count {
            let candId = pendingConflicts[idx].candidate.id
            candidatesToActuallyImport.removeAll(where: { $0.id == candId })
        }
        showDuplicateResolver = false
        startProgressiveImportExecution()
    }

    private func advanceConflictResolution() {
        if activeConflictIndex + 1 < pendingConflicts.count {
            activeConflictIndex += 1
        } else {
            showDuplicateResolver = false
            startProgressiveImportExecution()
        }
    }

    // MARK: - ÉTAPE 5 : Importation Progressive & Non-bloquante

    private var progressiveImportOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 24) {
                if isImportFinished {
                    // Écran de succès final
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))

                    VStack(spacing: 8) {
                        Text("Importation réussie !")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("\(importSuccessCount) nouveaux élèves importés et configurés.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("Dossiers et partages synchronisés sur \(cloudName).")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Progression active
                    ProgressView()
                        .controlSize(.large)

                    VStack(spacing: 8) {
                        Text("Importation en cours...")
                            .font(.system(size: 20, weight: .bold))

                        Text("Élève \(importCurrentIndex) sur \(importTotalCount)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.blue)

                        if !currentProcessingStudentName.isEmpty {
                            Text(currentProcessingStudentName)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Text(currentProcessingAction)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: importProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(maxWidth: 360)

                    Text("Temporisation douce active pour respecter les quotas de votre stockage \(cloudName).")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(32)
            .frame(minWidth: 420)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
            .padding(20)
        }
    }

    // MARK: - Mécaniques Métier & Logique d'Import

    private func handleLocalFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: url),
               let text = decodeText(data: data) {
                loadCSV(text: text, sourceName: url.lastPathComponent)
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                loadCSV(text: text, sourceName: url.lastPathComponent)
            } else {
                errorMessage = "Impossible de lire le fichier sélectionné."
            }
        case .failure(let err):
            errorMessage = "Erreur de sélection : \(err.localizedDescription)"
        }
    }

    private func loadCloudCSVFile(_ cloudFile: CloudItem) {
        isLoadingFile = true
        Task {
            do {
                let data = try await appState.storageManager.activeProvider.readData(at: cloudFile.path)
                if let text = decodeText(data: data) {
                    await MainActor.run {
                        self.isLoadingFile = false
                        self.loadCSV(text: text, sourceName: cloudFile.name)
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingFile = false
                        self.errorMessage = "Impossible de décoder l'encodage du fichier CSV."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingFile = false
                    self.errorMessage = "Erreur lors du téléchargement Cloud : \(error.localizedDescription)"
                }
            }
        }
    }

    private func decodeText(data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .macOSRoman) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    private func loadCSV(text: String, sourceName: String) {
        let parsed = parseCSVRobust(text: text)
        guard !parsed.isEmpty else {
            errorMessage = "Le fichier ne contient aucune ligne de données exploitable."
            return
        }

        self.loadedFileName = sourceName
        self.rawRows = parsed

        let colCount = parsed.map { $0.count }.max() ?? 0
        let firstRow = parsed.first ?? []

        // Deviner automatiquement les correspondances (Droopy v5)
        var guessed: [CSVColumnType] = []
        for c in 0..<colCount {
            let h = (c < firstRow.count) ? firstRow[c] : ""
            guessed.append(guessColumnType(header: h))
        }
        self.columnMappings = guessed

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.wizardStep = 2
        }
    }

    private func guessColumnType(header: String) -> CSVColumnType {
        let h = header.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let withoutPrenom = h.replacingOccurrences(of: "prenom", with: "").replacingOccurrences(of: "prénom", with: "")
        let hasNom = withoutPrenom.contains("nom") || h == "last_name" || h == "lastname"
        let hasPrenom = h.contains("prenom") || h.contains("prénom") || h == "first_name" || h == "firstname"

        if hasNom && hasPrenom {
            return .nomPrenom
        }
        if hasPrenom {
            return .prenom
        }
        if hasNom {
            return .nom
        }
        if h.contains("classe") || h.contains("division") || h.contains("groupe") {
            return .classe
        }
        if h.contains("sexe") || h.contains("genre") {
            return .sexeMF
        }
        if h.contains("login") || h.contains("identifiant") || h.contains("user") {
            return .login
        }
        if h.contains("pass") || h.contains("mdp") || h.contains("code") {
            return .password
        }
        if h.contains("dropbox") || h.contains("url") || h.contains("lien") {
            return .url
        }
        return .none
    }

    private func detectHasHeader(row: [String]) -> Bool {
        guard !row.isEmpty else { return false }
        let headerKeywords = [
            "nom", "prenom", "prénom", "classe", "division", "sexe", "genre",
            "login", "identifiant", "user", "password", "mdp", "pass",
            "dropbox", "url", "lien", "mail", "email", "naissance", "ine", "numero", "id"
        ]
        let joined = row.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
        return headerKeywords.contains { joined.contains($0) }
    }

    private func prepareCandidatesForStep3() {
        guard !rawRows.isEmpty else { return }

        let firstRow = rawRows.first ?? []
        let isFirstRowSuspectedHeader = detectHasHeader(row: firstRow)

        let nomIdx = columnMappings.firstIndex(of: .nom)
        let prenomIdx = columnMappings.firstIndex(of: .prenom)
        let nomPrenomIdx = columnMappings.firstIndex(of: .nomPrenom)
        let classeIdx = columnMappings.firstIndex(of: .classe)
        let sexeMFIdx = columnMappings.firstIndex(of: .sexeMF)
        let sexeGFIdx = columnMappings.firstIndex(of: .sexeGF)
        let loginIdx = columnMappings.firstIndex(of: .login)
        let passIdx = columnMappings.firstIndex(of: .password)
        let urlIdx = columnMappings.firstIndex(of: .url)

        var list: [CandidateStudent] = []

        for (rowIdx, row) in rawRows.enumerated() {
            guard !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }

            var fullName = ""
            if let np = nomPrenomIdx, np < row.count {
                fullName = row[np].trimmingCharacters(in: .whitespaces)
            } else {
                let n = (nomIdx != nil && nomIdx! < row.count) ? row[nomIdx!].trimmingCharacters(in: .whitespaces) : ""
                let p = (prenomIdx != nil && prenomIdx! < row.count) ? row[prenomIdx!].trimmingCharacters(in: .whitespaces) : ""
                if !n.isEmpty && !p.isEmpty {
                    fullName = "\(n.uppercased()) \(p)"
                } else if !n.isEmpty {
                    fullName = n
                } else {
                    fullName = p
                }
            }

            let cl = (classeIdx != nil && classeIdx! < row.count) ? row[classeIdx!].trimmingCharacters(in: .whitespaces) : ""

            var gender: Student.Gender = .male
            if let sIdx = sexeMFIdx ?? sexeGFIdx, sIdx < row.count {
                let sVal = row[sIdx].trimmingCharacters(in: .whitespaces).uppercased()
                if sVal.hasPrefix("F") {
                    gender = .female
                }
            }

            let log = (loginIdx != nil && loginIdx! < row.count) ? row[loginIdx!].trimmingCharacters(in: .whitespaces) : ""
            let pwd = (passIdx != nil && passIdx! < row.count) ? row[passIdx!].trimmingCharacters(in: .whitespaces) : ""
            let url = (urlIdx != nil && urlIdx! < row.count) ? row[urlIdx!].trimmingCharacters(in: .whitespaces) : ""

            let isSuspected = (rowIdx == 0 && isFirstRowSuspectedHeader)

            let cand = CandidateStudent(
                rawIndex: rowIdx + 1,
                isSelected: true, // Toutes les lignes sont pré-sélectionnées par défaut
                isSuspectedHeader: isSuspected,
                name: fullName,
                classe: cl,
                gender: gender,
                login: log,
                password: pwd,
                urlDropbox: url
            )
            list.append(cand)
        }

        self.candidates = list
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.wizardStep = 3
        }
    }

    private func initiateImportProcess() {
        let selected = candidates.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        // Détection préalable des doublons
        var conflicts: [DuplicateConflict] = []
        for cand in selected {
            let candClean = cand.name.folding(options: .diacriticInsensitive, locale: .current).lowercased().replacingOccurrences(of: " ", with: "")
            let candClass = cand.classe.lowercased().trimmingCharacters(in: .whitespaces)
            let candLogin = cand.login.lowercased().trimmingCharacters(in: .whitespaces)

            if let existing = appState.students.first(where: { ext in
                let extClean = ext.name.folding(options: .diacriticInsensitive, locale: .current).lowercased().replacingOccurrences(of: " ", with: "")
                let extClass = ext.classe.lowercased().trimmingCharacters(in: .whitespaces)
                let extLogin = ext.login.lowercased().trimmingCharacters(in: .whitespaces)

                if candClean == extClean && candClass == extClass {
                    return true
                }
                if !candLogin.isEmpty && candLogin == extLogin {
                    return true
                }
                return false
            }) {
                let reason = (!candLogin.isEmpty && existing.login.lowercased() == candLogin) ?
                    "Même identifiant : « \(existing.login) »" :
                    "Même nom (« \(existing.name) ») dans la classe « \(existing.classe) »"
                conflicts.append(DuplicateConflict(candidate: cand, existingStudent: existing, reason: reason))
            }
        }

        self.candidatesToActuallyImport = selected

        if !conflicts.isEmpty {
            self.pendingConflicts = conflicts
            self.activeConflictIndex = 0
            self.showDuplicateResolver = true
        } else {
            startProgressiveImportExecution()
        }
    }

    private func startProgressiveImportExecution() {
        let toImport = candidatesToActuallyImport
        guard !toImport.isEmpty else {
            dismiss()
            return
        }

        isImporting = true
        importTotalCount = toImport.count
        importCurrentIndex = 0
        importSuccessCount = 0
        importProgress = 0.0
        isImportFinished = false

        Task {
            var currentMaxId = appState.students.map { $0.id }.max() ?? 0

            for (idx, cand) in toImport.enumerated() {
                await MainActor.run {
                    self.importCurrentIndex = idx + 1
                    self.currentProcessingStudentName = "\(cand.name) (\(cand.classe))"
                    self.currentProcessingAction = "Génération des identifiants et configuration..."
                    self.importProgress = Double(idx) / Double(toImport.count)
                }

                currentMaxId += 1
                let login = cand.login.isEmpty ? Student.generateLogin(from: cand.name) : cand.login
                let pass = cand.password.isEmpty ? PasswordGenerator.generatePassphrase(wordCount: 2, language: appState.settings.language) : cand.password

                let student = Student(
                    id: currentMaxId,
                    name: cand.name,
                    classe: cand.classe,
                    gender: cand.gender,
                    login: login,
                    password: pass,
                    urlDropbox: cand.urlDropbox
                )

                // Création physique du dossier et lien partagé sur le Cloud
                await MainActor.run {
                    self.currentProcessingAction = "Création du dossier et du partage sur \(self.cloudName)..."
                }

                let synced = (try? await appState.storageManager.ensureSingleStudentFolder(student)) ?? student

                await MainActor.run {
                    self.appState.students.append(synced)
                    self.importSuccessCount += 1
                    self.importProgress = Double(idx + 1) / Double(toImport.count)
                }

                // Sauvegarde incrémentale dans eleves.json
                try? await appState.storageManager.saveStudents(self.appState.students)

                // Temporisation douce de 250ms pour préserver l'API Cloud (anti-rate limit)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            await MainActor.run {
                self.isImportFinished = true
                self.currentProcessingAction = "Synchronisation de la base de données terminée !"
            }

            // Pause de 2.5 secondes pour afficher le résultat, puis fermeture automatique
            try? await Task.sleep(nanoseconds: 2_500_000_000)

            await MainActor.run {
                self.isImporting = false
                dismiss()
            }
        }
    }

    // MARK: - Analyseur CSV Robuste (Guillemets, Délimiteurs multiples, Sauts de ligne)

    private func parseCSVRobust(text: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = rawLines.first else { return [] }

        let semiCount = first.filter { $0 == ";" }.count
        let commaCount = first.filter { $0 == "," }.count
        let tabCount = first.filter { $0 == "\t" }.count

        let delimiter: Character
        if semiCount >= commaCount && semiCount >= tabCount && semiCount > 0 {
            delimiter = ";"
        } else if tabCount > commaCount && tabCount > semiCount {
            delimiter = "\t"
        } else {
            delimiter = ","
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField: String = ""
        var inQuotes = false

        let chars = Array(normalized)
        var i = 0
        let len = chars.count

        while i < len {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < len && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == delimiter {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if c == "\n" {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(c)
                }
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }
}
