//
//  Step1CorrectionStudioView.swift
//  Droopies
//
//  Étape 1 : Atelier de correction au stylet (Apple Pencil + PencilKit).
//  Architecture :
//  - Dashboard Mosaïque des Paquets (Évaluations à corriger et corrigées, synchro cloud, badges).
//  - Atelier Plein Écran immersif (.fullScreenCover) :
//      * Îlot 1 (Haut Gauche) : Bouton retour chevron + Onglets des paquets ouverts (sans extension .pdf, bouton croix de fermeture).
//      * Îlot 2 (Haut Centre) : 6 Outils avec popovers dédiés (Pastille couleur 6 disques, Stylet 5 arrêts + aperçu, Surligneur 3 fluos + largeurs, Texte 4 arrêts, Tampons pédagogiques en grille, Effaceur 5 arrêts).
//      * Îlot 3 (Haut Droite) : Annuler (Undo) et Rétablir (Redo) réactifs connectés à UndoManager.
//      * Toile interactive haute résolution au centre : zoom tactile 1.0x - 4.0x, double-tap zoom/reset, swipe horizontal pour changer de page, rejet de paume matériel (Apple Pencil exclusif).
//      * Bulle HUD Page en bas à droite ("3 / 48") avec fondu auto après 1.2s, clic pour ouvrir le ruban de navigation rapide.
//      * Ruban horizontal de prévisualisation miniature pour saut direct de page.
//

import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Modèles de Données Atelier

public enum CorrectionToolType: String, CaseIterable, Equatable {
    case pencil = "Stylet"
    case highlighter = "Surligneur"
    case text = "Texte"
    case stamp = "Tampon"
    case eraser = "Effaceur"
}

public enum EvaluationStatusFilter: String, CaseIterable, Identifiable {
    case all = "Toutes"
    case pending = "À corriger"
    case inProgress = "En cours"
    case completed = "Corrigées"

    public var id: String { rawValue }
}

public struct StampDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let bgHex: String
    public let fgHex: String
}

public struct PlacedStampItem: Identifiable, Equatable {
    public let id: UUID
    public let stamp: StampDefinition
    public var xRatio: CGFloat // 0.0 ... 1.0 coordonnée relative à la largeur
    public var yRatio: CGFloat // 0.0 ... 1.0 coordonnée relative à la hauteur

    public init(id: UUID = UUID(), stamp: StampDefinition, xRatio: CGFloat = 0.5, yRatio: CGFloat = 0.5) {
        self.id = id
        self.stamp = stamp
        self.xRatio = xRatio
        self.yRatio = yRatio
    }
}

public struct PlacedTextItem: Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var fontSize: CGFloat
    public var colorHex: String
    public var xRatio: CGFloat
    public var yRatio: CGFloat

    public init(id: UUID = UUID(), text: String, fontSize: CGFloat = 16, colorHex: String = "EF4444", xRatio: CGFloat = 0.5, yRatio: CGFloat = 0.5) {
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.xRatio = xRatio
        self.yRatio = yRatio
    }
}

private struct StudioColorOption: Identifiable {
    let id: String
    let name: String
    let color: Color
    let hex: String
}

private struct PencilWidthStop {
    let label: String
    let width: CGFloat
}

private struct FluoColorOption: Identifiable {
    let id: String
    let name: String
    let color: Color
    #if canImport(UIKit)
    let uiColor: UIColor
    #elseif canImport(AppKit)
    let nsColor: NSColor
    #endif
}

private struct TextSizeStop {
    let label: String
    let size: CGFloat
}

private struct EraserWidthStop {
    let label: String
    let width: CGFloat
}

// MARK: - Vue Principale : Step1CorrectionStudioView

