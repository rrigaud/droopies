//
//  CorrectionWorkflowView.swift
//  Dropies
//
//  Conteneur principal du flux de correction en 4 étapes :
//  1. Atelier de correction au stylet (Apple Pencil / PencilKit & paquets A corriger)
//  2. Chargement des copies & Préparation (Nouvelle évaluation ou Rattrapage d'absents)
//  3. Découpage & Identification assistée par Vision OCR (filtrage des élèves absents)
//  4. Distribution, fusion du backup et envoi Cloud en arrière-plan
//

import SwiftUI

public struct CorrectionWorkflowView: View {
    @Bindable public var appState: AppState
    @State private var currentStep: Int = 1

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - En-tête Stepper visuel à 4 étapes
            HStack(spacing: 16) {
                stepIndicator(
                    number: 1,
                    title: "1. Atelier Stylet",
                    icon: "pencil.and.outline",
                    isActive: currentStep == 1,
                    isDone: currentStep > 1
                )

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                stepIndicator(
                    number: 2,
                    title: "2. Chargement des copies",
                    icon: "tray.and.arrow.down.fill",
                    isActive: currentStep == 2,
                    isDone: currentStep > 2
                )

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                stepIndicator(
                    number: 3,
                    title: "3. Découpage & OCR",
                    icon: "viewfinder",
                    isActive: currentStep == 3,
                    isDone: currentStep > 3
                )

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                stepIndicator(
                    number: 4,
                    title: "4. Distribution",
                    icon: "paperplane.fill",
                    isActive: currentStep == 4,
                    isDone: false
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.5, opacity: 0.04))

            Divider()

            // MARK: - Vue de l'étape active
            Group {
                switch currentStep {
                case 1:
                    Step1CorrectionStudioView(appState: appState, currentStep: $currentStep)
                case 2:
                    Step2LoadingView(appState: appState, currentStep: $currentStep)
                case 3:
                    Step3IdentificationView(appState: appState, currentStep: $currentStep)
                case 4:
                    Step4DistributionView(appState: appState, currentStep: $currentStep)
                default:
                    Step1CorrectionStudioView(appState: appState, currentStep: $currentStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func stepIndicator(number: Int, title: String, icon: String, isActive: Bool, isDone: Bool) -> some View {
        Button {
            // Permettre la navigation fluide entre étapes accessibles
            if isDone || number <= currentStep {
                currentStep = number
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.blue : (isDone ? Color.green : Color.secondary.opacity(0.2)))
                        .frame(width: 22, height: 22)

                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isActive ? .white : .secondary)
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
