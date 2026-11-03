//
//  KPICard.swift
//  Dropies
//
//  Carte d'indicateur clé de performance (KPI) pour le tableau de bord et la synthèse.
//

import SwiftUI

public struct KPICard: View {
    public let title: String
    public let value: String
    public var subtitle: String? = nil
    public let icon: String
    public var tintColor: Color = .blue

    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        tintColor: Color = .blue
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tintColor = tintColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(tintColor)
                    .frame(width: 28, height: 28)
                    .background(tintColor.opacity(0.12))
                    .clipShape(Circle())
            }

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundColor(.primary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.5, opacity: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
