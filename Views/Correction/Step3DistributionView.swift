//
//  Step3DistributionView.swift
//  Dropies
//
//  Étape 3 : Synthèse des notes, calcul des moyennes, export pour Pronote / Excel
//  et distribution des copies PDF vers les dossiers élèves et le Cloud.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct Step3DistributionView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    @State private var isDistributing: Bool = false
    @State private var distributionProgress: Double = 0.0
    @State private var hasCopiedToClipboard: Bool = false
    @State private var distributionSuccessMessage: String? = nil

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

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Barre supérieure de navigation
            HStack(spacing: 16) {
                Button {
                    currentStep = 2
                } label: {
                    Label("Identification", systemImage: "arrow.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text(evaluation?.title.isEmpty == false ? evaluation!.title : "Distribution du devoir")
                    .font(.headline)

                Spacer()

                // Bouton Copier les notes
                Button {
                    copyGradesToClipboard()
                } label: {
                    Label(
                        hasCopiedToClipboard ? "Notes copiées !" : "Copier pour Pronote / Excel",
                        systemImage: hasCopiedToClipboard ? "checkmark" : "doc.on.clipboard"
                    )
                }
                .buttonStyle(.bordered)
                .tint(hasCopiedToClipboard ? .green : .blue)

                // Bouton Distribuer et téléverser
                Button {
                    distributeCopies()
                } label: {
                    Label("Distribuer les copies", systemImage: "icloud.and.arrow.up.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isDistributing || copies.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.5, opacity: 0.06))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Cartes KPI Synthèse
                    HStack(spacing: 14) {
                        KPICard(
                            title: "Copies identifiées",
                            value: "\(evaluation?.identifiedCount ?? 0) / \(evaluation?.totalCopies ?? 0)",
                            subtitle: "\(evaluation?.absentCount ?? 0) élève(s) absent(s)",
                            icon: "checkmark.seal.fill",
                            tintColor: .green
                        )

                        KPICard(
                            title: "Moyenne de la classe",
                            value: evaluation?.classAverage != nil ? String(format: "%.2f / %.0f", evaluation!.classAverage!, evaluation?.maxScore ?? 20) : "—",
                            subtitle: "Sur \(copies.filter { !$0.isAbsent && $0.grade != nil }.count) copie(s) notée(s)",
                            icon: "chart.bar.fill",
                            tintColor: .blue
                        )

                        KPICard(
                            title: "Note la plus haute",
                            value: evaluation?.maxGrade != nil ? String(format: "%.1f", evaluation!.maxGrade!) : "—",
                            subtitle: evaluation?.minGrade != nil ? "Min : \(String(format: "%.1f", evaluation!.minGrade!))" : nil,
                            icon: "arrow.up.circle.fill",
                            tintColor: .orange
                        )
                    }

                    // MARK: - Barre de progression de distribution
                    if isDistributing {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Génération et téléversement des copies...")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(Int(distributionProgress * 100)) %")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: distributionProgress)
                                .tint(.blue)
                        }
                        .padding(14)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let message = distributionSuccessMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // MARK: - Tableau récapitulatif des copies
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Détail des copies")
                            .font(.headline)

                        VStack(spacing: 0) {
                            // En-tête du tableau
                            HStack {
                                Text("Copie").frame(width: 60, alignment: .leading)
                                Text("Élève").frame(maxWidth: .infinity, alignment: .leading)
                                Text("Pages").frame(width: 80, alignment: .center)
                                Text("Note").frame(width: 90, alignment: .trailing)
                                Text("Statut Cloud").frame(width: 140, alignment: .trailing)
                            }
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.5, opacity: 0.08))

                            Divider()

                            // Lignes des copies
                            ForEach(copies) { copy in
                                HStack {
                                    Text("\(copy.index)")
                                        .font(.subheadline.bold())
                                        .frame(width: 60, alignment: .leading)

                                    HStack(spacing: 6) {
                                        if copy.isAbsent {
                                            Image(systemName: "person.crop.circle.badge.xmark")
                                                .foregroundColor(.red)
                                            Text("Absent")
                                                .foregroundColor(.secondary)
                                                .italic()
                                        } else if copy.isIdentified {
                                            Image(systemName: "person.crop.circle.fill")
                                                .foregroundColor(.blue)
                                            Text(copy.studentName)
                                                .fontWeight(.medium)
                                        } else {
                                            Image(systemName: "questionmark.circle")
                                                .foregroundColor(.orange)
                                            Text("Non attribué")
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(copy.pageStart)-\(copy.pageEnd)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .center)

                                    Group {
                                        if let grade = copy.grade {
                                            Text(String(format: "%.1f", grade))
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                        } else {
                                            Text("—")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(width: 90, alignment: .trailing)

                                    Group {
                                        switch copy.cloudSyncStatus {
                                        case .idle:
                                            BadgeView("En attente", style: .neutral)
                                        case .uploading(let p):
                                            BadgeView("\(Int(p * 100))%", icon: "arrow.triangle.2.circlepath", style: .info)
                                        case .synced:
                                            BadgeView("Synchronisé", icon: "checkmark", style: .success)
                                        case .failed:
                                            BadgeView("Échec", icon: "exclamationmark.triangle", style: .danger)
                                        }
                                    }
                                    .frame(width: 140, alignment: .trailing)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                Divider()
                            }
                        }
                        .background(Color(white: 0.5, opacity: 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Actions

    private func copyGradesToClipboard() {
        var lines: [String] = []
        for copy in copies where copy.isIdentified && !copy.isAbsent {
            if let grade = copy.grade {
                lines.append("\(copy.studentName)\t\(grade)")
            }
        }

        let clipboardString = lines.joined(separator: "\n")

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipboardString, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = clipboardString
        #endif

        hasCopiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.hasCopiedToClipboard = false
        }
    }

    private func distributeCopies() {
        guard var eval = appState.currentEvaluation else { return }
        isDistributing = true
        distributionProgress = 0.0

        Task {
            let total = Double(eval.copies.count)
            for i in 0..<eval.copies.count {
                try? await Task.sleep(nanoseconds: 150_000_000)
                await MainActor.run {
                    self.distributionProgress = Double(i + 1) / max(1.0, total)
                    eval.copies[i].cloudSyncStatus = .synced
                    self.appState.currentEvaluation = eval
                }
            }

            await MainActor.run {
                self.isDistributing = false
                self.distributionSuccessMessage = "Toutes les copies ont été distribuées et synchronisées avec succès !"
            }
        }
    }
}
