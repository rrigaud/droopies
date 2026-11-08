//
//  CorrectionWorkflowView.swift
//  Droopies
//
//  Conteneur principal du flux de Distribution en 3 étapes :
//  1. Chargement des copies & Préparation
//  2. Identification OCR et association aux élèves
//  3. Envoi et synchronisation Cloud
//

import SwiftUI

public struct CorrectionWorkflowView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if !appState.isOnline {
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
                        Text("Distribution indisponible en mode Hors-Ligne")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("La distribution consiste à découper, identifier et déposer individuellement chaque devoir annoté dans le dossier Cloud de chaque élève.\nCette opération requiert une connexion Internet active pour synchroniser avec le Cloud.")
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
                            Text("La correction de copies reste 100 % opérationnelle hors-ligne.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "wifi")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text("Dès la reconnexion à Internet, la distribution sera immédiatement débloquée.")
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
                    switch appState.distributionStep {
                    case 1:
                        Step2LoadingView(appState: appState, currentStep: $appState.distributionStep)
                    case 2:
                        Step3IdentificationView(appState: appState, currentStep: $appState.distributionStep)
                    case 3:
                        Step4DistributionView(appState: appState, currentStep: $appState.distributionStep)
                    default:
                        Step2LoadingView(appState: appState, currentStep: $appState.distributionStep)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 68)
            }
        }
    }
}