public struct Step1CorrectionStudioView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int
    public var onDistributeScan: ((StorageManager.ScanItem) -> Void)? = nil

    // État Mosaïque Dashboard
    private var availableScans: [StorageManager.ScanItem] { appState.availableScans }
    @State private var searchQuery: String = ""
    @State private var selectedClassFilter: String = "Toutes"
    @State private var selectedStatusFilter: EvaluationStatusFilter = .all
    @State private var showMarkedToast: String? = nil
    @State private var isLoadingScans: Bool = false
    @State private var importSuccessToast: String? = nil
    @State private var scanPendingReset: StorageManager.ScanItem? = nil
    @State private var scanPendingDistribution: StorageManager.ScanItem? = nil
    @State private var processingScanId: String? = nil
    @State private var scanSyncStatuses: [String: ScanSyncStatus] = [:]
    @State private var isCheckingCloud: Bool = false
    @State private var thumbnailCacheVersion: UUID = UUID()
    @State private var thumbnailUpdateTask: Task<Void, Never>? = nil

    // MARK: - État Atelier de Correction Intégré (Non-Modal)
    @State private var pdfURL: URL? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var currentPageIndex: Int = 0
    @State private var currentDrawing: PKDrawing = PKDrawing()

    // Mémoire des annotations par paquet et par page
    @State private var scanDrawings: [String: [Int: PKDrawing]] = [:]
    @State private var scanStamps: [String: [Int: [PlacedStampItem]]] = [:]
    @State private var scanTexts: [String: [Int: [PlacedTextItem]]] = [:]

    // Moteur d'Historique Unifié (Pencil + Surligneur + Tampons + Textes)
    @State private var scanUndoStacks: [String: [CorrectionAction]] = [:]
    @State private var scanRedoStacks: [String: [CorrectionAction]] = [:]
    @State private var isPerformingUndoRedo: Bool = false

    // Outils actifs
    @State private var activeTool: CorrectionToolType = .pencil
    @State private var activeColor: Color = Color(hex: "EF4444") // Rouge par défaut
    @State private var pencilWidthIndex: Int = 1 // Fin (3.0 pt)
    @State private var highlighterColorIndex: Int = 0 // Jaune fluo
    @State private var highlighterWidthIndex: Int = 1 // Moyen (20 pt)
    @State private var textFontSizeIndex: Int = 1 // Moyen (16 pt)
    @State private var eraserWidthIndex: Int = 2 // Moyen (20 pt)

    // Popovers
    @State private var isColorPopoverPresented: Bool = false
    @State private var isPencilPopoverPresented: Bool = false
    @State private var isHighlighterPopoverPresented: Bool = false
    @State private var isTextPopoverPresented: Bool = false
    @State private var isStampPopoverPresented: Bool = false
    @State private var isEraserPopoverPresented: Bool = false

    // Dock vertical position & préférence gaucher/droitier
    @AppStorage("droopies_annotation_dock_on_right") private var isDockOnRight: Bool = false
    @State private var dockDragTranslationX: CGFloat = 0

    // Page HUD & Scrubber
    @State private var isPageHUDVisible: Bool = false
    @State private var showThumbnailScrubber: Bool = false
    @State private var pageHUDTask: Task<Void, Never>? = nil

    // Dialogue d'ajout / édition de texte
    @State private var newTextAlertPresented: Bool = false
    @State private var textAlertInput: String = ""
    @State private var editingTextId: UUID? = nil

    // Définitions des palettes et options d'outils
    private let studioColors: [StudioColorOption] = [
        StudioColorOption(id: "noir", name: "Noir", color: Color(hex: "1F2937"), hex: "1F2937"),
        StudioColorOption(id: "rouge", name: "Rouge", color: Color(hex: "EF4444"), hex: "EF4444"),
        StudioColorOption(id: "violet", name: "Violet", color: Color(hex: "8B5CF6"), hex: "8B5CF6"),
        StudioColorOption(id: "bleu", name: "Bleu", color: Color(hex: "3B82F6"), hex: "3B82F6"),
        StudioColorOption(id: "vert", name: "Vert", color: Color(hex: "10B981"), hex: "10B981"),
        StudioColorOption(id: "jaune", name: "Jaune", color: Color(hex: "F59E0B"), hex: "F59E0B")
    ]

    private let pencilStops: [PencilWidthStop] = [
        PencilWidthStop(label: "Très fin", width: 1.5),
        PencilWidthStop(label: "Fin", width: 3.0),
        PencilWidthStop(label: "Moyen", width: 5.0),
        PencilWidthStop(label: "Épais", width: 8.0),
        PencilWidthStop(label: "Très épais", width: 12.0)
    ]

    #if canImport(UIKit)
    private let fluoColors: [FluoColorOption] = [
        FluoColorOption(id: "jaune", name: "Jaune fluo", color: Color(hex: "FACC15"), uiColor: UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 0.60)),
        FluoColorOption(id: "vert", name: "Vert fluo", color: Color(hex: "4ADE80"), uiColor: UIColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 0.60)),
        FluoColorOption(id: "rose", name: "Rose fluo", color: Color(hex: "FB7185"), uiColor: UIColor(red: 251/255, green: 113/255, blue: 133/255, alpha: 0.60))
    ]
    #elseif canImport(AppKit)
    private let fluoColors: [FluoColorOption] = [
        FluoColorOption(id: "jaune", name: "Jaune fluo", color: Color(hex: "FACC15"), nsColor: NSColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 0.60)),
        FluoColorOption(id: "vert", name: "Vert fluo", color: Color(hex: "4ADE80"), nsColor: NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 0.60)),
        FluoColorOption(id: "rose", name: "Rose fluo", color: Color(hex: "FB7185"), nsColor: NSColor(red: 251/255, green: 113/255, blue: 133/255, alpha: 0.60))
    ]
    #endif

    private let highlighterWidths: [CGFloat] = [12.0, 20.0, 32.0]
    private let highlighterLabels: [String] = ["Fin (12pt)", "Moyen (20pt)", "Large (32pt)"]

    private let textStops: [TextSizeStop] = [
        TextSizeStop(label: "Petit", size: 13),
        TextSizeStop(label: "Moyen", size: 16),
        TextSizeStop(label: "Grand", size: 20),
        TextSizeStop(label: "Très grand", size: 26)
    ]

    private let eraserStops: [EraserWidthStop] = [
        EraserWidthStop(label: "Très fin", width: 6.0),
        EraserWidthStop(label: "Fin", width: 12.0),
        EraserWidthStop(label: "Moyen", width: 20.0),
        EraserWidthStop(label: "Épais", width: 32.0),
        EraserWidthStop(label: "Très épais", width: 50.0)
    ]

    private let availableStamps: [StampDefinition] = [
        StampDefinition(id: "excellent", title: "Excellent !", icon: "star.fill", bgHex: "10B981", fgHex: "FFFFFF"),
        StampDefinition(id: "tres_bien", title: "Très bien", icon: "hand.thumbsup.fill", bgHex: "3B82F6", fgHex: "FFFFFF"),
        StampDefinition(id: "soin", title: "Soin à revoir", icon: "exclamationmark.triangle.fill", bgHex: "F59E0B", fgHex: "FFFFFF"),
        StampDefinition(id: "calcul", title: "Erreur calcul", icon: "xmark.circle.fill", bgHex: "EF4444", fgHex: "FFFFFF"),
        StampDefinition(id: "justifier", title: "Justifier !", icon: "questionmark.circle.fill", bgHex: "8B5CF6", fgHex: "FFFFFF"),
        StampDefinition(id: "incomplet", title: "Incomplet", icon: "doc.text.badge.plus", bgHex: "EC4899", fgHex: "FFFFFF"),
        StampDefinition(id: "vu", title: "Vu 👀", icon: "eye.fill", bgHex: "64748B", fgHex: "FFFFFF"),
        StampDefinition(id: "note_max", title: "20 / 20", icon: "sparkles", bgHex: "D97706", fgHex: "FFFFFF")
    ]

    private func currentSyncStatus(for scan: StorageManager.ScanItem) -> ScanSyncStatus {
        if let localStatus = scanSyncStatuses[scan.name] {
            return localStatus
        }
        if let engineStatus = OfflineSyncEngine.shared.fileSyncStatuses[scan.name] {
            return engineStatus
        }
        return appState.isOnline ? .synced : .offline
    }

    public init(
        appState: AppState,
        currentStep: Binding<Int>,
        onDistributeScan: ((StorageManager.ScanItem) -> Void)? = nil
    ) {
        self.appState = appState
        self._currentStep = currentStep
        self.onDistributeScan = onDistributeScan

        let cached = appState.availableScans.isEmpty ? appState.storageManager.listLocalScansSync() : appState.availableScans
        var statuses: [String: ScanSyncStatus] = [:]
        for item in cached {
            statuses[item.name] = appState.isOnline ? .synced : .offline
        }
        self._scanSyncStatuses = State(initialValue: statuses)
        self._isCheckingCloud = State(initialValue: false)
    }

    private var totalPages: Int {
        pdfDocument?.pageCount ?? 0
    }

    // MARK: - Détection de Classe & Filtrage Mosaïque

    private func detectClass(from fileName: String) -> String? {
        let baseName = fileName.replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive])
        let sortedClasses = appState.classes.sorted { $0.name.count > $1.name.count }

        for cls in sortedClasses {
            let rawName = cls.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { continue }

            var variations: [String] = [
                rawName,
                rawName.replacingOccurrences(of: " ", with: "_"),
                rawName.replacingOccurrences(of: " ", with: "-"),
                rawName.replacingOccurrences(of: " ", with: "")
            ]

            if let regexNumLet = try? NSRegularExpression(pattern: "^(\\d+e)(\\d+|[A-Za-z])$", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: rawName.utf16.count)
                if let match = regexNumLet.firstMatch(in: rawName, options: [], range: range) {
                    if let r1 = Range(match.range(at: 1), in: rawName),
                       let r2 = Range(match.range(at: 2), in: rawName) {
                        let part1 = String(rawName[r1])
                        let part2 = String(rawName[r2])
                        variations.append("\(part1) \(part2)")
                        variations.append("\(part1)_\(part2)")
                        variations.append("\(part1)-\(part2)")
                    }
                }
            }

            for variation in Set(variations) {
                let escaped = NSRegularExpression.escapedPattern(for: variation)
                let pattern = "(?i)(?:^|[\\s_\\-\\.\\[\\]()#])" + escaped + "(?:$|[\\s_\\-\\.\\[\\]()#])"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(location: 0, length: baseName.utf16.count)
                    if regex.firstMatch(in: baseName, options: [], range: range) != nil {
                        return cls.name
                    }
                }
            }
        }

        return nil
    }

    private func countForClass(_ className: String) -> Int {
        availableScans.filter { detectClass(from: $0.rawFileName) == className }.count
    }

    private var filteredEvaluations: [StorageManager.ScanItem] {
        var list = availableScans

        // 1. Filtre par recherche textuelle
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.cleanTitle.lowercased().contains(query) ||
                $0.name.lowercased().contains(query)
            }
        }

        // 2. Filtre par classe
        if selectedClassFilter != "Toutes" {
            list = list.filter { scan in
                detectClass(from: scan.rawFileName) == selectedClassFilter
            }
        }

        // 3. Filtre par statut
        switch selectedStatusFilter {
        case .all:
            break
        case .pending:
            list = list.filter { scan in
                let meta = appState.evaluationsMetadata[scan.rawFileName]
                let isEffectivelyDone = scan.isCorrected || meta?.isEffectivelyCompleted == true
                let percent = meta?.progressPercent ?? 0
                let hasAnnotation = (meta?.maxAnnotatedPage ?? 0) > 0
                return !isEffectivelyDone && percent == 0 && !hasAnnotation
            }
        case .inProgress:
            list = list.filter { scan in
                let meta = appState.evaluationsMetadata[scan.rawFileName]
                let isEffectivelyDone = scan.isCorrected || meta?.isEffectivelyCompleted == true
                let percent = meta?.progressPercent ?? 0
                let hasAnnotation = (meta?.maxAnnotatedPage ?? 0) > 0
                return !isEffectivelyDone && (percent > 0 || hasAnnotation)
            }
        case .completed:
            list = list.filter { scan in
                let meta = appState.evaluationsMetadata[scan.rawFileName]
                return scan.isCorrected || meta?.isEffectivelyCompleted == true
            }
        }

        // Tri alphabétique naturel (style Finder, ex. DS 2 avant DS 10)
        return list.sorted {
            $0.cleanTitle.localizedStandardCompare($1.cleanTitle) == .orderedAscending
        }
    }

    private var responsiveGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 270), spacing: 16)]
    }

    // MARK: - Vue Principale (Mosaïque ou Atelier Intégré)

    public var body: some View {
        ZStack {
            if let activeScan = appState.activeCorrectionScan, let doc = pdfDocument {
                // MARK: - Atelier de Correction Intégré (Non-modal)
                activeGradingStudioView(scan: activeScan, document: doc)
            } else if appState.activeCorrectionScan != nil {
                // État de chargement bref de la copie
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Chargement de la copie...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // MARK: - Page d'Accueil : Mosaïque des Paquets de Copies
                correctionHomeDashboardView
            }

            // Toast de confirmation d'importation
            if let toast = importSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(50)
            }
        }
        .task {
            let autoOpen = CommandLine.arguments.contains("-testOpenScan")
            let multiTabs = CommandLine.arguments.contains("-testMultipleTabs")
            let twoTabs = CommandLine.arguments.contains("-testTwoTabs")
            if (multiTabs || twoTabs) && appState.openCorrectionScans.isEmpty {
                let scans = appState.storageManager.listLocalScansSync()
                let countToTake = twoTabs ? 2 : 3
                for scan in scans.prefix(countToTake) {
                    if !appState.openCorrectionScans.contains(where: { $0.id == scan.id }) {
                        appState.openCorrectionScans.append(scan)
                    }
                }
                if appState.activeCorrectionScan == nil, let first = scans.first {
                    openScanInStudio(first)
                }
            }
            await refreshAvailableScans(autoSelectFirst: autoOpen)
            if CommandLine.arguments.contains("-testDockRight") {
                isDockOnRight = true
            } else if CommandLine.arguments.contains("-testDockLeft") {
                isDockOnRight = false
            }
            if CommandLine.arguments.contains("-testScrubber") {
                showThumbnailScrubber = true
            }
            if CommandLine.arguments.contains("-testStampPopover") {
                isStampPopoverPresented = true
            }
            if let active = appState.activeCorrectionScan {
                loadScanPDF(active)
            }
        }
        .onChange(of: appState.activeCorrectionScan) { oldScan, newScan in
            if oldScan?.name != newScan?.name {
                saveCurrentDrawing()
                if let newScan = newScan {
                    loadScanPDF(newScan)
                    triggerPageHUD()
                } else {
                    pdfDocument = nil
                    pdfURL = nil
                    appState.canUndoCorrection = false
                    appState.canRedoCorrection = false
                }
            }
        }
        .onChange(of: appState.undoCorrectionTrigger) { _, _ in
            performUndo()
        }
        .onChange(of: appState.redoCorrectionTrigger) { _, _ in
            performRedo()
        }
        .onChange(of: appState.isOnline) { _, _ in
            Task {
                await refreshAvailableScans(autoSelectFirst: false, forceCloud: true)
            }
        }
        .fileImporter(
            isPresented: $appState.showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                handleImportedPDFs(urls)
            case .failure(let error):
                appState.errorMessage = "Erreur d'importation : \(error.localizedDescription)"
            }
        }
        .alert(
            "Réinitialiser la progression ?",
            isPresented: Binding(
                get: { scanPendingReset != nil },
                set: { if !$0 { scanPendingReset = nil } }
            ),
            presenting: scanPendingReset
        ) { scan in
            Button("Réinitialiser", role: .destructive) {
                let target = scan
                scanPendingReset = nil
                appState.resetEvaluationProgress(for: target.rawFileName)
            }
            Button("Annuler", role: .cancel) {
                scanPendingReset = nil
            }
        } message: { scan in
            Text("Voulez-vous remettre à zéro la progression de correction pour « \(scan.cleanTitle) » ?")
        }
        .alert(
            "Distribuer cette évaluation ?",
            isPresented: Binding(
                get: { scanPendingDistribution != nil },
                set: { if !$0 { scanPendingDistribution = nil } }
            ),
            presenting: scanPendingDistribution
        ) { scan in
            Button("Distribuer") {
                let target = scan
                scanPendingDistribution = nil
                onDistributeScan?(target)
            }
            Button("Annuler", role: .cancel) {
                scanPendingDistribution = nil
            }
        } message: { scan in
            Text("Voulez-vous passer à la distribution des copies pour « \(scan.cleanTitle) » ?")
        }
    }

    // MARK: - 0. Page d'Accueil Mosaïque (Dashboard Épuré 100% HIG avec Barre de Filtre)

    private var correctionHomeDashboardView: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 960

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // MARK: - Barre de Filtre Unifiée : Recherche, Classes & Statut
                    evaluationsFilterBar(isCompact: isCompact)
                        .padding(.horizontal, 24)
                        #if os(iOS)
                        .padding(.top, 8)
                        #else
                        .padding(.top, 12)
                        #endif

                    if availableScans.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text("Aucune évaluation disponible")
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                            Text("Importez un document PDF de copies ou synchronisez votre dossier Cloud.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredEvaluations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Aucune évaluation trouvée")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Aucun devoir ne correspond à votre recherche ou aux filtres sélectionnés.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button("Réinitialiser les filtres") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    searchQuery = ""
                                    selectedClassFilter = "Toutes"
                                    selectedStatusFilter = .all
                                }
                            }
                            .buttonStyle(.bordered)
                            .clipShape(Capsule())
                            .padding(.top, 4)
                        }
                        .padding(48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LazyVGrid(columns: responsiveGridColumns, spacing: 20) {
                            ForEach(filteredEvaluations) { scan in
                                EvaluationScanCard(
                                    scan: scan,
                                    metadata: appState.evaluationsMetadata[scan.rawFileName],
                                    fileURL: appState.storageManager.localURL(for: scan.path),
                                    isProcessing: processingScanId == scan.name,
                                    syncStatus: currentSyncStatus(for: scan),
                                    updateToken: thumbnailCacheVersion,
                                    onOpen: {
                                        openScanInStudio(scan)
                                    },
                                    onReset: {
                                        scanPendingReset = scan
                                    },
                                    onDistribute: {
                                        scanPendingDistribution = scan
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .refreshable {
                await refreshAvailableScans(autoSelectFirst: false, forceCloud: true)
            }
            .background(Color.clear)
        }
    }

    // MARK: - Barre Unifiée : Recherche, Filtre Classes & Statut (Style A : Segmented)

    private func evaluationsFilterBar(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            // MARK: - 1. Champ de Recherche à gauche
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField(isCompact ? "Rechercher..." : "Rechercher une évaluation...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(width: isCompact ? 160 : 220)

            Divider()
                .frame(height: 18)
                .opacity(0.4)

            // MARK: - 2. Sélecteur de classes (Capsules en paysage, Menu compact en portrait)
            if isCompact && appState.classes.count > 3 {
                Menu {
                    Button {
                        selectedClassFilter = "Toutes"
                    } label: {
                        HStack {
                            Text("Toutes les classes (\(availableScans.count))")
                            if selectedClassFilter == "Toutes" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(appState.classes) { group in
                        let count = countForClass(group.name)
                        Button {
                            selectedClassFilter = group.name
                        } label: {
                            HStack {
                                Text("\(group.name) (\(count))")
                                if selectedClassFilter == group.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)

                        let currentCount = selectedClassFilter == "Toutes" ? availableScans.count : countForClass(selectedClassFilter)
                        Text(selectedClassFilter == "Toutes" ? "Toutes les classes" : "Classe : \(selectedClassFilter)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("\(currentCount)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        classFilterChip(title: "Toutes", count: availableScans.count)

                        ForEach(appState.classes) { group in
                            classFilterChip(title: group.name, count: countForClass(group.name))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 4)

            // MARK: - 3. Filtre de Statut (Style A : Picker Segmenté HIG)
            Picker("Statut", selection: $selectedStatusFilter) {
                ForEach(EvaluationStatusFilter.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: isCompact ? 280 : 320)
        }
    }

    @ViewBuilder
    private func classFilterChip(title: String, count: Int) -> some View {
        let isSelected = selectedClassFilter == title
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedClassFilter = title
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .bold : .medium)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.blue : Color.primary.opacity(0.06))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ==========================================
    // MARK: - ATELIER DE CORRECTION INTÉGRÉ (NON-MODAL)
    // MARK: - ==========================================

    @ViewBuilder
    private func activeGradingStudioView(scan: StorageManager.ScanItem, document: PDFDocument) -> some View {
        ZStack {
            // 1. Toile Interactive PDF + Stylet Apple Pencil + Zoom tactile
            InteractivePDFCanvasView(
                document: document,
                pageIndex: currentPageIndex,
                drawing: $currentDrawing,
                tool: activeTool,
                activeColor: activeColor,
                pencilWidth: pencilStops[pencilWidthIndex].width,
                highlighterColor: fluoColors[highlighterColorIndex].color,
                highlighterWidth: highlighterWidths[highlighterWidthIndex],
                eraserWidth: eraserStops[eraserWidthIndex].width,
                stamps: currentStampsForActivePage,
                texts: currentTextsForActivePage,
                isPerformingUndoRedo: isPerformingUndoRedo,
                onStrokeFinished: { oldDrawing, newDrawing in
                    recordAction(.strokeDrawing(pageIndex: currentPageIndex, oldDrawing: oldDrawing, newDrawing: newDrawing))
                    currentDrawing = newDrawing
                    saveCurrentDrawing()
                    appState.updateEvaluationProgress(for: scan.rawFileName, annotatedPage: currentPageIndex + 1, totalPages: totalPages)
                },
                onUpdateStamp: { updated, oldX, oldY in
                    if abs(oldX - updated.xRatio) > 0.001 || abs(oldY - updated.yRatio) > 0.001 {
                        recordAction(.moveStamp(pageIndex: currentPageIndex, id: updated.id, fromX: oldX, fromY: oldY, toX: updated.xRatio, toY: updated.yRatio))
                    }
                    updatePlacedStamp(updated)
                },
                onDeleteStamp: { stampId in
                    deletePlacedStamp(id: stampId)
                },
                onUpdateText: { updated, oldX, oldY in
                    if abs(oldX - updated.xRatio) > 0.001 || abs(oldY - updated.yRatio) > 0.001 {
                        recordAction(.moveText(pageIndex: currentPageIndex, id: updated.id, fromX: oldX, fromY: oldY, toX: updated.xRatio, toY: updated.yRatio))
                    }
                    updatePlacedText(updated)
                },
                onDeleteText: { textId in
                    deletePlacedText(id: textId)
                },
                onTapText: { item in
                    textAlertInput = item.text
                    editingTextId = item.id
                    newTextAlertPresented = true
                },
                onNextPage: {
                    if currentPageIndex < totalPages - 1 {
                        changePage(to: currentPageIndex + 1)
                    }
                },
                onPreviousPage: {
                    if currentPageIndex > 0 {
                        changePage(to: currentPageIndex - 1)
                    }
                }
            )
            .ignoresSafeArea()
            .onChange(of: currentDrawing) { _, newDrawing in
                guard currentPageIndex == 0, let url = pdfURL else { return }
                schedulePage0ThumbnailUpdate(doc: document, url: url, drawing: newDrawing)
            }

            // 2. Dock Vertical d'Annotation Flottant (Liquid Glass, déplaçable Gauche ↔ Droite)
            verticalAnnotationDock

            // 3. Bulle HUD Numéro de Page (Bas Droite, "3 / 48")
            pageHUDOverlay

            // 4. Ruban horizontal de navigation rapide (Scrubber)
            if showThumbnailScrubber {
                thumbnailScrubberBar(document: document)
            }
        }
        .alert(editingTextId == nil ? "Nouvelle annotation texte" : "Modifier l'annotation", isPresented: $newTextAlertPresented) {
            TextField("Votre remarque ou note...", text: $textAlertInput)
            Button(editingTextId == nil ? "Ajouter sur la copie" : "Valider") {
                let trimmed = textAlertInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let editId = editingTextId {
                        updateTextContent(id: editId, newText: trimmed)
                    } else {
                        addTextAnnotation(trimmed)
                    }
                }
                textAlertInput = ""
                editingTextId = nil
            }
            Button("Annuler", role: .cancel) {
                textAlertInput = ""
                editingTextId = nil
            }
        }
    }

    // MARK: - Dock Vertical d'Annotations Flottant (Liquid Glass & Draggable)

    private var verticalAnnotationDock: some View {
        HStack {
            if isDockOnRight {
                Spacer()
            }

            VStack(spacing: 8) {
                // Poignée de déplacement et bouton bascule Gauche/Droite
                dockFlipHandle

                Divider()
                    .frame(width: 24)
                    .opacity(0.3)

                // 1. Bouton Pastille de Couleur Active
                Button {
                    isColorPopoverPresented.toggle()
                } label: {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: activeColor.opacity(0.4), radius: 3)
                }
                .buttonStyle(.plain)
                .help("Palette de couleurs")
                .popover(isPresented: $isColorPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    colorPalettePopoverContent
                }

                // 2. Bouton Stylet Apple Pencil
                Button {
                    activeTool = .pencil
                    isPencilPopoverPresented.toggle()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activeTool == .pencil ? .blue : .primary)
                        .frame(width: 32, height: 32)
                        .background(activeTool == .pencil ? Color.blue.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Stylet Apple Pencil")
                .popover(isPresented: $isPencilPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    pencilPopoverContent
                }

                // 3. Bouton Surligneur fluo
                Button {
                    activeTool = .highlighter
                    isHighlighterPopoverPresented.toggle()
                } label: {
                    Image(systemName: "highlighter")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activeTool == .highlighter ? Color(hex: "FACC15") : .primary)
                        .frame(width: 32, height: 32)
                        .background(activeTool == .highlighter ? Color.yellow.opacity(0.22) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Surligneur fluo")
                .popover(isPresented: $isHighlighterPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    highlighterPopoverContent
                }

                // 4. Bouton Texte dactylographié
                Button {
                    activeTool = .text
                    isTextPopoverPresented.toggle()
                } label: {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activeTool == .text ? .blue : .primary)
                        .frame(width: 32, height: 32)
                        .background(activeTool == .text ? Color.blue.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Ajouter une annotation texte")
                .popover(isPresented: $isTextPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    textPopoverContent
                }

                // 5. Bouton Tampon / Sticker
                Button {
                    activeTool = .stamp
                    isStampPopoverPresented.toggle()
                } label: {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activeTool == .stamp ? Color(hex: "10B981") : .primary)
                        .frame(width: 32, height: 32)
                        .background(activeTool == .stamp ? Color(hex: "10B981").opacity(0.22) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Tampons et stickers d'évaluation")
                .popover(isPresented: $isStampPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    stampPopoverContent
                }

                // 6. Bouton Effaceur / Gomme
                Button {
                    activeTool = .eraser
                    isEraserPopoverPresented.toggle()
                } label: {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activeTool == .eraser ? .red : .primary)
                        .frame(width: 32, height: 32)
                        .background(activeTool == .eraser ? Color.red.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Gomme / Effaceur")
                .popover(isPresented: $isEraserPopoverPresented, arrowEdge: isDockOnRight ? .trailing : .leading) {
                    eraserPopoverContent
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .glassCapsule(strokeOpacity: 0.4)
            .shadow(color: Color.black.opacity(0.16), radius: 12, x: isDockOnRight ? -3 : 3, y: 4)
            .offset(x: dockDragTranslationX)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dockDragTranslationX = value.translation.width
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if !isDockOnRight && value.translation.width > 80 {
                                isDockOnRight = true
                            } else if isDockOnRight && value.translation.width < -80 {
                                isDockOnRight = false
                            }
                            dockDragTranslationX = 0
                        }
                    }
            )
            .padding(.horizontal, 16)

            if !isDockOnRight {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private var dockFlipHandle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isDockOnRight.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 18, height: 3.5)
                Image(systemName: isDockOnRight ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 28, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isDockOnRight ? "Déplacer la barre d'outils à gauche" : "Déplacer la barre d'outils à droite (pour gauchers)")
    }

    // MARK: - Popovers pour chacun des outils

    private var colorPalettePopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couleur active")
                .font(.system(size: 13, weight: .bold))

            HStack(spacing: 10) {
                ForEach(studioColors) { opt in
                    Button {
                        activeColor = opt.color
                        isColorPopoverPresented = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(opt.color)
                                .frame(width: 32, height: 32)
                                .shadow(color: opt.color.opacity(0.4), radius: 3, y: 1)

                            if activeColor == opt.color {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2.5)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(opt.name)
                }
            }
        }
        .padding(14)
    }

    private var pencilPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stylet Pencil :")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(pencilStops[pencilWidthIndex].label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)
            }

            Slider(
                value: Binding(
                    get: { Double(pencilWidthIndex) },
                    set: { pencilWidthIndex = Int(round($0)) }
                ),
                in: 0...4,
                step: 1
            )
            .tint(.blue)

            HStack {
                Text("Très fin (1.5pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Très épais (12pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Aperçu du trait")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 38)

                    RoundedRectangle(cornerRadius: pencilStops[pencilWidthIndex].width / 2)
                        .fill(activeColor)
                        .frame(width: 140, height: pencilStops[pencilWidthIndex].width)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var highlighterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couleur fluo")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 12) {
                #if canImport(UIKit)
                ForEach(0..<fluoColors.count, id: \.self) { idx in
                    let opt = fluoColors[idx]
                    Button {
                        highlighterColorIndex = idx
                    } label: {
                        ZStack {
                            Circle()
                                .fill(opt.color)
                                .frame(width: 32, height: 32)
                                .shadow(color: opt.color.opacity(0.4), radius: 3, y: 1)

                            if highlighterColorIndex == idx {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(opt.name)
                }
                #endif
            }

            Divider()

            HStack {
                Text("Largeur :")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(highlighterLabels[highlighterWidthIndex])
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
            }

            Slider(
                value: Binding(
                    get: { Double(highlighterWidthIndex) },
                    set: { highlighterWidthIndex = Int(round($0)) }
                ),
                in: 0...2,
                step: 1
            )
            .tint(.yellow)
        }
        .padding(14)
        .frame(width: 250)
    }

    private var textPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Taille du texte :")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(textStops[textFontSizeIndex].label) (\(Int(textStops[textFontSizeIndex].size))pt)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)
            }

            Slider(
                value: Binding(
                    get: { Double(textFontSizeIndex) },
                    set: { textFontSizeIndex = Int(round($0)) }
                ),
                in: 0...3,
                step: 1
            )
            .tint(.blue)

            HStack {
                Text("Petit (13pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Très grand (26pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                isTextPopoverPresented = false
                textAlertInput = ""
                editingTextId = nil
                newTextAlertPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Ajouter une note de texte")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(LinearGradient.electricBlue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 270)
    }

    private var stampPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tampons d'évaluation")
                .font(.system(size: 13, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(availableStamps) { stamp in
                    Button {
                        addStamp(stamp)
                        isStampPopoverPresented = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: stamp.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(stamp.title)
                                .font(.system(size: 11.5, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(hex: stamp.bgHex))
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: stamp.bgHex).opacity(0.35), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var eraserPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gomme :")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(eraserStops[eraserWidthIndex].label) (\(Int(eraserStops[eraserWidthIndex].width))pt)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)
            }

            Slider(
                value: Binding(
                    get: { Double(eraserWidthIndex) },
                    set: { eraserWidthIndex = Int(round($0)) }
                ),
                in: 0...4,
                step: 1
            )
            .tint(.red)

            HStack {
                Text("Très fin (6pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Très large (50pt)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Aperçu diamètre")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 58)

                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                        .frame(width: eraserStops[eraserWidthIndex].width, height: eraserStops[eraserWidthIndex].width)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - Bulle HUD Page en Bas à Droite ("3 / 48")

    private var pageHUDOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showThumbnailScrubber.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(currentPageIndex + 1) / \(totalPages)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial.opacity(0.85))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .opacity(isPageHUDVisible || showThumbnailScrubber ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 0.25), value: isPageHUDVisible)
                .padding(.trailing, 24)
                .padding(.bottom, showThumbnailScrubber ? 140 : 24)
            }
        }
    }

    // MARK: - Ruban Horizontal de Navigation Rapide (Scrubber)

    private func thumbnailScrubberBar(document: PDFDocument) -> some View {
        VStack(spacing: 8) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 13))
                        Text("Saut direct de page (1 à \(totalPages))")
                            .font(.system(size: 13, weight: .bold))
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showThumbnailScrubber = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(0..<totalPages, id: \.self) { idx in
                            Button {
                                changePage(to: idx)
                                withAnimation {
                                    showThumbnailScrubber = false
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    PageThumbnailMiniView(doc: document, pageIndex: idx)
                                        .frame(width: 64, height: 86)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(idx == currentPageIndex ? Color.blue : Color.primary.opacity(0.15), lineWidth: idx == currentPageIndex ? 2.5 : 1)
                                        )
                                        .shadow(color: idx == currentPageIndex ? Color.blue.opacity(0.3) : .clear, radius: 4)

                                    Text("\(idx + 1)")
                                        .font(.system(size: 11, weight: idx == currentPageIndex ? .bold : .medium))
                                        .foregroundColor(idx == currentPageIndex ? .blue : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .frame(height: 110)
            }
            .frame(maxWidth: 640)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(40)
    }

    // MARK: - Actions & Logique Métier

    private var activeScanName: String {
        appState.activeCorrectionScan?.name ?? ""
    }

    private var currentStampsForActivePage: [PlacedStampItem] {
        let name = activeScanName
        guard !name.isEmpty else { return [] }
        return scanStamps[name]?[currentPageIndex] ?? []
    }

    private var currentTextsForActivePage: [PlacedTextItem] {
        let name = activeScanName
        guard !name.isEmpty else { return [] }
        return scanTexts[name]?[currentPageIndex] ?? []
    }

    // MARK: - Moteur d'Historique Unifié (Tracés Pencil + Surligneur + Tampons + Textes)

    private enum CorrectionAction {
        case strokeDrawing(pageIndex: Int, oldDrawing: PKDrawing, newDrawing: PKDrawing)
        case addStamp(pageIndex: Int, stamp: PlacedStampItem)
        case deleteStamp(pageIndex: Int, stamp: PlacedStampItem)
        case moveStamp(pageIndex: Int, id: UUID, fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat)
        case addText(pageIndex: Int, text: PlacedTextItem)
        case deleteText(pageIndex: Int, text: PlacedTextItem)
        case editText(pageIndex: Int, id: UUID, oldText: String, newText: String)
        case moveText(pageIndex: Int, id: UUID, fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat)
    }

    private func recordAction(_ action: CorrectionAction) {
        let name = activeScanName
        guard !name.isEmpty else { return }
        if scanUndoStacks[name] == nil { scanUndoStacks[name] = [] }
        scanUndoStacks[name]?.append(action)
        scanRedoStacks[name]?.removeAll()
        syncUndoRedoState()
    }

    private func performUndo() {
        let name = activeScanName
        guard !name.isEmpty, var undoStack = scanUndoStacks[name], let action = undoStack.popLast() else { return }
        scanUndoStacks[name] = undoStack

        if scanRedoStacks[name] == nil { scanRedoStacks[name] = [] }
        scanRedoStacks[name]?.append(action)

        applyAction(action, isUndo: true)
        syncUndoRedoState()
    }

    private func performRedo() {
        let name = activeScanName
        guard !name.isEmpty, var redoStack = scanRedoStacks[name], let action = redoStack.popLast() else { return }
        scanRedoStacks[name] = redoStack

        if scanUndoStacks[name] == nil { scanUndoStacks[name] = [] }
        scanUndoStacks[name]?.append(action)

        applyAction(action, isUndo: false)
        syncUndoRedoState()
    }

    private func syncUndoRedoState() {
        let name = activeScanName
        appState.canUndoCorrection = !(scanUndoStacks[name]?.isEmpty ?? true)
        appState.canRedoCorrection = !(scanRedoStacks[name]?.isEmpty ?? true)
    }

    private func applyAction(_ action: CorrectionAction, isUndo: Bool) {
        let name = activeScanName
        guard !name.isEmpty else { return }

        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }

        switch action {
        case .strokeDrawing(let pageIndex, let oldDrawing, let newDrawing):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            let targetDrawing = isUndo ? oldDrawing : newDrawing
            currentDrawing = targetDrawing
            if scanDrawings[name] == nil { scanDrawings[name] = [:] }
            scanDrawings[name]?[pageIndex] = targetDrawing

        case .addStamp(let pageIndex, let stamp):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if isUndo {
                scanStamps[name]?[pageIndex]?.removeAll(where: { $0.id == stamp.id })
            } else {
                if scanStamps[name] == nil { scanStamps[name] = [:] }
                if scanStamps[name]?[pageIndex] == nil { scanStamps[name]?[pageIndex] = [] }
                scanStamps[name]?[pageIndex]?.append(stamp)
            }

        case .deleteStamp(let pageIndex, let stamp):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if isUndo {
                if scanStamps[name] == nil { scanStamps[name] = [:] }
                if scanStamps[name]?[pageIndex] == nil { scanStamps[name]?[pageIndex] = [] }
                scanStamps[name]?[pageIndex]?.append(stamp)
            } else {
                scanStamps[name]?[pageIndex]?.removeAll(where: { $0.id == stamp.id })
            }

        case .moveStamp(let pageIndex, let id, let fromX, let fromY, let toX, let toY):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if let idx = scanStamps[name]?[pageIndex]?.firstIndex(where: { $0.id == id }) {
                scanStamps[name]?[pageIndex]?[idx].xRatio = isUndo ? fromX : toX
                scanStamps[name]?[pageIndex]?[idx].yRatio = isUndo ? fromY : toY
            }

        case .addText(let pageIndex, let text):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if isUndo {
                scanTexts[name]?[pageIndex]?.removeAll(where: { $0.id == text.id })
            } else {
                if scanTexts[name] == nil { scanTexts[name] = [:] }
                if scanTexts[name]?[pageIndex] == nil { scanTexts[name]?[pageIndex] = [] }
                scanTexts[name]?[pageIndex]?.append(text)
            }

        case .deleteText(let pageIndex, let text):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if isUndo {
                if scanTexts[name] == nil { scanTexts[name] = [:] }
                if scanTexts[name]?[pageIndex] == nil { scanTexts[name]?[pageIndex] = [] }
                scanTexts[name]?[pageIndex]?.append(text)
            } else {
                scanTexts[name]?[pageIndex]?.removeAll(where: { $0.id == text.id })
            }

        case .editText(let pageIndex, let id, let oldText, let newText):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if let idx = scanTexts[name]?[pageIndex]?.firstIndex(where: { $0.id == id }) {
                scanTexts[name]?[pageIndex]?[idx].text = isUndo ? oldText : newText
            }

        case .moveText(let pageIndex, let id, let fromX, let fromY, let toX, let toY):
            if currentPageIndex != pageIndex {
                changePage(to: pageIndex)
            }
            if let idx = scanTexts[name]?[pageIndex]?.firstIndex(where: { $0.id == id }) {
                scanTexts[name]?[pageIndex]?[idx].xRatio = isUndo ? fromX : toX
                scanTexts[name]?[pageIndex]?[idx].yRatio = isUndo ? fromY : toY
            }
        }
    }

    private func addStamp(_ stamp: StampDefinition) {
        let name = activeScanName
        guard !name.isEmpty else { return }
        var list = scanStamps[name]?[currentPageIndex] ?? []
        let newItem = PlacedStampItem(stamp: stamp, xRatio: 0.5, yRatio: 0.4)
        recordAction(.addStamp(pageIndex: currentPageIndex, stamp: newItem))
        list.append(newItem)
        if scanStamps[name] == nil { scanStamps[name] = [:] }
        scanStamps[name]?[currentPageIndex] = list
        if let scan = appState.activeCorrectionScan {
            appState.updateEvaluationProgress(for: scan.rawFileName, annotatedPage: currentPageIndex + 1, totalPages: totalPages)
        }
    }

    private func updatePlacedStamp(_ item: PlacedStampItem) {
        let name = activeScanName
        guard !name.isEmpty, var list = scanStamps[name]?[currentPageIndex] else { return }
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
            scanStamps[name]?[currentPageIndex] = list
        }
    }

    private func deletePlacedStamp(id: UUID) {
        let name = activeScanName
        guard !name.isEmpty, var list = scanStamps[name]?[currentPageIndex] else { return }
        if let item = list.first(where: { $0.id == id }) {
            recordAction(.deleteStamp(pageIndex: currentPageIndex, stamp: item))
        }
        list.removeAll(where: { $0.id == id })
        scanStamps[name]?[currentPageIndex] = list
    }

    private func addTextAnnotation(_ text: String) {
        let name = activeScanName
        guard !name.isEmpty else { return }
        var list = scanTexts[name]?[currentPageIndex] ?? []
        let hex = studioColors.first(where: { $0.color == activeColor })?.hex ?? "EF4444"
        let newItem = PlacedTextItem(
            text: text,
            fontSize: textStops[textFontSizeIndex].size,
            colorHex: hex,
            xRatio: 0.5,
            yRatio: 0.45
        )
        recordAction(.addText(pageIndex: currentPageIndex, text: newItem))
        list.append(newItem)
        if scanTexts[name] == nil { scanTexts[name] = [:] }
        scanTexts[name]?[currentPageIndex] = list
        if let scan = appState.activeCorrectionScan {
            appState.updateEvaluationProgress(for: scan.rawFileName, annotatedPage: currentPageIndex + 1, totalPages: totalPages)
        }
    }

    private func updatePlacedText(_ item: PlacedTextItem) {
        let name = activeScanName
        guard !name.isEmpty, var list = scanTexts[name]?[currentPageIndex] else { return }
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
            scanTexts[name]?[currentPageIndex] = list
        }
    }

    private func updateTextContent(id: UUID, newText: String) {
        let name = activeScanName
        guard !name.isEmpty, var list = scanTexts[name]?[currentPageIndex] else { return }
        if let idx = list.firstIndex(where: { $0.id == id }) {
            let oldText = list[idx].text
            if oldText != newText {
                recordAction(.editText(pageIndex: currentPageIndex, id: id, oldText: oldText, newText: newText))
            }
            list[idx].text = newText
            scanTexts[name]?[currentPageIndex] = list
        }
    }

    private func deletePlacedText(id: UUID) {
        let name = activeScanName
        guard !name.isEmpty, var list = scanTexts[name]?[currentPageIndex] else { return }
        if let item = list.first(where: { $0.id == id }) {
            recordAction(.deleteText(pageIndex: currentPageIndex, text: item))
        }
        list.removeAll(where: { $0.id == id })
        scanTexts[name]?[currentPageIndex] = list
    }

    private func openScanInStudio(_ scan: StorageManager.ScanItem) {
        saveCurrentDrawing()
        if !appState.openCorrectionScans.contains(where: { $0.id == scan.id }) {
            appState.openCorrectionScans.append(scan)
        }
        appState.activeCorrectionScan = scan
        loadScanPDF(scan)
        syncUndoRedoState()
        triggerPageHUD()
    }

    private func loadScanPDF(_ scan: StorageManager.ScanItem) {
        let url = appState.storageManager.localURL(for: scan.path)
        loadPDFFromURL(url)
    }

    private func triggerPageHUD() {
        isPageHUDVisible = true
        pageHUDTask?.cancel()
        pageHUDTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.isPageHUDVisible = false
                }
            }
        }
    }

    private func refreshAvailableScans(autoSelectFirst: Bool = false, forceCloud: Bool = false) async {
        await appState.refreshScans(forceCloud: forceCloud)
        await MainActor.run {
            self.isLoadingScans = false
            self.isCheckingCloud = appState.isCheckingScansCloud
            for scan in appState.availableScans {
                self.scanSyncStatuses[scan.name] = appState.isOnline ? .synced : .offline
            }
            if autoSelectFirst && appState.activeCorrectionScan == nil, let first = appState.availableScans.first {
                openScanInStudio(first)
            }
        }
    }

    private func loadPDFFromURL(_ url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        if let doc = try? PDFEngine.shared.loadDocument(from: url) {
            self.pdfURL = url
            self.pdfDocument = doc

            let targetPage: Int
            if let scan = appState.activeCorrectionScan {
                let saved = appState.evaluationsMetadata[scan.rawFileName]?.lastViewedPage ?? 1
                targetPage = max(0, min(doc.pageCount - 1, saved - 1))
            } else {
                targetPage = 0
            }
            self.currentPageIndex = targetPage

            if let scan = appState.activeCorrectionScan {
                self.currentDrawing = scanDrawings[scan.name]?[targetPage] ?? PKDrawing()
                appState.updateEvaluationProgress(for: scan.rawFileName, viewedPage: targetPage + 1, totalPages: doc.pageCount)
            } else {
                self.currentDrawing = PKDrawing()
            }
        }
    }

    private func changePage(to newIndex: Int) {
        guard newIndex >= 0, newIndex < totalPages else { return }
        saveCurrentDrawing()
        currentPageIndex = newIndex
        if let scan = appState.activeCorrectionScan {
            currentDrawing = scanDrawings[scan.name]?[newIndex] ?? PKDrawing()
            appState.updateEvaluationProgress(for: scan.rawFileName, viewedPage: newIndex + 1, totalPages: totalPages)
        }
        triggerPageHUD()
    }

    private func saveCurrentDrawing() {
        guard let scan = appState.activeCorrectionScan else { return }
        if scanDrawings[scan.name] == nil {
            scanDrawings[scan.name] = [:]
        }
        scanDrawings[scan.name]?[currentPageIndex] = currentDrawing

        if !currentDrawing.strokes.isEmpty {
            appState.updateEvaluationProgress(for: scan.rawFileName, annotatedPage: currentPageIndex + 1, totalPages: totalPages)
        }

        if currentPageIndex == 0, let doc = pdfDocument, let url = pdfURL {
            thumbnailUpdateTask?.cancel()
            let drawingToRender = currentDrawing
            let stampsToRender = scanStamps[scan.name]?[0] ?? []
            let textsToRender = scanTexts[scan.name]?[0] ?? []
            Task {
                await generateAndCachePage0Thumbnail(
                    doc: doc,
                    url: url,
                    drawing: drawingToRender,
                    stamps: stampsToRender,
                    texts: textsToRender
                )
            }
        }
    }

    private func schedulePage0ThumbnailUpdate(doc: PDFDocument, url: URL, drawing: PKDrawing) {
        thumbnailUpdateTask?.cancel()
        thumbnailUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            let stamps = appState.activeCorrectionScan.flatMap { scanStamps[$0.name]?[0] } ?? []
            let texts = appState.activeCorrectionScan.flatMap { scanTexts[$0.name]?[0] } ?? []
            await generateAndCachePage0Thumbnail(doc: doc, url: url, drawing: drawing, stamps: stamps, texts: texts)
        }
    }

    #if canImport(UIKit)
    private func generateAndCachePage0Thumbnail(
        doc: PDFDocument,
        url: URL,
        drawing: PKDrawing,
        stamps: [PlacedStampItem] = [],
        texts: [PlacedTextItem] = []
    ) async {
        guard let page = doc.page(at: 0) else { return }
        let pageCount = doc.pageCount

        let renderedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let targetSize = CGSize(width: 320, height: 440)
            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 2.0
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: targetSize))

                let cgContext = ctx.cgContext
                cgContext.saveGState()

                let scaleX = targetSize.width / pageBounds.width
                let scaleY = targetSize.height / pageBounds.height
                let scale = min(scaleX, scaleY)
                let offsetX = (targetSize.width - pageBounds.width * scale) / 2.0
                let offsetY = (targetSize.height - pageBounds.height * scale) / 2.0

                cgContext.translateBy(x: offsetX, y: targetSize.height - offsetY)
                cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .cropBox, to: cgContext)
                cgContext.restoreGState()

                if !drawing.strokes.isEmpty {
                    let inkImg = drawing.image(from: pageBounds, scale: 2.0)
                    inkImg.draw(in: CGRect(x: offsetX, y: offsetY, width: pageBounds.width * scale, height: pageBounds.height * scale))
                }
            }
        }.value

        if let img = renderedImage {
            PDFThumbnailMemoryCache.shared.setImage(img, for: url)
            PDFThumbnailMemoryCache.shared.setPageCount(pageCount, for: url)
            await MainActor.run {
                self.thumbnailCacheVersion = UUID()
            }
        }
    }
    #elseif canImport(AppKit)
    private func generateAndCachePage0Thumbnail(
        doc: PDFDocument,
        url: URL,
        drawing: PKDrawing,
        stamps: [PlacedStampItem] = [],
        texts: [PlacedTextItem] = []
    ) async {
        guard let page = doc.page(at: 0) else { return }
        let pageCount = doc.pageCount

        let renderedImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let targetSize = CGSize(width: 320, height: 440)
            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

            let newImage = NSImage(size: targetSize)
            newImage.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: targetSize).fill()

            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                let scaleX = targetSize.width / pageBounds.width
                let scaleY = targetSize.height / pageBounds.height
                let scale = min(scaleX, scaleY)
                let offsetX = (targetSize.width - pageBounds.width * scale) / 2.0
                let offsetY = (targetSize.height - pageBounds.height * scale) / 2.0

                ctx.translateBy(x: offsetX, y: offsetY)
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .cropBox, to: ctx)
                ctx.restoreGState()

                if !drawing.strokes.isEmpty {
                    let inkImg = drawing.image(from: pageBounds, scale: 2.0)
                    inkImg.draw(in: NSRect(x: offsetX, y: offsetY, width: pageBounds.width * scale, height: pageBounds.height * scale))
                }
            }
            newImage.unlockFocus()
            return newImage
        }.value

        if let img = renderedImage {
            PDFThumbnailMemoryCache.shared.setImage(img, for: url)
            PDFThumbnailMemoryCache.shared.setPageCount(pageCount, for: url)
            await MainActor.run {
                self.thumbnailCacheVersion = UUID()
            }
        }
    }
    #endif

    private func toggleCorrectedStatus(for scan: StorageManager.ScanItem) {
        let targetState = !scan.isCorrected
        let scanName = scan.name
        withAnimation(.easeInOut(duration: 0.2)) {
            processingScanId = scanName
            scanSyncStatuses[scanName] = .uploading
        }

        Task {
            let oldURL = appState.storageManager.localURL(for: "Evaluations/A corriger/\(scan.name)")
            let targetName = targetState
                ? (scan.name.hasPrefix("CORRIGE_") ? scan.name : "CORRIGE_\(scan.name)")
                : scan.rawFileName
            let newURL = appState.storageManager.localURL(for: "Evaluations/A corriger/\(targetName)")
            PDFThumbnailMemoryCache.shared.copyCache(from: oldURL, to: newURL)

            try? await appState.storageManager.markScan(scan: scan, asCorrected: targetState)

            if targetState {
                let totalP = appState.evaluationsMetadata[scan.rawFileName]?.totalPages ?? 0
                appState.updateEvaluationProgress(for: scan.rawFileName, annotatedPage: max(1, totalP), totalPages: totalP)
            }

            await MainActor.run {
                self.scanSyncStatuses[targetName] = self.appState.isOnline ? .synced : .offline
                self.scanSyncStatuses.removeValue(forKey: scanName)
            }

            await refreshAvailableScans(autoSelectFirst: false, forceCloud: false)

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.processingScanId = nil
                }
                if let updated = availableScans.first(where: { $0.cleanTitle == scan.cleanTitle }) {
                    if self.appState.activeCorrectionScan?.id == scan.id {
                        self.appState.activeCorrectionScan = updated
                    }
                    if let idx = self.appState.openCorrectionScans.firstIndex(where: { $0.id == scan.id }) {
                        self.appState.openCorrectionScans[idx] = updated
                    }
                    self.showMarkedToast = targetState ? "Marqué comme CORRIGÉ !" : "Remis en cours"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.showMarkedToast = nil
                    }
                }
            }
        }
    }

    private func handleImportedPDFs(_ urls: [URL]) {
        Task {
            var importedCount = 0
            for url in urls {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess { url.stopAccessingSecurityScopedResource() }
                }

                if let data = try? Data(contentsOf: url), !data.isEmpty {
                    let filename = url.lastPathComponent
                    let targetPath = "Evaluations/A corriger/\(filename)"
                    try? await appState.storageManager.localCacheProvider.writeData(data, to: targetPath)
                    if appState.isOnline && !(appState.storageManager.activeProvider is LocalStorageProvider) {
                        try? await appState.storageManager.activeProvider.writeData(data, to: targetPath)
                    }
                    importedCount += 1
                }
            }

            await refreshAvailableScans(autoSelectFirst: false, forceCloud: true)

            if importedCount > 0 {
                await MainActor.run {
                    self.importSuccessToast = "\(importedCount) \(importedCount > 1 ? "fichiers importés" : "fichier importé") avec succès"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.importSuccessToast = nil
                    }
                }
            }
        }
    }
}

