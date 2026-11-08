//
//  DroopiesMascotView.swift
//  Droopies
//
//  Composant d'affichage de la mascotte officielle Droopy v5 / Droopies.
//  Affiche l'image vectorielle/PNG officielle avec coins arrondis et ombre portée douce.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct DroopiesMascotView: View {
    public var size: CGFloat
    public var hasShadow: Bool
    public var isAnimated: Bool

    @State private var isBreathing: Bool = false
    @State private var isFloating: Bool = false

    public init(size: CGFloat = 40, hasShadow: Bool = true, isAnimated: Bool = false) {
        self.size = size
        self.hasShadow = hasShadow
        self.isAnimated = isAnimated
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let _ = UIImage(named: "AppLogo") {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackMascot
            }
            #elseif canImport(AppKit)
            if let _ = NSImage(named: "AppLogo") {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackMascot
            }
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.blue.opacity(hasShadow ? (isFloating ? 0.38 : 0.22) : 0.0),
            radius: size * (isFloating ? 0.18 : 0.12),
            y: size * (isFloating ? 0.08 : 0.04)
        )
        .offset(y: (isAnimated && isFloating) ? -7 : 7)
        .scaleEffect((isAnimated && isBreathing) ? 1.05 : 0.98)
        .onAppear {
            if isAnimated {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    isFloating = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }

    private var fallbackMascot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "2563EB"), Color(hex: "1D4ED8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
