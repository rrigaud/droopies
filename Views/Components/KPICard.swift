//
//  KPICard.swift
//  Dropies
//
//  Carte d'indicateur clé de performance (KPI) au style Liquid Glass.
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(tintColor)
                    .frame(width: 30, height: 30)
                    .background(tintColor.opacity(0.16))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(tintColor.opacity(0.3), lineWidth: 1)
                    )
            }

            Text(value)
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundColor(.primary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14)
    }
}