// MARK: - Carte Mosaïque pour un Paquet d'Évaluation

private struct EvaluationScanCard: View {
    let scan: StorageManager.ScanItem
    let metadata: EvaluationMetadata?
    let fileURL: URL
    let isProcessing: Bool
    let syncStatus: ScanSyncStatus
    let updateToken: UUID
    let onOpen: () -> Void
    let onReset: () -> Void
    let onDistribute: () -> Void

    private var isComplete: Bool {
        scan.isCorrected || metadata?.isEffectivelyCompleted == true
    }

    private var isBlocked: Bool {
        isProcessing || syncStatus == .uploading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Nom du fichier PDF au-dessus du thumbnail (sans .pdf)
            HStack(spacing: 5) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "doc.text.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isComplete ? Color(hex: "10B981") : Color.blue)

                Text(scan.cleanTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            // 2. Thumbnail / Prévisualisation de la 1ère page (Cliquable pour ouvrir directement le document)
            Button {
                guard !isBlocked else { return }
                onOpen()
            } label: {
                PDFScanThumbnailView(
                    url: fileURL,
                    updateToken: updateToken,
                    syncStatus: syncStatus
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isBlocked)
            .help("Cliquer pour ouvrir le document dans l'atelier")

            // 3. Ligne d'action unifiée : [ ↺ ] [ ===== % ===== ] [ ✈️ ]
            if isProcessing || syncStatus == .uploading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Modification en cours...")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            } else {
                unifiedActionRow
            }
        }
        .padding(10)
        .background(
            isComplete
                ? Color(hex: "10B981").opacity(0.04)
                : Color(white: 0.5, opacity: 0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isComplete
                        ? Color(hex: "10B981").opacity(0.35)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private var unifiedActionRow: some View {
        let percent = isComplete ? 100 : (metadata?.progressPercent ?? 0)
        let ratio: Double = isComplete ? 1.0 : (metadata?.progressRatio ?? (Double(percent) / 100.0))

        return HStack(spacing: 6) {
            // Bouton Réinitialiser la progression (Capsule bleue dépolie)
            Button {
                onReset()
            } label: {
                ZStack {
                    Capsule()
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(width: 34, height: 32)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.blue.opacity(0.30), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Remettre la progression de cette évaluation à zéro")

            // Jauge de progression centrale Liquid Glass (hauteur 32)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))

                    if ratio > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isComplete
                                        ? [Color(hex: "10B981"), Color(hex: "059669")]
                                        : [Color.blue, Color(hex: "38BDF8")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(14, geo.size.width * CGFloat(min(1.0, ratio))))
                    }

                    // Label centré : uniquement le pourcentage ou "Non commencé", pas de parenthèses de pages
                    HStack {
                        Spacer(minLength: 0)
                        if percent == 0 {
                            Text("Non commencé")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        } else if isComplete {
                            Text("100 %")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            Text("\(percent) %")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ratio >= 0.5 ? .white : .primary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 32)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isComplete
                            ? Color(hex: "10B981").opacity(0.35)
                            : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            )

            // Bouton Distribuer (Capsule verte dépolie)
            Button {
                onDistribute()
            } label: {
                ZStack {
                    Capsule()
                        .fill(Color(hex: "10B981").opacity(0.14))
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "10B981"))
                }
                .frame(width: 34, height: 32)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(hex: "10B981").opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Distribuer les copies de cette évaluation")
        }
    }
}

// MARK: - Composant de Prévisualisation de Miniature PDF (Asynchrone + Cache Mémoire)

private final class PDFThumbnailMemoryCache: @unchecked Sendable {
    static let shared = PDFThumbnailMemoryCache()
    #if canImport(UIKit)
    private let imageCache = NSCache<NSURL, UIImage>()
    #elseif canImport(AppKit)
    private let imageCache = NSCache<NSURL, NSImage>()
    #endif
    private let pageCountCache = NSCache<NSURL, NSNumber>()

    private init() {
        #if canImport(UIKit)
        imageCache.countLimit = 80
        #endif
    }

    func copyCache(from oldURL: URL, to newURL: URL) {
        if let img = image(for: oldURL) {
            setImage(img, for: newURL)
        }
        if let count = pageCount(for: oldURL) {
            setPageCount(count, for: newURL)
        }
    }

    #if canImport(UIKit)
    func image(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    func setImage(_ image: UIImage, for url: URL) {
        imageCache.setObject(image, forKey: url as NSURL)
    }
    #elseif canImport(AppKit)
    func image(for url: URL) -> NSImage? {
        imageCache.object(forKey: url as NSURL)
    }

    func setImage(_ image: NSImage, for url: URL) {
        imageCache.setObject(image, forKey: url as NSURL)
    }
    #endif

    func pageCount(for url: URL) -> Int? {
        pageCountCache.object(forKey: url as NSURL)?.intValue
    }

    func setPageCount(_ count: Int, for url: URL) {
        pageCountCache.setObject(NSNumber(value: count), forKey: url as NSURL)
    }
}

private struct PDFScanThumbnailView: View {
    let url: URL
    let updateToken: UUID
    let syncStatus: ScanSyncStatus

    #if canImport(UIKit)
    @State private var thumbnailImage: UIImage? = nil
    #elseif canImport(AppKit)
    @State private var thumbnailImage: NSImage? = nil
    #endif
    @State private var pageCount: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Color.white

                #if canImport(UIKit)
                if let img = thumbnailImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                #elseif canImport(AppKit)
                if let img = thumbnailImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                #endif
            }
            .aspectRatio(1 / 1.38, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)

            if syncStatus == .uploading || syncStatus == .downloading {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.32))

                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)

                        Text(overlayLabel(for: syncStatus))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.7), radius: 4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                }
                .aspectRatio(1 / 1.38, contentMode: .fit)
                .transition(.opacity)
            }

            if pageCount > 0 {
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                        Text("\(pageCount) p.")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.72))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .padding(6)
            }
        }
        .task(id: "\(url.path)_\(updateToken.uuidString)") {
            loadThumbnail()
        }
    }

    private func overlayLabel(for status: ScanSyncStatus) -> String {
        switch status {
        case .downloading:
            return "Téléchargement..."
        case .uploading:
            return "Envoi vers Dropbox..."
        default:
            return ""
        }
    }

    private func loadThumbnail() {
        if let cached = PDFThumbnailMemoryCache.shared.image(for: url) {
            self.thumbnailImage = cached
            self.pageCount = PDFThumbnailMemoryCache.shared.pageCount(for: url) ?? 0
            return
        }

        Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return }
            let count = doc.pageCount
            #if canImport(UIKit)
            let thumb = page.thumbnail(of: CGSize(width: 320, height: 440), for: .cropBox)
            PDFThumbnailMemoryCache.shared.setImage(thumb, for: url)
            PDFThumbnailMemoryCache.shared.setPageCount(count, for: url)
            await MainActor.run {
                self.thumbnailImage = thumb
                self.pageCount = count
            }
            #elseif canImport(AppKit)
            let thumb = page.thumbnail(of: CGSize(width: 320, height: 440), for: .cropBox)
            PDFThumbnailMemoryCache.shared.setImage(thumb, for: url)
            PDFThumbnailMemoryCache.shared.setPageCount(count, for: url)
            await MainActor.run {
                self.thumbnailImage = thumb
                self.pageCount = count
            }
            #endif
        }
    }
}

