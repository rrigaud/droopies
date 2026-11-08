//
//  CorrectionWorkflowView.swift
//  Dropies
//
//  Conteneur principal du flux de correction en 4 étapes.
//  Présente une barre flottante en verre dépoli (Liquid Glass Capsule)
//  avec transitions animées et esthétique visionOS / iPadOS 18.
//

import SwiftUI

public struct CorrectionWorkflowView: View {
    @Bindable public var appState: AppState
    @State private var currentStep: Int = 1
    @Namespace private var stepperNamespace

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if currentStep == 4 && !appState.isOnline {
                // MARK: - Écran Informateur Mode Hors-Ligne pour la Distribution
                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 90, height: 90)

                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    VStack(spacing: 10) {
                        Text("Distribution suspendue en mode Hors-Ligne")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("La distribution consiste à déposer individuellement chaque devoir annoté dans le dossier Cloud de chaque élève.\nCette opération requiert une connexion Internet active.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16))
                            Text("L'Atelier de Correction au stylet reste 100 % opérationnel hors-ligne.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "wifi")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text("Dès la reconnexion au Wi-Fi, la distribution sera immédiatement débloquée.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(18)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 68)
            } else {
                // MARK: - Vue de l'étape active normale
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
                .padding(.top, 68)

                // MARK: - Stepper Flottant VisionOS (Island Capsule)
                floatingStepper
                    .padding(.top, 14)
            }
        }
        .withLiquidGlassBackground()
    }

    // MARK: - Composant Stepper Flottant en Verre Dépoli

    private var floatingStepper: some View {
        HStack(spacing: 4) {
            stepItem(number: 1, title: "Atelier Stylet", icon: "pencil.and.outline")
            stepChevron
            stepItem(number: 2, title: "Chargement", icon: "tray.and.arrow.down.fill")
            stepChevron
            stepItem(number: 3, title: "Identification", icon: "viewfinder")
            stepChevron
            stepItem(number: 4, title: "Distribution", icon: "paperplane.fill")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(strokeOpacity: 0.45)
    }

    private var stepChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.secondary.opacity(0.4))
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func stepItem(number: Int, title: String, icon: String) -> some View {
        let isActive = currentStep == number
        let isDone = currentStep > number

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if isDone || number <= currentStep {
                    currentStep = number
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if isDone {
                        Circle()
                            .fill(Color(hex: "10B981"))
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else if isActive {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "2563EB"))
                    } else {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 22, height: 22)
                        Text("\(number)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .white : (isDone ? .primary : .secondary))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isActive {
                        Capsule()
                            .fill(LinearGradient.electricBlue)
                            .matchedGeometryEffect(id: "activePill", in: stepperNamespace)
                            .shadow(color: Color.blue.opacity(0.4), radius: 8, y: 2)
                    } else if isDone {
                        Capsule()
                            .fill(Color.green.opacity(0.08))
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
