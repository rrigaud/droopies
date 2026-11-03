//
//  Step1CorrectionStudioView.swift
//  Dropies
//
//  Étape 1 : Atelier de correction au stylet (Apple Pencil + PencilKit).
//  Permet de corriger plusieurs paquets de copies en parallèle dans `Evaluations/A corriger/`
//  et de marquer un paquet comme terminé avec le préfixe `CORRIGE_`.
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
        VStack(spacing: 0) {
            // MARK: - Barre d'outils supérieure
            HStack(spacing: 14) {
                // Menu de sélection des paquets dans `Evaluations/A corriger`
                Menu {
                    Section("Paquets en attente dans A corriger") {
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
                    HStack(spacing: 6) {
                        Image(systemName: selectedScan?.isCorrected == true ? "checkmark.circle.fill" : "folder.fill")
                            .foregroundColor(selectedScan?.isCorrected == true ? .green : .blue)
                        Text(selectedScan?.cleanTitle ?? (pdfURL?.lastPathComponent ?? "Choisir un paquet de copies"))
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.5, opacity: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Badge de statut du scan en cours
                if let scan = selectedScan {
                    if scan.isCorrected {
                        BadgeView("Paquet Corrigé", icon: "checkmark.seal.fill", style: .success)
                    } else {
                        BadgeView("En cours", icon: "pencil", style: .warning)
                    }

                    // Bouton pour marquer comme CORRIGÉ
                    Button {
                        toggleCorrectedStatus(for: scan)
                    } label: {
                        Label(
                            scan.isCorrected ? "Démarquer (En cours)" : "Marquer comme Corrigé (CORRIGE_)",
                            systemImage: scan.isCorrected ? "arrow.uturn.backward" : "checkmark.circle"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(scan.isCorrected ? .orange : .green)
                }

                Spacer()

                if let toast = showMarkedToast {
                    Text(toast)
                        .font(.caption.bold())
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Bouton plein écran pour correction confortable au stylet
                Button {
                    isFullScreenCanvas.toggle()
                } label: {
                    Image(systemName: isFullScreenCanvas ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                }
                .help("Bascule plein écran stylet")

                // Bouton pour passer au chargement des copies
                Button {
                    saveCurrentDrawing()
                    currentStep = 2
                } label: {
                    Label("Chargement des copies (2) ➔", systemImage: "arrow.right.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.5, opacity: 0.06))

            Divider()

            // MARK: - Espace de travail de correction au stylet
            if let document = pdfDocument {
                ZStack {
                    // Vue PDFKit sous-jacente
                    PDFKitView(document: document, currentPageIndex: currentPageIndex)
                        .edgesIgnoringSafeArea(.all)

                    // Calque transparent PencilKit tactile superposé
                    PencilCanvasOverlay(drawing: $currentDrawing)
                        .edgesIgnoringSafeArea(.all)

                    // Barre flottante de navigation entre les pages
                    VStack {
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                changePage(to: currentPageIndex - 1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.title3.bold())
                                    .padding(8)
                            }
                            .disabled(currentPageIndex <= 0)

                            Text("Page \(currentPageIndex + 1) sur \(totalPages)")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Button {
                                changePage(to: currentPageIndex + 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.title3.bold())
                                    .padding(8)
                            }
                            .disabled(currentPageIndex >= totalPages - 1)

                            Divider()
                                .frame(height: 20)

                            Button(role: .destructive) {
                                currentDrawing = PKDrawing()
                                pageDrawings[currentPageIndex] = PKDrawing()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .help("Effacer les annotations de cette page")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .padding(.bottom, 20)
                    }
                }
            } else {
                // Aucun paquet ouvert
                VStack(spacing: 20) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 64))
                        .foregroundColor(.blue.opacity(0.8))

                    Text("Atelier de Correction au Stylet")
                        .font(.title2.bold())

                    Text("Sélectionnez un paquet scanné dans le dossier « A corriger » pour annoter vos copies au stylet Apple Pencil à votre rythme.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    if !availableScans.isEmpty {
                        VStack(spacing: 8) {
                            Text("Paquets disponibles dans Evaluations/A corriger/ :")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            ForEach(availableScans) { scan in
                                Button {
                                    loadScanItem(scan)
                                } label: {
                                    HStack {
                                        Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                                            .foregroundColor(scan.isCorrected ? .green : .blue)
                                        Text(scan.name)
                                            .fontWeight(.medium)
                                        Spacer()
                                        if scan.isCorrected {
                                            BadgeView("Corrigé", style: .success)
                                        } else {
                                            BadgeView("En attente", style: .neutral)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: 380)
                                    .background(Color(white: 0.5, opacity: 0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Importer un fichier PDF externe", systemImage: "folder.badge.plus")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.5, opacity: 0.03))
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