// MARK: - Mini Prévisualisation de Page pour le Ruban de Saut

#if canImport(UIKit)
private struct PageThumbnailMiniView: View {
    let doc: PDFDocument
    let pageIndex: Int
    @State private var thumbImage: UIImage? = nil

    var body: some View {
        ZStack {
            Color.white
            if let img = thumbImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .task(id: pageIndex) {
            guard let page = doc.page(at: pageIndex) else { return }
            let thumb = page.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox)
            await MainActor.run {
                self.thumbImage = thumb
            }
        }
    }
}
#elseif canImport(AppKit)
private struct PageThumbnailMiniView: View {
    let doc: PDFDocument
    let pageIndex: Int
    @State private var thumbImage: NSImage? = nil

    var body: some View {
        ZStack {
            Color.white
            if let img = thumbImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .task(id: pageIndex) {
            guard let page = doc.page(at: pageIndex) else { return }
            let thumb = page.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox)
            await MainActor.run {
                self.thumbImage = thumb
            }
        }
    }
}
#endif

// MARK: - ===============================================================
// MARK: - TOILE INTERACTIVE HAUTE RÉSOLUTION (UIKit UIScrollView + PencilKit)
// MARK: - ===============================================================

#if canImport(UIKit)
final class CenteringScrollView: UIScrollView {
    weak var containerView: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        centerContent()
    }

    func centerContent() {
        guard let container = containerView else { return }
        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        var frameToCenter = container.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) * 0.5
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) * 0.5
        } else {
            frameToCenter.origin.y = 0
        }

        container.frame = frameToCenter
    }
}

