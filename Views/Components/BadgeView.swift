//
//  BadgeView.swift
//  Dropies
//
//  Composant d'étiquette ou badge d'état arrondi (style Apple HIG).
//

import SwiftUI

public enum BadgeStyle: Sendable {
    case success
    case warning
    case danger
    case info
    case neutral

    public var backgroundColor: Color {
        switch self {
        case .success: return Color.green.opacity(0.15)
        case .warning: return Color.orange.opacity(0.15)
        case .danger: return Color.red.opacity(0.15)
        case .info: return Color.blue.opacity(0.15)
        case .neutral: return Color.secondary.opacity(0.12)
        }
    }

    public var foregroundColor: Color {
        switch self {
        case .success: return Color.green
        case .warning: return Color.orange
        case .danger: return Color.red
        case .info: return Color.blue
        case .neutral: return Color.secondary
        }
    }
}

public struct BadgeView: View {
    public let title: String
    public var icon: String? = nil
    public var style: BadgeStyle = .neutral

    public init(_ title: String, icon: String? = nil, style: BadgeStyle = .neutral) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(style.backgroundColor)
        .foregroundColor(style.foregroundColor)
        .clipShape(Capsule())
    }
}
