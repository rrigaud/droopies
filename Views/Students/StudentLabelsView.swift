//
//  StudentLabelsView.swift
//  Droopies
//
//  Aperçu réel et générateur de PDF des étiquettes de connexion (QR).
//  Supporte la découpe en 2 étiquettes par ligne, le saut de page automatique par classe,
//  la validation obligatoire des partages Cloud avant génération, et l'enregistrement
//  à la racine du dossier Source avec ouverture directe dans l'OS.
//

import SwiftUI
import PDFKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct StudentLabelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState
    public let targetStudentIds: Set<Int>?
    public let onGenerated: ((URL) -> Void)?

    @State private var generatedPDFDocument: PDFDocument? = nil
    @State private var isRenderingPDF: Bool = false
    @State private var isSavingPDF: Bool = false
    @State private var isActivatingShares: Bool = false
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

    // MARK: - Filtrage des élèves
    private var studentsToDisplay: [Student] {
        var baseList = appState.students
        if let targets = targetStudentIds, !targets.isEmpty {
            baseList = baseList.filter { targets.contains($0.id) }
        }
        return baseList
    }

    // Élèves sans lien de partage Cloud actif
    private var studentsMissingShare: [Student] {
        studentsToDisplay.filter { $0.urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var canGeneratePDF: Bool {
        !studentsToDisplay.isEmpty && studentsMissingShare.isEmpty
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Barre d'outils supérieure
                toolbarHeader

                // MARK: - Bannière d'avertissement si partages manquants
                if !studentsMissingShare.isEmpty {
                    missingSharesBanner
                }

                Divider()

                // MARK: - Zone Principale : Vrai Aperçu PDF (PDFView)
                ZStack {
                    Color(white: 0.94)
                        .ignoresSafeArea()

                    if isRenderingPDF {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Génération de l'aperçu PDF...")
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
            .navigationTitle(appState.t(.labelsBatchTitle))
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
                if !studentsMissingShare.isEmpty {
                    await activateMissingShares()
                }
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
            // Compteur d'étiquettes
            HStack(spacing: 6) {
                Text("\(studentsToDisplay.count)")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())

                Text("étiquette(s)")
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
            .disabled(!canGeneratePDF || isSavingPDF || isActivatingShares)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bannière d'avertissement Partages Inactifs

    private var missingSharesBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Synchronisation automatique des partages Cloud en cours (\(studentsMissingShare.count))...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Droopies génère automatiquement les liens Cloud nécessaires aux QR Codes...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isActivatingShares {
                Button {
                    Task { await activateMissingShares() }
                } label: {
                    Text("Relancer")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.08))
    }

    // MARK: - Actions Métier

    /// Rendu réactif de l'aperçu PDF haute fidélité
    private func renderPreviewPDF() async {
        isRenderingPDF = true
        defer { isRenderingPDF = false }

        let targets = studentsToDisplay
        guard !targets.isEmpty else {
            generatedPDFDocument = nil
            return
        }

        // Exécution en tâche de fond pour garantir la fluidité de l'UI
        let doc = await Task.detached(priority: .userInitiated) {
            StudentLabelsPDFGenerator.generatePDFDocument(
                students: targets,
                portalURL: portalURL
            )
        }.value

        await MainActor.run {
            self.generatedPDFDocument = doc
        }
    }

    /// Active en 1 clic les dossiers et liens Cloud manquants
    private func activateMissingShares() async {
        isActivatingShares = true
        defer { isActivatingShares = false }

        do {
            let updated = try await appState.storageManager.ensureStudentFolders(students: appState.students)
            await MainActor.run {
                appState.students = updated
                showToast("Dossiers et liens de partage activés avec succès !")
            }
            await renderPreviewPDF()
        } catch {
            await MainActor.run {
                showToast("Erreur lors de l'activation des partages : \(error.localizedDescription)")
            }
        }
    }

    /// Génère le fichier PDF à la racine du dossier Source et l'ouvre via l'OS
    private func generateAndOpenPDF() async {
        guard canGeneratePDF else { return }
        isSavingPDF = true
        defer { isSavingPDF = false }

        let targets = studentsToDisplay
        guard let pdfData = StudentLabelsPDFGenerator.generatePDFData(students: targets, portalURL: portalURL) else {
            showToast("Erreur lors de la génération du PDF.")
            return
        }

        let filename = "Droopies - Etiquettes de connexion.pdf"
        let cloudPath = "Exports/\(filename)"

        // 1. Sauvegarde dans le sous-dossier Exports dans le Cloud actif
        do {
            try? await appState.storageManager.ensureSourceFolderStructure()
            try await appState.storageManager.activeProvider.writeData(pdfData, to: cloudPath)
        } catch {
            // Continuer même si le cloud renvoie une erreur mineure pour ouvrir le fichier local
            print("Erreur écriture cloud : \(error)")
        }

        // 2. Écriture dans le répertoire temporaire pour ouverture par l'OS
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