public struct InteractivePDFCanvasView: UIViewRepresentable {
    public let document: PDFDocument?
    public let pageIndex: Int
    @Binding public var drawing: PKDrawing
    public let tool: CorrectionToolType
    public let activeColor: Color
    public let pencilWidth: CGFloat
    public let highlighterColor: Color
    public let highlighterWidth: CGFloat
    public let eraserWidth: CGFloat
    public let stamps: [PlacedStampItem]
    public let texts: [PlacedTextItem]
    public let isPerformingUndoRedo: Bool
    public let onStrokeFinished: (PKDrawing, PKDrawing) -> Void
    public let onUpdateStamp: (PlacedStampItem, CGFloat, CGFloat) -> Void
    public let onDeleteStamp: (UUID) -> Void
    public let onUpdateText: (PlacedTextItem, CGFloat, CGFloat) -> Void
    public let onDeleteText: (UUID) -> Void
    public let onTapText: (PlacedTextItem) -> Void
    public let onNextPage: () -> Void
    public let onPreviousPage: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteringScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        context.coordinator.scrollView = scrollView

        let containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.22
        containerView.layer.shadowRadius = 16
        containerView.layer.shadowOffset = CGSize(width: 0, height: 6)
        scrollView.addSubview(containerView)
        scrollView.containerView = containerView
        context.coordinator.containerView = containerView

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        containerView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        #if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput
        #else
        canvasView.drawingPolicy = .pencilOnly
        #endif
        containerView.addSubview(canvasView)
        context.coordinator.canvasView = canvasView

