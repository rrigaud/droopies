//
//  StudentLabelsView.swift
//  Droopies
//
//  Générateur de fiches et étiquettes de connexion découpables
//  avec QR Code personnalisé pour chaque élève.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct StudentLabelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState

    @State private var selectedClassFilter: String = "Toutes"

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredStudents: [Student] {
        if selectedClassFilter == "Toutes" {
            return appState.students
        }
        return appState.students.filter { $0.classe == selectedClassFilter }
    }

    private var portalURL: String {
        appState.settings.portalUrl.isEmpty ? "https://droopies.education" : appState.settings.portalUrl
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Barre d'outils
                HStack(spacing: 16) {
                    Picker("Classe", selection: $selectedClassFilter) {
                        Text("Toutes les classes").tag("Toutes")
                        ForEach(appState.classes) { group in
                            Text(group.name).tag(group.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)

                    Text("\(filteredStudents.count) fiche(s) à imprimer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        printLabels()
                    } label: {
                        Label("Imprimer les fiches", systemImage: "printer.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color(white: 0.5, opacity: 0.05))

                Divider()

                // Grille de cartes élèves
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(filteredStudents) { student in
                            studentCard(student)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Fiches de Connexion Élèves")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 500)
    }

    @ViewBuilder
    private func studentCard(_ student: Student) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Classe : \(student.classe)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                BadgeView(student.classe, style: .info)
            }

            Divider()

            HStack(spacing: 12) {
                // QR Code
                QRCodeView(text: "\(portalURL)?id=\(student.login)", size: 84)

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Identifiant")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(student.login)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mot de passe")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        Text(student.password)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
                Spacer()
            }

            Text("Scannez ce QR Code pour accéder à vos copies corrigées.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(Color(white: 0.5, opacity: 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func printLabels() {
        #if canImport(AppKit)
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        let printOp = NSPrintOperation(view: NSView())
        printOp.run()
        #elseif canImport(UIKit)
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Fiches_Connexion_Droopies"
        printController.printInfo = printInfo
        printController.present(animated: true, completionHandler: nil)
        #endif
    }
}
