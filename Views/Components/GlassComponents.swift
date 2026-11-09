//
//  GlassComponents.swift
//  Dropies
//
//  Système de design "Liquid Glass" moderne (visionOS / iPadOS 18).
//  Fournit des arrière-plans d'ambiance à réfraction, des cartes et capsules de verre dépoli,
//  des barres d'outils flottantes, des onglets glissants et des boutons vibrants.
//

import SwiftUI

// MARK: - Extension Couleurs Hexadécimales & Dégradés Vibrants

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

public extension LinearGradient {
    static let electricBlue = LinearGradient(
        colors: [Color(hex: "2563EB"), Color(hex: "1D4ED8")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let emeraldGreen = LinearGradient(
        colors: [Color(hex: "059669"), Color(hex: "047857")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let coralOrange = LinearGradient(
        colors: [Color(hex: "EA580C"), Color(hex: "C2410C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let violetPurple = LinearGradient(
        colors: [Color(hex: "7C3AED"), Color(hex: "6D28D9")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassPrism = LinearGradient(
        colors: [
            Color.white.opacity(0.45),
            Color.white.opacity(0.12),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGray = LinearGradient(
        colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Arrière-plan Ambiant Liquid Glass
// Le secret du verre dépoli sous Apple : il faut des variations de lumière
// sous le matériau ultraThinMaterial pour qu'il réfracte et brille au lieu d'être terne !

public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            // Fond neutre doux
            if colorScheme == .dark {
                Color(hex: "0B0F19")
                    .ignoresSafeArea()
            } else {
                Color(hex: "F8FAFC")
                    .ignoresSafeArea()
            }

            // Orbes lumineuses diffuses d'ambiance
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                // Orbe Indigo / Bleue en haut à droite
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "3B82F6" : "60A5FA").opacity(colorScheme == .dark ? 0.18 : 0.14),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: max(w, h) * 0.45
                        )
                    )
                    .frame(width: max(w, h) * 0.9, height: max(w, h) * 0.9)
                    .position(x: w * 0.85, y: h * 0.15)
                    .blur(radius: 60)

                // Orbe Violette / Cyan en bas à gauche
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "8B5CF6" : "A78BFA").opacity(colorScheme == .dark ? 0.14 : 0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: max(w, h) * 0.4
                        )
                    )
                    .frame(width: max(w, h) * 0.8, height: max(w, h) * 0.8)
                    .position(x: w * 0.15, y: h * 0.85)
                    .blur(radius: 50)

                // Touche subtile Émeraude au centre
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: colorScheme == .dark ? "10B981" : "34D399").opacity(colorScheme == .dark ? 0.08 : 0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: max(w, h) * 0.35
                        )
                    )
                    .frame(width: max(w, h) * 0.6, height: max(w, h) * 0.6)
                    .position(x: w * 0.5, y: h * 0.5)
                    .blur(radius: 70)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Modificateurs Cartes & Capsules en Verre Dépoli

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var strokeOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.35) {
        self.cornerRadius = cornerRadius
        self.strokeOpacity = strokeOpacity
    }

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? strokeOpacity * 0.8 : strokeOpacity),
                                Color.white.opacity(strokeOpacity * 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 14, x: 0, y: 6)
    }
}

public struct GlassCapsuleModifier: ViewModifier {
    public var strokeOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(strokeOpacity: Double = 0.35) {
        self.strokeOpacity = strokeOpacity
    }

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.45 : 0.65),
                                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.09), radius: 8, x: 0, y: 3)
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.35) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }

    func glassCapsule(strokeOpacity: Double = 0.4) -> some View {
        self.modifier(GlassCapsuleModifier(strokeOpacity: strokeOpacity))
    }

    /// Applique l'ambiance lumineuse Liquid Glass en arrière-plan
    func withLiquidGlassBackground() -> some View {
        self.background(LiquidGlassBackground())
    }
}

// MARK: - Barre d'outils flottante en verre dépoli (Floating Glass Bar)

public struct FloatingGlassBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule(strokeOpacity: 0.45)
    }
}

// MARK: - Boutons Vibrants à Dégradés (Vibrant Action Buttons)

public struct VibrantGradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool
    public var gradient: LinearGradient
    public var isCompact: Bool

    public static let electricBlue = LinearGradient.electricBlue
    public static let emeraldGreen = LinearGradient.emeraldGreen
    public static let coralOrange = LinearGradient.coralOrange
    public static let violetPurple = LinearGradient.violetPurple
    public static let subtleGray = LinearGradient.subtleGray

    public init(gradient: LinearGradient = .electricBlue, isCompact: Bool = false) {
        self.gradient = gradient
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(isCompact ? .subheadline : .headline, weight: .semibold))
            .foregroundColor(isEnabled ? .white : .secondary)
            .padding(.horizontal, isCompact ? 14 : 20)
            .padding(.vertical, isCompact ? 8 : 12)
            .background(
                Group {
                    if isEnabled {
                        gradient
                    } else {
                        Color.primary.opacity(0.08)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isEnabled ? Color.white.opacity(0.35) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(
                color: isEnabled ? Color.blue.opacity(configuration.isPressed ? 0.15 : 0.35) : Color.clear,
                radius: configuration.isPressed ? 4 : 10,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Bouton d'outil flottant en verre dépoli (Glass Tool Button)

public struct GlassToolButton: View {
    let icon: String
    var title: String? = nil
    var isActive: Bool = false
    var tint: Color = .blue
    let action: () -> Void

    public init(
        icon: String,
        title: String? = nil,
        isActive: Bool = false,
        tint: Color = .blue,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                if let title = title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, title != nil ? 12 : 10)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isActive {
                        Capsule().fill(tint)
                    } else {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isActive ? 0.3 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bouton d'icône Liquid Glass façon Aperçu / macOS HUD (GlassHUDIconButton)

public struct GlassHUDIconButton: View {
    public let icon: String
    public let isEnabled: Bool
    public var isActive: Bool = false
    public var helpText: String? = nil
    public var size: CGFloat = 30
    public let action: () -> Void

    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init(
        icon: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        helpText: String? = nil,
        size: CGFloat = 30,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.helpText = helpText
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Fond translucide réactif avec réfraction de verre
                Circle()
                    .fill(
                        (isActive || (isHovered && isEnabled))
                        ? LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.40),
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity((isActive || isHovered) && isEnabled ? 0.75 : 0.45),
                                        Color.white.opacity((isActive || isHovered) && isEnabled ? 0.30 : 0.12),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: (isActive || isHovered) && isEnabled ? Color.white.opacity(colorScheme == .dark ? 0.25 : 0.45) : Color.clear,
                        radius: 5,
                        x: 0,
                        y: 1
                    )

                Image(systemName: icon)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundColor(isEnabled ? (isActive ? .accentColor : .primary) : .secondary.opacity(0.35))
                    .shadow(
                        color: isEnabled ? Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08) : Color.clear,
                        radius: 1,
                        x: 0,
                        y: 1
                    )
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(GlassHUDPressStyle())
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .help(helpText ?? "")
    }
}

public struct GlassHUDPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Cross-Platform Text Input Helpers

public extension View {
    @ViewBuilder
    func disableAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