        let stampsOverlay = PassThroughOverlayView()
        stampsOverlay.backgroundColor = .clear
        containerView.addSubview(stampsOverlay)
        context.coordinator.stampsOverlay = stampsOverlay

        // Double-tap pour zoomer / réinitialiser
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Swipes horizontaux pour changer de page (quand zoom == 1.0)
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        scrollView.addGestureRecognizer(swipeLeft)
        context.coordinator.swipeLeft = swipeLeft

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        scrollView.addGestureRecognizer(swipeRight)
        context.coordinator.swipeRight = swipeRight

        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self

        guard let doc = document, let page = doc.page(at: pageIndex) else { return }
        let coordinator = context.coordinator

        // 1. Mise à jour de la page affichée
        let shouldRender = (coordinator.lastLoadedPageIndex != pageIndex || coordinator.lastDocument !== doc) || (coordinator.lastViewportSize == .zero && scrollView.bounds.size != .zero)
        if shouldRender {
            coordinator.lastLoadedPageIndex = pageIndex
            coordinator.lastDocument = doc
            if scrollView.bounds.size != .zero {
                coordinator.lastViewportSize = scrollView.bounds.size
            }
            scrollView.setZoomScale(1.0, animated: false)

            renderPage(page, in: scrollView, coordinator: coordinator)
        }

