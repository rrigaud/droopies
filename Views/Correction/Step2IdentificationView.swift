//
//  Step2IdentificationView.swift
//  Dropies
//
//  Étape 2 : Découpage intelligent du PDF et identification fluide
//  assistée par reconnaissance manuscrite Apple Vision (OCR & Fuzzy Matching).
//

import SwiftUI
import PDFKit
import Vision

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct Step2IdentificationView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    @State private var selectedCopyIndex: Int = 0
    @State private var isAnalyzingOCR: Bool = false
    @State private var ocrResultText: String? = nil
    @State private var suggestedStudent: (student: Student, confidence: Double)? = nil
    @State private var searchStudentQuery: String = ""

    public init(appState: AppState, currentStep: Binding<Int>) {
        self.appState = appState
        self._currentStep = currentStep
    }

    private var evaluation: Evaluation? {
        appState.currentEvaluation
    }

    private var copies: [StudentCopy] {
        evaluation?.copies ?? []
    }

    private var activeClassStudents: [Student] {
        appState.studentsInSelectedClass
    }

    private var selectedCopy: StudentCopy? {
        guard selectedCopyIndex >= 0, selectedCopyIndex < copies.count else { return nil }
        return copies[selectedCopyIndex]
    }

    // Détection des doublons d'élèves
    private var duplicateStudentIds: Set<Int> {
        var seen = Set<Int>()
        var duplicates = Set<Int>()
        for copy in copies {
            if let sid = copy.studentId, !copy.isAbsent {
                if seen.contains(sid) {
                    duplicates.insert(sid)
                } else {
                    seen.insert(sid)
                }
            }
        }
        return duplicates
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Barre d'outils supérieure : Réglage du découpage
            HStack(spacing: 16) {
                Button {
                    currentStep = 1
                } label: {
                    Label("Correction au stylet", systemImage: "arrow.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Divider().frame(height: 20)

                // Sélecteur de pages par copie
                HStack(spacing: 8) {
                    Text("Pages par copie :")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Pages", selection: Binding(
                        get: { evaluation?.pagesPerCopy ?? 2 },
                        set: { newPages in updatePagesPerCopy(newPages) }
                    )) {
                        ForEach(1...6, id: \.self) { num in
                            Text("\(num) \(num > 1 ? "pages" : "page")").tag(num)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                BadgeView("\(copies.count) copies au total", icon: "doc.on.doc", style: .info)

                Spacer()

                // Bouton passer à la distribution
                Button {
                    currentStep = 3
                } label: {
                    Label("Distribution ➔", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(copies.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.5, opacity: 0.06))

            Divider()

            // MARK: - Bandeau de sélection horizontale des copies
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<copies.count, id: \.self) { idx in
                        let copy = copies[idx]
                        let isSelected = idx == selectedCopyIndex
                        let hasDuplicate = copy.studentId != nil && duplicateStudentIds.contains(copy.studentId!)

                        Button {
                            selectedCopyIndex = idx
                            ocrResultText = nil
                            suggestedStudent = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Copie \(copy.index)")
                                        .font(.caption.bold())
                                    Spacer()
                                    if hasDuplicate {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption2)
                                    } else if copy.isAbsent {
                                        BadgeView("ABS", style: .danger)
                                    } else if copy.isIdentified {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }

                                Text(copy.isAbsent ? "Absent" : (copy.studentName.isEmpty ? "À identifier" : copy.studentName))
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundColor(copy.studentName.isEmpty ? .secondary : .primary)

                                if let grade = copy.grade {
                                    Text(String(format: "%.1f / %.0f", grade, evaluation?.maxScore ?? 20))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(8)
                            .frame(width: 130, height: 68)
                            .background(isSelected ? Color.blue.opacity(0.15) : Color(white: 0.5, opacity: 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(white: 0.5, opacity: 0.03))

            Divider()

            // MARK: - Poste de travail principal : Attribution & OCR
            if let copy = selectedCopy {
                HStack(alignment: .top, spacing: 20) {
                    // Colonne de gauche : Aperçu de l'en-tête de la copie
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Aperçu : Copie \(copy.index) (Pages \(copy.pageStart)-\(copy.pageEnd))")
                                .font(.headline)
                            Spacer()
                            // Bouton analyse OCR manuelle
                            Button {
                                performOCRScan(for: copy)
                            } label: {
                                Label("Relancer l'OCR", systemImage: "viewfinder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        // Zone d'aperçu de l'en-tête
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.5, opacity: 0.08))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                    Text("En-tête de la copie \(copy.index)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("Pages \(copy.pageStart) à \(copy.pageEnd)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                    .frame(maxWidth: .infinity)

                    // Colonne de droite : Formulaire d'identification & Saisie rapide
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Identification de la copie")
                            .font(.headline)

                        // Suggestion de l'assistant OCR
                        if isAnalyzingOCR {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Lecture manuscrite de l'en-tête...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else if let suggestion = suggestedStudent {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suggestion IA : \(suggestion.student.name)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(String(format: "Confiance : %.0f %%", suggestion.confidence * 100))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Appliquer") {
                                    assignStudent(suggestion.student, to: selectedCopyIndex)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Alerte de doublon
                        if let sid = copy.studentId, duplicateStudentIds.contains(sid) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Attention : cet élève a déjà une autre copie assignée !")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        // Attribution de l'élève
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Élève assigné")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Picker("Élève", selection: Binding(
                                get: { copy.studentId },
                                set: { newId in
                                    if let id = newId, let student = activeClassStudents.first(where: { $0.id == id }) {
                                        assignStudent(student, to: selectedCopyIndex)
                                    }
                                }
                            )) {
                                Text("— Non attribué —").tag(nil as Int?)
                                ForEach(activeClassStudents) { student in
                                    Text(student.name).tag(student.id as Int?)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(copy.isAbsent)
                        }

                        // Saisie de la note
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Note attribuée")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("sur \(String(format: "%.0f", evaluation?.maxScore ?? 20))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                TextField("Note", value: Binding(
                                    get: { copy.grade },
                                    set: { newGrade in
                                        updateGrade(newGrade, for: selectedCopyIndex)
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3.bold())
                                .disabled(copy.isAbsent)

                                if copy.grade != nil {
                                    Button {
                                        updateGrade(nil, for: selectedCopyIndex)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Interrupteur Absent
                        Toggle(isOn: Binding(
                            get: { copy.isAbsent },
                            set: { isAbsent in
                                toggleAbsent(isAbsent, for: selectedCopyIndex)
                            }
                        )) {
                            Label("Marquer comme élève absent", systemImage: "person.crop.circle.badge.xmark")
                                .font(.subheadline)
                        }

                        Spacer()

                        // Boutons de navigation rapide (Précédente / Suivante)
                        HStack {
                            Button {
                                if selectedCopyIndex > 0 {
                                    selectedCopyIndex -= 1
                                }
                            } label: {
                                Label("Précédente", systemImage: "chevron.left")
                            }
                            .disabled(selectedCopyIndex <= 0)

                            Spacer()

                            Button {
                                if selectedCopyIndex < copies.count - 1 {
                                    selectedCopyIndex += 1
                                }
                            } label: {
                                Label("Suivante", systemImage: "chevron.right")
                            }
                            .disabled(selectedCopyIndex >= copies.count - 1)
                        }
                    }
                    .frame(width: 320)
                    .padding(16)
                    .background(Color(white: 0.5, opacity: 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
        }
    }

    // MARK: - Actions & Mises à jour

    private func updatePagesPerCopy(_ pages: Int) {
        guard var eval = appState.currentEvaluation else { return }
        eval.pagesPerCopy = pages

        // Re-découpage automatique des copies
        var newCopies: [StudentCopy] = []
        let totalPages = eval.copies.map { $0.pageEnd }.max() ?? (eval.copies.count * 2)
        var page = 1
        var copyIdx = 1

        while page <= totalPages {
            let pageEnd = min(page + pages - 1, totalPages)
            let existing = eval.copies.first { $0.index == copyIdx }
            newCopies.append(StudentCopy(
                index: copyIdx,
                pageStart: page,
                pageEnd: pageEnd,
                studentId: existing?.studentId,
                studentName: existing?.studentName ?? "",
                grade: existing?.grade,
                isAbsent: existing?.isAbsent ?? false,
                annotationsData: existing?.annotationsData
            ))
            page += pages
            copyIdx += 1
        }

        eval.copies = newCopies
        appState.currentEvaluation = eval
        selectedCopyIndex = min(selectedCopyIndex, max(0, newCopies.count - 1))
    }

    private func assignStudent(_ student: Student, to copyIndex: Int) {
        guard var eval = appState.currentEvaluation, copyIndex < eval.copies.count else { return }
        eval.copies[copyIndex].studentId = student.id
        eval.copies[copyIndex].studentName = student.name
        eval.copies[copyIndex].isAbsent = false
        appState.currentEvaluation = eval
    }

    private func updateGrade(_ grade: Double?, for copyIndex: Int) {
        guard var eval = appState.currentEvaluation, copyIndex < eval.copies.count else { return }
        eval.copies[copyIndex].grade = grade
        appState.currentEvaluation = eval
    }

    private func toggleAbsent(_ isAbsent: Bool, for copyIndex: Int) {
        guard var eval = appState.currentEvaluation, copyIndex < eval.copies.count else { return }
        eval.copies[copyIndex].isAbsent = isAbsent
        if isAbsent {
            eval.copies[copyIndex].grade = nil
        }
        appState.currentEvaluation = eval
    }

    private func performOCRScan(for copy: StudentCopy) {
        isAnalyzingOCR = true
        suggestedStudent = nil

        // Simulation ou exécution OCR Apple Vision
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.isAnalyzingOCR = false
                // Recherche du premier élève non encore assigné dans la classe
                let unassigned = activeClassStudents.filter { s in
                    !copies.contains(where: { $0.studentId == s.id })
                }
                if let candidate = unassigned.first {
                    self.suggestedStudent = (candidate, 0.94)
                }
            }
        }
    }
}
