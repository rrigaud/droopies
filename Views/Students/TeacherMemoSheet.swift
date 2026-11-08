//
//  TeacherMemoSheet.swift
//  Droopies
//
//  Aperçu réel et générateur de PDF du Mémo des Accès Enseignant.
//  Format A4 compact et lisible (jusqu'à 36 élèves par page),
//  enregistrement automatique à la racine du dossier Source Cloud,
//  et ouverture directe par l'OS (Aperçu sur Mac, AirPrint / Fichiers sur iPad).
//

import SwiftUI
import PDFKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct TeacherMemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState
    public let targetStudentIds: Set<Int>?
    public let onGenerated: ((URL) -> Void)?

    @State private var generatedPDFDocument: PDFDocument? = nil
    @State private var isRenderingPDF: Bool = false
    @State private var isSavingPDF: Bool = false
    @State private var toastMessage: String? = nil
    @State private var exportedFileURL: URL? = nil

    public init(
        appState: AppState,
        targetStudentIds: Set<Int>? = nil,
        onGenerated: ((URL) -> Void)? = nil
    ) {
        self.appState = appState
        self.targetStudentIds = targetStudentIds
        self.onGenerated = onGenerated
    }

    private var portalURL: String {
        appState.settings.portalUrl.isEmpty ? "https://droopies.education" : appState.settings.portalUrl
    }

    private var activeRootPath: String {
        let clean = appState.currentRootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? "/" : "/\(clean)"
    }

    private var providerType: AppSettings.StorageProviderType {
        appState.storageManager.activeProvider.providerType
    }

    private var cloudServiceName: String {
        appState.storageManager.activeProvider.providerType.displayName
    }

    // MARK: - Élèves concernés
    private var studentsToDisplay: [Student] {
        var baseList = appState.students
        if let targets = targetStudentIds, !targets.isEmpty {
            baseList = baseList.filter { targets.contains($0.id) }
        }
        return baseList.sorted {
            if $0.classe == $1.classe {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.classe < $1.classe
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Barre d'outils supérieure
                toolbarHeader

                Divider()

                // MARK: - 2. Vrai Aperçu PDF Haute Fidélité
                ZStack {
                    Color(white: 0.94)
                        .ignoresSafeArea()

                    if isRenderingPDF {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Génération de l'aperçu du Mémo...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    } else if let doc = generatedPDFDocument {
                        PDFKitView(document: doc, autoScales: true)
                            .padding(8)
                    } else if studentsToDisplay.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Aucun élève à afficher")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(appState.t(.memoBatchTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .task(id: studentsToDisplay) {
                await renderPreviewPDF()
            }
            .overlay(alignment: .bottom) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 650)
        #endif
    }

    // MARK: - Barre d'Outils Supérieure

    private var toolbarHeader: some View {
        HStack(spacing: 14) {
            // Compteur d'élèves
            HStack(spacing: 6) {
                Text("\(studentsToDisplay.count)")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())

                Text("élève(s)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Indicateur de pagination PDF réelle
            if let doc = generatedPDFDocument, doc.pageCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "doc.richtext")
                        .font(.caption2)
                    Text("\(doc.pageCount) page(s) A4")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
            }

            // Badge du service Cloud actif avec logo officiel
            HStack(spacing: 6) {
                CloudBrandIconView(type: providerType, size: 14)
                Text(cloudServiceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())

            Spacer()

            // Bouton "Générer le PDF"
            Button {
                Task { await generateAndOpenPDF() }
            } label: {
                HStack(spacing: 6) {
                    if isSavingPDF {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                    }
                    Text(appState.t(.btnGeneratePDF))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(studentsToDisplay.isEmpty || isSavingPDF)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions Métier

    /// Rendu réactif de l'aperçu PDF
    private func renderPreviewPDF() async {
        isRenderingPDF = true
        defer { isRenderingPDF = false }

        let targets = studentsToDisplay
        guard !targets.isEmpty else {
            generatedPDFDocument = nil
            return
        }

        let provType = self.providerType
        let serviceName = self.cloudServiceName
        let rootPath = self.activeRootPath
        let portal = self.portalURL

        let doc = await Task.detached(priority: .userInitiated) {
            TeacherMemoPDFGenerator.generatePDFDocument(
                students: targets,
                portalURL: portal,
                providerType: provType,
                cloudServiceName: serviceName,
                cloudFolderPath: rootPath
            )
        }.value

        await MainActor.run {
            self.generatedPDFDocument = doc
        }
    }

    /// Génère le fichier PDF à la racine du dossier Source et l'ouvre via l'OS
    private func generateAndOpenPDF() async {
        guard !studentsToDisplay.isEmpty else { return }
        isSavingPDF = true
        defer { isSavingPDF = false }

        let targets = studentsToDisplay
        guard let pdfData = TeacherMemoPDFGenerator.generatePDFData(
            students: targets,
            portalURL: portalURL,
            providerType: providerType,
            cloudServiceName: cloudServiceName,
            cloudFolderPath: activeRootPath
        ) else {
            showToast("Erreur lors de la génération du PDF.")
            return
        }

        let filename = "Droopies - Memo Acces Eleves.pdf"
        let cloudPath = "Exports/\(filename)"

        // 1. Sauvegarde dans le sous-dossier Exports dans le Cloud actif
        do {
            try? await appState.storageManager.ensureSourceFolderStructure()
            try await appState.storageManager.activeProvider.writeData(pdfData, to: cloudPath)
        } catch {
            print("Erreur écriture cloud : \(error)")
        }

        // 2. Écriture locale temporaire pour ouverture par l'OS
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try pdfData.write(to: tempURL, options: .atomic)
            self.exportedFileURL = tempURL

            await MainActor.run {
                // Fermer immédiatement la fenêtre de génération avant d'ouvrir le PDF
                dismiss()

                // Déclencher l'ouverture par l'OS
                if let onGenerated = self.onGenerated {
                    onGenerated(tempURL)
                } else {
                    #if os(macOS)
                    NSWorkspace.shared.open(tempURL)
                    #endif
                }
            }
        } catch {
            showToast("Erreur lors de l'enregistrement local : \(error.localizedDescription)")
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = msg
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    if toastMessage == msg {
                        toastMessage = nil
                    }
                }
            }
        }
    }
}