        // 2. Synchronisation du tracé PencilKit
        if let canvasView = coordinator.canvasView {
            if canvasView.drawing != drawing {
                coordinator.isProgrammaticUpdate = true
                canvasView.drawing = drawing
                coordinator.committedDrawing = drawing
                coordinator.isProgrammaticUpdate = false
            }

            // Outil actif
            switch tool {
            case .pencil:
                canvasView.isUserInteractionEnabled = true
                let color = UIColor(activeColor)
                canvasView.tool = PKInkingTool(.pen, color: color, width: pencilWidth)
            case .highlighter:
                canvasView.isUserInteractionEnabled = true
                let color = UIColor(highlighterColor).withAlphaComponent(0.60)
                canvasView.tool = PKInkingTool(.marker, color: color, width: highlighterWidth)
            case .eraser:
                canvasView.isUserInteractionEnabled = true
                if #available(iOS 14.0, *) {
                    canvasView.tool = PKEraserTool(.bitmap, width: eraserWidth)
                } else {
                    canvasView.tool = PKEraserTool(.vector)
                }
            case .text, .stamp:
                canvasView.isUserInteractionEnabled = false
            }
        }

        // 3. Synchronisation des tampons et textes
        coordinator.syncStampsAndTexts(stamps: stamps, texts: texts)
    }

    private func renderPage(_ page: PDFPage, in scrollView: UIScrollView, coordinator: Coordinator) {
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }

        let screenBounds = UIScreen.main.bounds
        let viewportW = scrollView.bounds.width > 0 ? scrollView.bounds.width : screenBounds.width
        let viewportH = scrollView.bounds.height > 0 ? scrollView.bounds.height : screenBounds.height

        // On maximise la copie avec une marge propre et régulière tout autour :
        // ~48pt horizontalement (24pt de chaque côté), ~110pt verticalement (55pt en haut pour la barre d'onglets, 55pt en bas pour le HUD)
        let availableW = viewportW - 48
        let availableH = viewportH - 110
        let fitScale = min(availableW / pageBounds.width, availableH / pageBounds.height)
        let displayW = round(pageBounds.width * fitScale)
        let displayH = round(pageBounds.height * fitScale)

        let targetFrame = CGRect(x: 0, y: 0, width: displayW, height: displayH)
        coordinator.containerView?.frame = targetFrame
        coordinator.imageView?.frame = targetFrame
        coordinator.canvasView?.frame = targetFrame
        coordinator.stampsOverlay?.frame = targetFrame
        scrollView.contentSize = targetFrame.size
        scrollView.contentInset = .zero

        (scrollView as? CenteringScrollView)?.centerContent()

        // Rendu Retina net
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: targetFrame.size, format: format)
        let rendered = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetFrame.size))
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: displayH)
            cg.scaleBy(x: displayW / pageBounds.width, y: -displayH / pageBounds.height)
            page.draw(with: .cropBox, to: cg)
            cg.restoreGState()
        }
        coordinator.imageView?.image = rendered
    }

    public final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: InteractivePDFCanvasView
        weak var scrollView: UIScrollView?
        weak var containerView: UIView?
        weak var imageView: UIImageView?
        weak var canvasView: PKCanvasView?
        weak var stampsOverlay: UIView?
        var lastLoadedPageIndex: Int = -1
        weak var lastDocument: PDFDocument?
        var lastViewportSize: CGSize = .zero
        var committedDrawing: PKDrawing = PKDrawing()
        var isProgrammaticUpdate: Bool = false
        weak var swipeLeft: UISwipeGestureRecognizer?
        weak var swipeRight: UISwipeGestureRecognizer?

        init(_ parent: InteractivePDFCanvasView) {
            self.parent = parent
            self.committedDrawing = parent.drawing
            super.init()
        }

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return containerView
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? CenteringScrollView)?.centerContent()
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isProgrammaticUpdate, !parent.isPerformingUndoRedo else { return }
            let oldDrawing = committedDrawing
            let newDrawing = canvasView.drawing
            if oldDrawing != newDrawing {
                committedDrawing = newDrawing
                parent.drawing = newDrawing
                parent.onStrokeFinished(oldDrawing, newDrawing)
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let sv = scrollView, let container = containerView else { return }
            if sv.zoomScale > 1.05 {
                sv.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: container)
                let zoomRect = CGRect(
                    x: point.x - (sv.bounds.width / 4.4),
                    y: point.y - (sv.bounds.height / 4.4),
                    width: sv.bounds.width / 2.2,
                    height: sv.bounds.height / 2.2
                )
                sv.zoom(to: zoomRect, animated: true)
            }
        }

        @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
            if (scrollView?.zoomScale ?? 1.0) <= 1.05 {
                parent.onNextPage()
            }
        }

        @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
            if (scrollView?.zoomScale ?? 1.0) <= 1.05 {
                parent.onPreviousPage()
            }
        }

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer == swipeLeft || gestureRecognizer == swipeRight {
                return (scrollView?.zoomScale ?? 1.0) <= 1.05
            }
            return true
        }

        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }

        func syncStampsAndTexts(stamps: [PlacedStampItem], texts: [PlacedTextItem]) {
            guard let overlay = stampsOverlay, let container = containerView else { return }
            let w = container.bounds.width
            let h = container.bounds.height
            guard w > 0, h > 0 else { return }

            overlay.subviews.forEach { $0.removeFromSuperview() }

            // Dessin des tampons
            for item in stamps {
                let badge = StampBadgeUIKitView(item: item, containerBounds: container.bounds) { [weak self] newX, newY in
                    var updated = item
                    let oldX = item.xRatio
                    let oldY = item.yRatio
                    updated.xRatio = newX
                    updated.yRatio = newY
                    self?.parent.onUpdateStamp(updated, oldX, oldY)
                } onDelete: { [weak self] in
                    self?.parent.onDeleteStamp(item.id)
                }
                overlay.addSubview(badge)
            }

            // Dessin des textes
            for item in texts {
                let textBadge = TextBadgeUIKitView(item: item, containerBounds: container.bounds) { [weak self] newX, newY in
                    var updated = item
                    let oldX = item.xRatio
                    let oldY = item.yRatio
                    updated.xRatio = newX
                    updated.yRatio = newY
                    self?.parent.onUpdateText(updated, oldX, oldY)
                } onDelete: { [weak self] in
                    self?.parent.onDeleteText(item.id)
                } onTap: { [weak self] in
                    self?.parent.onTapText(item)
                }
                overlay.addSubview(textBadge)
            }
        }
    }
}

