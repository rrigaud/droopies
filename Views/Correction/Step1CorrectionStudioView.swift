//
//  Step1CorrectionStudioView.swift
//  Dropies
//
//  Étape 1 : Atelier de correction au stylet (Apple Pencil + PencilKit)
//  et préparation de l'évaluation (Scan brut, classe, titre, barème).
//

import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

public struct Step1CorrectionStudioView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    @State private var pdfURL: URL? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var currentPageIndex: Int = 0
    @State private var pageDrawings: [Int: PKDrawing] = [:]
    @State private var currentDrawing: PKDrawing = PKDrawing()

    @State private var evalTitle: String = ""
    @State private var evalDate: Date = Date()
    @State private var evalMaxScore: Double = 20.0
    @State private var isImporterPresented: Bool = false
    @State private var isFullScreenCanvas: Bool = false

    public init(appState: AppState, currentStep: Binding<Int>) {
        self.appState = appState
        self._currentStep = currentStep
    }

    private var totalPages: Int {
        pdfDocument?.pageCount ?? 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Barre d'outils supérieure (Métadonnées & Fichier)
            HStack(spacing: 16) {
                // Bouton d'importation PDF
                Button {
                    isImporterPresented = true
                } label: {
                    Label(
                        pdfURL == nil ? "Importer le scan PDF" : pdfURL!.lastPathComponent,
                        systemImage: pdfURL == nil ? "doc.badge.plus" : "doc.text.fill"
                    )
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(pdfURL == nil ? .blue : .secondary)

                Divider()
                    .frame(height: 24)

                // Sélecteur de classe
                Picker("Classe", selection: $appState.selectedClassId) {
                    Text("Choisir une classe").tag(nil as String?)
                    ForEach(appState.classes) { group in
                        Text(group.name).tag(group.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                // Titre de l'évaluation
                TextField("Titre du devoir (ex: DS 02 - Fractions)", text: $evalTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                // Date
                DatePicker("", selection: $evalDate, displayedComponents: .date)
                    .labelsHidden()

                Spacer()

                // Barème
                HStack(spacing: 6) {
                    Text("Sur")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("20", value: $evalMaxScore, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                // Bouton plein écran pour la correction au stylet
                Button {
                    isFullScreenCanvas.toggle()
                } label: {
                    Image(systemName: isFullScreenCanvas ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                }
                .help("Bascule plein écran stylet")

                // Bouton passer à l'étape suivante
                Button {
                    proceedToStep2()
                } label: {
                    Label("Découpage ➔", systemImage: "scissors")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(pdfDocument == nil || (appState.selectedClassId == nil && appState.classes.isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.5, opacity: 0.06))

            Divider()

            // MARK: - Espace de travail de correction
            if let document = pdfDocument {
                ZStack {
                    // Vue PDF Kit sous-jacente
                    PDFKitView(document: document, currentPageIndex: currentPageIndex)
                        .edgesIgnoringSafeArea(.all)

                    // Calque transparent PencilKit tactile superposé
                    PencilCanvasOverlay(drawing: $currentDrawing)
                        .edgesIgnoringSafeArea(.all)

                    // Barre de navigation entre pages
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
                // Écran d'accueil de dépôt de scan
                VStack(spacing: 20) {
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue.opacity(0.8))

                    Text("Aucun scan PDF chargé")
                        .font(.title2.bold())

                    Text("Déposez le PDF issu du photocopieur ou cliquez ci-dessous pour démarrer la correction au stylet Apple Pencil.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Sélectionner un fichier PDF", systemImage: "folder.badge.plus")
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
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadPDF(from: url)
            case .failure(let error):
                appState.errorMessage = "Erreur d'importation : \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Logique interne

    private func loadPDF(from url: URL) {
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

            if evalTitle.isEmpty {
                let baseName = url.deletingPathExtension().lastPathComponent
                self.evalTitle = baseName
            }
        }
    }

    private func changePage(to newIndex: Int) {
        guard newIndex >= 0, newIndex < totalPages else { return }
        // Sauvegarde du dessin de la page courante
        pageDrawings[currentPageIndex] = currentDrawing
        currentPageIndex = newIndex
        // Chargement du dessin de la nouvelle page
        currentDrawing = pageDrawings[newIndex] ?? PKDrawing()
    }

    private func proceedToStep2() {
        guard let doc = pdfDocument else { return }
        pageDrawings[currentPageIndex] = currentDrawing

        let selectedClass = appState.selectedClass?.name ?? "Classe"
        var eval = Evaluation(
            title: evalTitle.isEmpty ? "Devoir" : evalTitle,
            date: evalDate,
            className: selectedClass,
            maxScore: evalMaxScore,
            pagesPerCopy: Evaluation.estimatePagesPerCopy(totalPages: doc.pageCount, expectedClassSize: appState.studentsInSelectedClass.count)
        )

        // Générer les copies initiales découpées
        let pagesPerCopy = eval.pagesPerCopy
        var copies: [StudentCopy] = []
        var page = 1
        var copyIdx = 1

        while page <= doc.pageCount {
            let pageEnd = min(page + pagesPerCopy - 1, doc.pageCount)
            let drawingData = pageDrawings[page - 1]?.dataRepresentation()
            copies.append(StudentCopy(
                index: copyIdx,
                pageStart: page,
                pageEnd: pageEnd,
                annotationsData: drawingData
            ))
            page += pagesPerCopy
            copyIdx += 1
        }

        eval.copies = copies
        appState.currentEvaluation = eval
        currentStep = 2
    }
}
