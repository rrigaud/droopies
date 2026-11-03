//
//  CorrectionWorkflowView.swift
//  Dropies
//
//  Conteneur principal du flux de correction en 3 étapes :
//  1. Atelier de correction au stylet (Apple Pencil / PencilKit)
//  2. Découpage & Identification assistée par Vision OCR
//  3. Synthèse, export Pronote et distribution Cloud
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
            // MARK: - En-tête Stepper visuel
            HStack(spacing: 24) {
                stepIndicator(
                    number: 1,
                    title: "Atelier Stylet & Scan",
                    icon: "pencil.and.outline",
                    isActive: currentStep == 1,
                    isDone: currentStep > 1
                )

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                stepIndicator(
                    number: 2,
                    title: "Découpage & OCR",
                    icon: "viewfinder",
                    isActive: currentStep == 2,
                    isDone: currentStep > 2
                )

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                stepIndicator(
                    number: 3,
                    title: "Distribution & Synthèse",
                    icon: "paperplane.fill",
                    isActive: currentStep == 3,
                    isDone: false
                )
            }
            .padding(.horizontal, 20)
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
                    Step2IdentificationView(appState: appState, currentStep: $currentStep)
                case 3:
                    Step3DistributionView(appState: appState, currentStep: $currentStep)
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
            // Permettre de revenir en arrière ou de naviguer si l'étape est accessible
            if isDone || number <= currentStep {
                currentStep = number
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.blue : (isDone ? Color.green : Color.secondary.opacity(0.2)))
                        .frame(width: 24, height: 24)

                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isActive ? .white : .secondary)
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