// Vue superposée transparente qui laisse passer les touches s'il n'y a pas de sous-vue touchée
public final class PassThroughOverlayView: UIView {
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view == self ? nil : view
    }
}

// Badge UIKit pour un Tampon pédagogique draggable
private final class StampBadgeUIKitView: UIView {
    let item: PlacedStampItem
    let onMoved: (CGFloat, CGFloat) -> Void
    let onDelete: () -> Void

    init(item: PlacedStampItem, containerBounds: CGRect, onMoved: @escaping (CGFloat, CGFloat) -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.onMoved = onMoved
        self.onDelete = onDelete
        super.init(frame: .zero)

        backgroundColor = UIColor(hexString: item.stamp.bgHex)
        layer.cornerRadius = 14
        layer.masksToBounds = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 6
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)

        let iconView = UIImageView(image: UIImage(systemName: item.stamp.icon))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        hStack.addArrangedSubview(iconView)

        let label = UILabel()
        label.text = item.stamp.title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        hStack.addArrangedSubview(label)

        let deleteBtn = UIButton(type: .system)
        deleteBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteBtn.tintColor = UIColor.white.withAlphaComponent(0.85)
        deleteBtn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.widthAnchor.constraint(equalToConstant: 16).isActive = true
        deleteBtn.heightAnchor.constraint(equalToConstant: 16).isActive = true
        hStack.addArrangedSubview(deleteBtn)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])

        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(
            x: item.xRatio * containerBounds.width - size.width / 2,
            y: item.yRatio * containerBounds.height - size.height / 2,
            width: size.width,
            height: size.height
        )

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func deleteTapped() {
        onDelete()
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended {
            let xRatio = max(0.05, min(0.95, center.x / superview.bounds.width))
            let yRatio = max(0.05, min(0.95, center.y / superview.bounds.height))
            onMoved(xRatio, yRatio)
        }
    }
}

// Badge UIKit pour une Annotation Texte draggable
private final class TextBadgeUIKitView: UIView {
    let item: PlacedTextItem
    let onMoved: (CGFloat, CGFloat) -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    init(item: PlacedTextItem, containerBounds: CGRect, onMoved: @escaping (CGFloat, CGFloat) -> Void, onDelete: @escaping () -> Void, onTap: @escaping () -> Void) {
        self.item = item
        self.onMoved = onMoved
        self.onDelete = onDelete
        self.onTap = onTap
        super.init(frame: .zero)

        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor(hexString: item.colorHex).withAlphaComponent(0.45).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 6
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)

        let label = UILabel()
        label.text = item.text
        label.textColor = UIColor(hexString: item.colorHex)
        label.font = UIFont.systemFont(ofSize: item.fontSize, weight: .semibold)
        hStack.addArrangedSubview(label)

        let deleteBtn = UIButton(type: .system)
        deleteBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        deleteBtn.tintColor = UIColor.secondaryLabel
        deleteBtn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.widthAnchor.constraint(equalToConstant: 16).isActive = true
        deleteBtn.heightAnchor.constraint(equalToConstant: 16).isActive = true
        hStack.addArrangedSubview(deleteBtn)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])

        let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(
            x: item.xRatio * containerBounds.width - size.width / 2,
            y: item.yRatio * containerBounds.height - size.height / 2,
            width: size.width,
            height: size.height
        )

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func deleteTapped() {
        onDelete()
    }

    @objc func handleTap() {
        onTap()
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended {
            let xRatio = max(0.05, min(0.95, center.x / superview.bounds.width))
            let yRatio = max(0.05, min(0.95, center.y / superview.bounds.height))
            onMoved(xRatio, yRatio)
        }
    }
}

// Extension utilitaire UIColor Hex
private extension UIColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
#elseif canImport(AppKit) && !canImport(UIKit)
final class AutoScalingPDFView: PDFView {
    private var hasConfiguredInitialScale = false

    override func layout() {
        super.layout()
        if bounds.width > 0 && bounds.height > 0 && !hasConfiguredInitialScale {
            hasConfiguredInitialScale = true
            autoScales = true
        }
    }
}

public struct InteractivePDFCanvasView: NSViewRepresentable {
    public let document: PDFDocument?
    public let pageIndex: Int
    @Binding public var drawing: PKDrawing
    public let tool: CorrectionToolType
    public let activeColor: Color
    public let pencilWidth: CGFloat
    public let highlighterColor: Color
    public let highlighterWidth: CGFloat
    public let eraserWidth: CGFloat
    public let stamps: [PlacedStampItem]
    public let texts: [PlacedTextItem]
    public let isPerformingUndoRedo: Bool
    public let onStrokeFinished: (PKDrawing, PKDrawing) -> Void
    public let onUpdateStamp: (PlacedStampItem, CGFloat, CGFloat) -> Void
    public let onDeleteStamp: (UUID) -> Void
    public let onUpdateText: (PlacedTextItem, CGFloat, CGFloat) -> Void
    public let onDeleteText: (UUID) -> Void
    public let onTapText: (PlacedTextItem) -> Void
    public let onNextPage: () -> Void
    public let onPreviousPage: () -> Void

    public init(
        document: PDFDocument?,
        pageIndex: Int,
        drawing: Binding<PKDrawing>,
        tool: CorrectionToolType,
        activeColor: Color,
        pencilWidth: CGFloat,
        highlighterColor: Color,
        highlighterWidth: CGFloat,
        eraserWidth: CGFloat,
        stamps: [PlacedStampItem],
        texts: [PlacedTextItem],
        isPerformingUndoRedo: Bool,
        onStrokeFinished: @escaping (PKDrawing, PKDrawing) -> Void,
        onUpdateStamp: @escaping (PlacedStampItem, CGFloat, CGFloat) -> Void,
        onDeleteStamp: @escaping (UUID) -> Void,
        onUpdateText: @escaping (PlacedTextItem, CGFloat, CGFloat) -> Void,
        onDeleteText: @escaping (UUID) -> Void,
        onTapText: @escaping (PlacedTextItem) -> Void,
        onNextPage: @escaping () -> Void,
        onPreviousPage: @escaping () -> Void
    ) {
        self.document = document
        self.pageIndex = pageIndex
        self._drawing = drawing
        self.tool = tool
        self.activeColor = activeColor
        self.pencilWidth = pencilWidth
        self.highlighterColor = highlighterColor
        self.highlighterWidth = highlighterWidth
        self.eraserWidth = eraserWidth
        self.stamps = stamps
        self.texts = texts
        self.isPerformingUndoRedo = isPerformingUndoRedo
        self.onStrokeFinished = onStrokeFinished
        self.onUpdateStamp = onUpdateStamp
        self.onDeleteStamp = onDeleteStamp
        self.onUpdateText = onUpdateText
        self.onDeleteText = onDeleteText
        self.onTapText = onTapText
        self.onNextPage = onNextPage
        self.onPreviousPage = onPreviousPage
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = AutoScalingPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .clear
        pdfView.document = document
        if let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, let targetPage = doc.page(at: pageIndex) {
            pdfView.go(to: targetPage)
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        if pdfView.document !== document {
            pdfView.document = document
            pdfView.autoScales = true
        }
        if let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, let targetPage = doc.page(at: pageIndex) {
            if pdfView.currentPage != targetPage {
                pdfView.go(to: targetPage)
            }
        }
    }

    public final class Coordinator: NSObject {
        var parent: InteractivePDFCanvasView
        init(_ parent: InteractivePDFCanvasView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let current = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let idx = doc.index(for: current)
            if idx != parent.pageIndex {
                if idx > parent.pageIndex {
                    parent.onNextPage()
                } else if idx < parent.pageIndex {
                    parent.onPreviousPage()
                }
            }
        }
    }
}
#endif
