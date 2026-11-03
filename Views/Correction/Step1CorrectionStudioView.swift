//
//  Step1CorrectionStudioView.swift
//  Dropies
//
//  Étape 1 : Atelier de correction au stylet (Apple Pencil + PencilKit).
//  Permet de corriger plusieurs paquets de copies en parallèle dans `Evaluations/A corriger/`
//  et de marquer un paquet comme terminé avec le préfixe `CORRIGE_`.
//  Sublimé avec barres d'outils flottantes et cartes de verre dépoli visionOS.
//

import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

public struct Step1CorrectionStudioView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    @State private var availableScans: [StorageManager.ScanItem] = []
    @State private var selectedScan: StorageManager.ScanItem? = nil
    @State private var pdfURL: URL? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var currentPageIndex: Int = 0
    @State private var pageDrawings: [Int: PKDrawing] = [:]
    @State private var currentDrawing: PKDrawing = PKDrawing()

    @State private var isImporterPresented: Bool = false
    @State private var isFullScreenCanvas: Bool = false
    @State private var showMarkedToast: String? = nil

    public init(appState: AppState, currentStep: Binding<Int>) {
        self.appState = appState
        self._currentStep = currentStep
    }

    private var totalPages: Int {
        pdfDocument?.pageCount ?? 0
    }

    public var body: some View {
        ZStack {
            if let document = pdfDocument {
                // MARK: - Canvas de correction PDF + Apple Pencil
                ZStack {
                    PDFKitView(document: document, currentPageIndex: currentPageIndex)
                        .edgesIgnoringSafeArea(.all)

                    PencilCanvasOverlay(drawing: $currentDrawing)
                        .edgesIgnoringSafeArea(.all)

                    // Barre d'outils supérieure flottante
                    VStack {
                        topFloatingStudioBar
                            .padding(.top, 8)
                        Spacer()
                    }

                    // Barre d'outils inférieure flottante (Island Toolbar)
                    VStack {
                        Spacer()
                        bottomFloatingStudioBar
                            .padding(.bottom, 20)
                    }
                }
            } else {
                // MARK: - Hero Card Liquid Glass (Aucun paquet ouvert)
                emptyStateHeroCard
            }
        }
        .task {
            await refreshAvailableScans()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadPDFFromURL(url)
            case .failure(let error):
                appState.errorMessage = "Erreur : \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Barre d'outils Supérieure Flottante

    private var topFloatingStudioBar: some View {
        FloatingGlassBar {
            // Menu de choix des paquets en attente
            Menu {
                Section("Paquets en attente (Evaluations/A corriger)") {
                    ForEach(availableScans) { scan in
                        Button {
                            loadScanItem(scan)
                        } label: {
                            HStack {
                                if scan.isCorrected {
                                    Label(scan.cleanTitle, systemImage: "checkmark.seal.fill")
                                } else {
                                    Label(scan.cleanTitle, systemImage: "doc.text")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Importer un autre PDF...", systemImage: "plus.rectangle.on.folder")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedScan?.isCorrected == true ? "checkmark.seal.fill" : "folder.fill")
                        .foregroundColor(selectedScan?.isCorrected == true ? .green : .blue)
                    Text(selectedScan?.cleanTitle ?? (pdfURL?.lastPathComponent ?? "Choisir un paquet"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let scan = selectedScan {
                if scan.isCorrected {
                    BadgeView("Prêt pour chargement", icon: "checkmark.seal.fill", style: .success)
                } else {
                    BadgeView("Correction en cours", icon: "pencil", style: .warning)
                }
            }

            if let toast = showMarkedToast {
                Text(toast)
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                isFullScreenCanvas.toggle()
            } label: {
                Image(systemName: isFullScreenCanvas ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .help("Plein écran stylet")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Barre d'outils Inférieure Flottante (VisionOS Island Dock)

    private var bottomFloatingStudioBar: some View {
        FloatingGlassBar {
            // Navigation pages
            Button {
                changePage(to: currentPageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex <= 0)
            .buttonStyle(.plain)

            Text("Page \(currentPageIndex + 1) / \(totalPages)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)

            Button {
                changePage(to: currentPageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex >= totalPages - 1)
            .buttonStyle(.plain)

            Divider().frame(height: 20)

            // Effacer page
            Button(role: .destructive) {
                currentDrawing = PKDrawing()
                pageDrawings[currentPageIndex] = PKDrawing()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.85))
                    .frame(width: 30, height: 30)
            }
            .help("Effacer les annotations de cette page")
            .buttonStyle(.plain)

            Divider().frame(height: 20)

            // Bouton Bascule CORRIGÉ
            if let scan = selectedScan {
                Button {
                    toggleCorrectedStatus(for: scan)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "circle.dashed")
                        Text(scan.isCorrected ? "Terminé (CORRIGÉ)" : "Marquer Corrigé")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(scan.isCorrected ? LinearGradient.emeraldGreen : LinearGradient.coralOrange)
                    .clipShape(Capsule())
                    .shadow(color: (scan.isCorrected ? Color.green : Color.orange).opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 20)

            // Bouton Passer au chargement
            Button {
                saveCurrentDrawing()
                currentStep = 2
            } label: {
                HStack(spacing: 6) {
                    Text("Charger (2)")
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "arrow.right.circle.fill")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(LinearGradient.electricBlue)
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero Card Liquid Glass (État vide)

    private var emptyStateHeroCard: some View {
        VStack(spacing: 24) {
            // Icône Mascotte Stylisée
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "3B82F6").opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)

                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(LinearGradient.electricBlue)
            }

            VStack(spacing: 8) {
                Text("Atelier Stylet & Correction")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text("Ouvrez un paquet de copies numérisées pour annoter au stylet avec Apple Pencil.\nVous pouvez corriger plusieurs paquets en parallèle à votre rythme.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            if !availableScans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paquets détectés dans Evaluations/A corriger/ :")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    VStack(spacing: 8) {
                        ForEach(availableScans) { scan in
                            Button {
                                loadScanItem(scan)
                            } label: {
                                HStack {
                                    Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(scan.isCorrected ? .green : .blue)

                                    Text(scan.cleanTitle)
                                        .font(.system(size: 14, weight: .medium))

                                    Spacer()

                                    if scan.isCorrected {
                                        BadgeView("Prêt (CORRIGÉ)", style: .success)
                                    } else {
                                        BadgeView("En attente", style: .neutral)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .frame(maxWidth: 400)
                                .glassCard(cornerRadius: 12, strokeOpacity: 0.3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("Importer un fichier PDF", systemImage: "folder.badge.plus")
            }
            .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))
        }
        .padding(36)
        .glassCard(cornerRadius: 26, strokeOpacity: 0.5)
        .frame(maxWidth: 520)
    }

    // MARK: - Actions & Logique

    private func refreshAvailableScans() async {
        if let list = try? await appState.storageManager.listScans() {
            self.availableScans = list
            if selectedScan == nil, let first = list.first {
                loadScanItem(first)
            }
        }
    }

    private func loadScanItem(_ scan: StorageManager.ScanItem) {
        saveCurrentDrawing()
        selectedScan = scan
        let url = appState.storageManager.localURL(for: "Evaluations/A corriger/\(scan.name)")
        loadPDFFromURL(url)
    }

    private func loadPDFFromURL(_ url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        if let doc = try? PDFEngine.shared.loadDocument(from: url) {
            self.pdfURL = url
            self.pdfDocument = doc
            self.currentPageIndex = 0
            self.pageDrawings.removeAll()
            self.currentDrawing = PKDrawing()
        }
    }

    private func changePage(to newIndex: Int) {
        guard newIndex >= 0, newIndex < totalPages else { return }
        saveCurrentDrawing()
        currentPageIndex = newIndex
        currentDrawing = pageDrawings[newIndex] ?? PKDrawing()
    }

    private func saveCurrentDrawing() {
        pageDrawings[currentPageIndex] = currentDrawing
    }

    private func toggleCorrectedStatus(for scan: StorageManager.ScanItem) {
        let targetState = !scan.isCorrected
        Task {
            try? await appState.storageManager.markScan(scan: scan, asCorrected: targetState)
            await refreshAvailableScans()
            if let updated = availableScans.first(where: { $0.cleanTitle == scan.cleanTitle }) {
                await MainActor.run {
                    self.selectedScan = updated
                    self.showMarkedToast = targetState ? "Marqué comme CORRIGÉ !" : "Remis en cours"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.showMarkedToast = nil
                    }
                }
            }
        }
    }
}
