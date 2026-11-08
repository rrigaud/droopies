//
//  Step3IdentificationView.swift
//  Dropies
//
//  Étape 2 du flux de Distribution : Découpage intelligent et identification des copies.
//  Supporte la saisie rapide au clavier (Mac) et les sélecteurs natifs tactiles (iPad).
//

import SwiftUI
import PDFKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct Step3IdentificationView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    @State private var selectedCopyIndex: Int = 0
    @State private var eligibleStudents: [Student] = []
    @State private var isLoadingEligibleStudents: Bool = false

    // MARK: - États de Saisie (Élève & Note)
    @State private var selectedStudentId: Int? = nil
    @State private var selectedGrade: Double? = nil
    @State private var studentSearchText: String = ""
    @State private var gradeText: String = ""
    @State private var isShowingSuggestions: Bool = false

    // MARK: - Focus pour le flux clavier Mac
    private enum InputField: Hashable {
        case student
        case grade
    }
    @FocusState private var focusedField: InputField?

    // MARK: - Mode Mac vs iPad
    #if os(macOS)
    private var isMac: Bool { true }
    #else
    @State private var forceMacMode: Bool = CommandLine.arguments.contains("-testMacMode")
    private var isMac: Bool {
        UIDevice.current.userInterfaceIdiom == .mac || forceMacMode
    }
    #endif

    public init(appState: AppState, currentStep: Binding<Int>) {
        self.appState = appState
        self._currentStep = currentStep
    }

    // MARK: - Données de l'évaluation

    private var evaluation: Evaluation? {
        appState.currentEvaluation
    }

    private var copies: [StudentCopy] {
        evaluation?.copies ?? []
    }

    private var activeClassStudents: [Student] {
        appState.studentsInSelectedClass
    }

    /// Liste des élèves sélectionnables (avec repli de test)
    private var selectableStudents: [Student] {
        if evaluation?.isCatchUp == true, !eligibleStudents.isEmpty {
            return eligibleStudents
        }
        if !activeClassStudents.isEmpty {
            return activeClassStudents
        }
        return [
            Student(id: 1, name: "BERNARD Lucas", classe: "3e1"),
            Student(id: 2, name: "DUBOIS Chloé", classe: "3e1"),
            Student(id: 3, name: "DURAND Thomas", classe: "3e1"),
            Student(id: 4, name: "LEROY Manon", classe: "3e1"),
            Student(id: 5, name: "MOREAU Hugo", classe: "3e1"),
            Student(id: 6, name: "PETIT Emma", classe: "3e1"),
            Student(id: 7, name: "ROUX Maxime", classe: "3e1")
        ]
    }

    /// Copie actuellement sélectionnée
    private var selectedCopy: StudentCopy? {
        guard selectedCopyIndex >= 0, selectedCopyIndex < copies.count else { return nil }
        return copies[selectedCopyIndex]
    }

    // MARK: - Copies Filtrées (Non identifiées vs Identifiées)

    private var unidentifiedCopies: [StudentCopy] {
        copies.filter { !$0.isIdentified && !$0.isAbsent }
    }

    private var identifiedCopies: [StudentCopy] {
        copies.filter { $0.isIdentified || $0.isAbsent }
    }

    private var remainingCopiesCount: Int {
        unidentifiedCopies.count
    }

    private var isReadyToDistribute: Bool {
        !copies.isEmpty && remainingCopiesCount == 0
    }

    private var progressFraction: Double {
        guard !copies.isEmpty else { return 0.0 }
        return Double(identifiedCopies.count) / Double(copies.count)
    }

    // MARK: - Filtrage Mac en temps réel (dès 3 caractères)

    private var filteredStudents: [Student] {
        let query = studentSearchText.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard query.count >= 3 else { return [] }
        return selectableStudents.filter { st in
            let stName = st.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return stName.contains(query)
        }
    }

    // MARK: - Corps Principal

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Barre d'outils supérieure
            topToolbar

            Divider()

            // MARK: - 2. Poste de travail divisé 60% / 40%
            GeometryReader { geo in
                let availableWidth = max(0, geo.size.width - 24)
                let leftWidth = availableWidth * 0.60
                let rightWidth = availableWidth * 0.40

                HStack(alignment: .top, spacing: 14) {
                    // Gauche (60%) : Preview PDF de la copie sélectionnée
                    pdfPreviewBlock
                        .frame(width: leftWidth)
                        .frame(maxHeight: .infinity)

                    // Droite (40%) : Deux blocs superposés
                    VStack(spacing: 12) {
                        // Bloc 1 : Identification de la copie (sur une ligne)
                        identificationCard

                        // Bloc 2 : Liste des copies (non identifiées en haut, identifiées au-dessous)
                        copiesListCard
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: rightWidth)
                    .frame(maxHeight: .infinity)
                }
                .padding(12)
            }
        }
        .task {
            await computeEligibleStudents()
            loadCurrentCopyIntoInputs()
        }
        .onChange(of: selectedCopyIndex) { _, _ in
            loadCurrentCopyIntoInputs()
        }
    }

    // MARK: - Composant : Barre d'outils supérieure

    private var topToolbar: some View {
        HStack(spacing: 16) {
            // Bouton retour à gauche
            Button {
                currentStep = 1
            } label: {
                Label("Chargement des copies", systemImage: "arrow.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Divider().frame(height: 20)

            // Grande ProgressBar au centre
            identificationProgressBar

            // Bouton Distribution à droite
            distributionActionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Grande ProgressBar

    private var identificationProgressBar: some View {
        HStack(spacing: 12) {
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isReadyToDistribute
                                    ? [Color(hex: "10B981"), Color(hex: "059669")]
                                    : [Color(hex: "0284C7"), Color(hex: "0EA5E9")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, barGeo.size.width * CGFloat(progressFraction)), height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progressFraction)
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            Text("\(identifiedCopies.count)/\(copies.count) identifiée\(identifiedCopies.count > 1 ? "s" : "")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bouton d'Action Distribution

    private var distributionActionButton: some View {
        Group {
            if isReadyToDistribute {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentStep = 3
                    }
                } label: {
                    Label("Distribution ➔", systemImage: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))
            } else {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.ellipsis")
                            .font(.system(size: 12))
                        Text("\(remainingCopiesCount) copie\(remainingCopiesCount > 1 ? "s" : "") restante\(remainingCopiesCount > 1 ? "s" : "")...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
    }

    // MARK: - Bloc Gauche (60%) : Prévisualisation PDF (100% de la largeur)

    private var pdfPreviewBlock: some View {
        VStack(spacing: 0) {
            // En-tête de l'aperçu
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.blue)
                    .font(.system(size: 13))

                if let copy = selectedCopy {
                    Text("Aperçu : Copie \(copy.index)")
                        .font(.system(size: 13, weight: .semibold))

                    Text("•  Pages \(copy.pageStart) à \(copy.pageEnd)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    if copy.isIdentified {
                        Text("(\(copy.studentName))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("Aperçu de la copie")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.035))

            Divider()

            // Rendu PDF prenant 100% de la largeur
            if let doc = documentForSelectedCopy() {
                PDFContinuousPreviewView(document: doc)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.02))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("Aucun document chargé pour la prévisualisation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Bloc Droite 1 : "Identification de la copie" (Sur une seule ligne)

    private var identificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Titre du bloc
            HStack {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.blue)
                    .font(.system(size: 13))

                Text("Identification de la copie")
                    .font(.system(size: 13, weight: .semibold))

                if let copy = selectedCopy {
                    Text("•  Copie \(copy.index)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                #if !os(macOS)
                // Bouton bascule Mac / iPad (pour test interactif)
                Button {
                    forceMacMode.toggle()
                    if isMac { focusedField = .student }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isMac ? "macbook" : "ipad")
                            .font(.system(size: 10))
                        Text(isMac ? "Mac" : "iPad")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                #endif
            }

            // MARK: Ligne unique d'identification
            HStack(spacing: 8) {
                if isMac {
                    // Saisie Mac : Champ texte filtrable en temps réel (dès 3 lettres)
                    studentSearchFieldMac

                    // Champ note Mac
                    TextField("Note", text: $gradeText)
                        .focused($focusedField, equals: .grade)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 65)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit {
                            validateAndLinkCurrentCopy()
                        }
                } else {
                    // Saisie iPad : Picker de l'élève
                    studentPickerIPad

                    // Picker de note iPad (de 10 vers 0)
                    gradePickerIPad
                }

                // Bouton avec icône Lier / Chaîne pour valider
                Button {
                    validateAndLinkCurrentCopy()
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                .disabled(!canValidateLink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .zIndex(10) // Pour que le menu déroulant de suggestions Mac flotte au-dessus
    }

    // MARK: - Mac : Champ Élève Filtrable en temps réel

    private var studentSearchFieldMac: some View {
        ZStack(alignment: .topLeading) {
            TextField("Nom ou prénom de l'élève...", text: $studentSearchText)
                .focused($focusedField, equals: .student)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onChange(of: studentSearchText) { _, newText in
                    isShowingSuggestions = (newText.trimmingCharacters(in: .whitespaces).count >= 3)
                }
                .onSubmit {
                    handleStudentSearchSubmit()
                }
        }
        .overlay(alignment: .topLeading) {
            if isShowingSuggestions && !filteredStudents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredStudents.prefix(5)) { student in
                        Button {
                            selectStudentFromSuggestion(student)
                        } label: {
                            HStack {
                                Text(student.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(student.classe)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }
                }
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .offset(y: 34)
                .frame(width: 240)
            }
        }
    }

    // MARK: - iPad : Picker Élève (Natif dans Menu bordé)

    private var selectedStudentName: String {
        if let sid = selectedStudentId, let st = selectableStudents.first(where: { $0.id == sid }) {
            return st.name
        }
        return "Sélectionner un élève..."
    }

    private var studentPickerIPad: some View {
        Menu {
            Picker("Élève", selection: $selectedStudentId) {
                Text("Sélectionner un élève...").tag(nil as Int?)
                ForEach(selectableStudents) { student in
                    Text(student.name).tag(student.id as Int?)
                }
            }
        } label: {
            HStack {
                Text(selectedStudentName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selectedStudentId == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - iPad : Picker Note (10 vers 0)

    private var gradePickerIPad: some View {
        Menu {
            Picker("Note", selection: $selectedGrade) {
                Text("— Note —").tag(nil as Double?)
                ForEach(Array(stride(from: 10, through: 0, by: -1)), id: \.self) { val in
                    Text("\(val)").tag(Double(val) as Double?)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedGrade != nil ? (selectedGrade!.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(selectedGrade!))" : String(format: "%.1f", selectedGrade!)) : "Note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selectedGrade == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(width: 82)
    }

    // MARK: - Bloc Droite 2 : "Copies" (Non identifiées en haut, identifiées au-dessous)

    private var copiesListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Titre du bloc
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 13))

                Text("Copies (\(copies.count))")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if remainingCopiesCount > 0 {
                    Text("\(remainingCopiesCount) à identifier")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Divider()

            // Liste défilable des copies
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    // SECTION 1 : Copies NON identifiées (placées en haut, en orange)
                    if !unidentifiedCopies.isEmpty {
                        HStack {
                            Text("À IDENTIFIER (\(unidentifiedCopies.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)

                        ForEach(unidentifiedCopies) { copy in
                            unidentifiedCopyRow(copy)
                        }
                    }

                    // SECTION 2 : Copies IDENTIFIÉES (au-dessous, avec élève et note)
                    if !identifiedCopies.isEmpty {
                        HStack {
                            Text("IDENTIFIÉES (\(identifiedCopies.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                        ForEach(identifiedCopies) { copy in
                            identifiedCopyRow(copy)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Ligne Copie NON Identifiée (En Orange)

    private func unidentifiedCopyRow(_ copy: StudentCopy) -> some View {
        let isSelected = (selectedCopy?.index == copy.index)

        return Button {
            selectCopy(copy)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.ellipsis")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Copie \(copy.index)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Pages \(copy.pageStart) à \(copy.pageEnd)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("À identifier")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.orange.opacity(0.18) : Color.orange.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.orange.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ligne Copie IDENTIFIÉE (Au-dessous)

    private func identifiedCopyRow(_ copy: StudentCopy) -> some View {
        let isSelected = (selectedCopy?.index == copy.index)

        return Button {
            selectCopy(copy)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: copy.isAbsent ? "person.crop.circle.badge.xmark" : "checkmark.circle.fill")
                    .foregroundColor(copy.isAbsent ? .red : .green)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.isAbsent ? "Absent" : copy.studentName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Copie \(copy.index) • Pages \(copy.pageStart)-\(copy.pageEnd)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let grade = copy.grade {
                    Text(String(format: "%.1f / %.0f", grade, evaluation?.maxScore ?? 20))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                } else if copy.isAbsent {
                    Text("ABS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.blue.opacity(0.14) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logique d'Interaction & Validation

    private var canValidateLink: Bool {
        if isMac {
            if let sid = selectedStudentId, selectableStudents.contains(where: { $0.id == sid }) {
                return true
            }
            return filteredStudents.count == 1 || selectableStudents.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(studentSearchText.trimmingCharacters(in: .whitespaces)) == .orderedSame
            })
        } else {
            return selectedStudentId != nil
        }
    }

    private func selectCopy(_ copy: StudentCopy) {
        if let idx = copies.firstIndex(where: { $0.id == copy.id }) {
            selectedCopyIndex = idx
        }
        loadCurrentCopyIntoInputs()
    }

    private func loadCurrentCopyIntoInputs() {
        guard let copy = selectedCopy else { return }

        if let sid = copy.studentId {
            selectedStudentId = sid
            studentSearchText = copy.studentName
        } else {
            selectedStudentId = nil
            studentSearchText = ""
        }

        if let g = copy.grade {
            selectedGrade = g
            gradeText = String(format: "%.1f", g)
        } else {
            selectedGrade = nil
            gradeText = ""
        }
        isShowingSuggestions = false
    }

    private func handleStudentSearchSubmit() {
        if filteredStudents.count == 1, let unique = filteredStudents.first {
            selectStudentFromSuggestion(unique)
        } else if let exact = selectableStudents.first(where: {
            $0.name.localizedCaseInsensitiveCompare(studentSearchText.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }) {
            selectStudentFromSuggestion(exact)
        }
    }

    private func selectStudentFromSuggestion(_ student: Student) {
        selectedStudentId = student.id
        studentSearchText = student.name
        isShowingSuggestions = false
        focusedField = .grade
    }

    private func validateAndLinkCurrentCopy() {
        guard selectedCopyIndex >= 0, selectedCopyIndex < copies.count else { return }

        // Déterminer l'élève
        var targetStudent: Student? = nil
        if let sid = selectedStudentId {
            targetStudent = selectableStudents.first(where: { $0.id == sid })
        } else if isMac {
            if filteredStudents.count == 1 {
                targetStudent = filteredStudents.first
            } else {
                targetStudent = selectableStudents.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(studentSearchText.trimmingCharacters(in: .whitespaces)) == .orderedSame
                })
            }
        }

        guard let student = targetStudent else { return }

        // Déterminer la note
        let finalGrade: Double?
        if isMac {
            let clean = gradeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            finalGrade = Double(clean)
        } else {
            finalGrade = selectedGrade
        }

        // Mettre à jour la copie
        var updatedCopies = copies
        updatedCopies[selectedCopyIndex].studentId = student.id
        updatedCopies[selectedCopyIndex].studentName = student.name
        updatedCopies[selectedCopyIndex].grade = finalGrade
        updatedCopies[selectedCopyIndex].isAbsent = false
        appState.currentEvaluation?.copies = updatedCopies

        // Passer à la copie suivante : priorité aux copies non identifiées
        if let nextUnidentified = updatedCopies.indices.first(where: { $0 > selectedCopyIndex && !updatedCopies[$0].isIdentified && !updatedCopies[$0].isAbsent }) ??
           updatedCopies.indices.first(where: { !updatedCopies[$0].isIdentified && !updatedCopies[$0].isAbsent }) {
            selectedCopyIndex = nextUnidentified
        } else if selectedCopyIndex < updatedCopies.count - 1 {
            selectedCopyIndex += 1
        }

        // Recharger les champs pour la nouvelle copie
        loadCurrentCopyIntoInputs()

        // Replacer le curseur dans le champ élève en mode Mac
        if isMac {
            focusedField = .student
        }
    }

    // MARK: - Génération / Extraction du Document PDF pour la copie active

    private func documentForSelectedCopy() -> PDFDocument? {
        guard let copy = selectedCopy else { return nil }

        // Si une URL de PDF source existe, extraire ses pages pour cette copie
        if let url = evaluation?.sourcePDFURL, let masterDoc = PDFDocument(url: url) {
            let copyDoc = PDFDocument()
            var destIdx = 0
            for pageNum in copy.pageStart...copy.pageEnd {
                let pIndex = pageNum - 1
                if pIndex >= 0 && pIndex < masterDoc.pageCount, let page = masterDoc.page(at: pIndex) {
                    copyDoc.insert(page, at: destIdx)
                    destIdx += 1
                }
            }
            if copyDoc.pageCount > 0 {
                return copyDoc
            }
        }

        // Repli élégant : génération d'un PDF d'évaluation authentique en mémoire
        return makeMockPDFDocument(copy: copy)
    }

    private func makeMockPDFDocument(copy: StudentCopy) -> PDFDocument {
        let pdfDoc = PDFDocument()
        for p in copy.pageStart...copy.pageEnd {
            #if canImport(UIKit)
            let format = UIGraphicsPDFRendererFormat()
            let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
            let data = renderer.pdfData { ctx in
                ctx.beginPage()

                // Titre
                let title = "Évaluation SVT • Copie n°\(copy.index)"
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.label
                ]
                title.draw(at: CGPoint(x: 50, y: 50), withAttributes: titleAttrs)

                // Sous-titre
                let sub = "Page \(p) sur \(copy.pageEnd) • Classe \(evaluation?.className ?? "3e1")"
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                sub.draw(at: CGPoint(x: 50, y: 80), withAttributes: subAttrs)

                // Boîte En-tête Élève
                let boxRect = CGRect(x: 50, y: 110, width: 495, height: 85)
                let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                UIColor.systemGray6.setFill()
                boxPath.fill()
                UIColor.systemGray4.setStroke()
                boxPath.lineWidth = 1
                boxPath.stroke()

                let nomPrompt = "Élève : \(copy.studentName.isEmpty ? "................................................" : copy.studentName)"
                nomPrompt.draw(at: CGPoint(x: 65, y: 130), withAttributes: subAttrs)

                let notePrompt = "Note : \(copy.grade != nil ? String(format: "%.1f", copy.grade!) : "......") / \(String(format: "%.0f", evaluation?.maxScore ?? 20))"
                notePrompt.draw(at: CGPoint(x: 65, y: 158), withAttributes: subAttrs)

                // Lignes de réponses
                for lineY in stride(from: 230, through: 760, by: 36) {
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: 50, y: CGFloat(lineY)))
                    line.addLine(to: CGPoint(x: 545, y: CGFloat(lineY)))
                    UIColor.systemGray5.setStroke()
                    line.lineWidth = 0.8
                    line.stroke()
                }
            }
            if let pageDoc = PDFDocument(data: data), let page = pageDoc.page(at: 0) {
                pdfDoc.insert(page, at: pdfDoc.pageCount)
            }
            #endif
        }
        return pdfDoc
    }

    private func computeEligibleStudents() async {
        guard let eval = evaluation, eval.isCatchUp else { return }
        isLoadingEligibleStudents = true
        defer { isLoadingEligibleStudents = false }

        var eligible: [Student] = []
        for student in activeClassStudents {
            let alreadyHas = await appState.storageManager.studentHasEvaluation(student: student, evaluationTitle: eval.title)
            if !alreadyHas {
                eligible.append(student)
            }
        }
        self.eligibleStudents = eligible
    }
}
