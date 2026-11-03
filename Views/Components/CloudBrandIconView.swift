//
//  CloudBrandIconView.swift
//  Dropies
//
//  Composant vectoriel natif haute fidélité rendant les logos officiels
//  des 4 services Cloud supportés par Dropies :
//  - Dropbox : les 5 facettes isométriques officielles (Dropbox Blue #0061FF)
//  - Google Drive : le ruban triangulaire tricolore officiel (Bleu, Jaune, Vert)
//  - Microsoft OneDrive : le double nuage Fluent Design superposé (Azur #0078D4)
//  - Nextcloud : l'emblème officiel aux 3 anneaux connectés (Nextcloud Blue #0082C9)
//

import SwiftUI

public struct CloudBrandIconView: View {
    public let type: AppSettings.StorageProviderType
    public var size: CGFloat
    public var isSelected: Bool

    public init(
        type: AppSettings.StorageProviderType,
        size: CGFloat = 26,
        isSelected: Bool = false
    ) {
        self.type = type
        self.size = size
        self.isSelected = isSelected
    }

    public var body: some View {
        Group {
            switch type {
            case .dropbox:
                DropboxOfficialLogo(size: size, isSelected: isSelected)
            case .googleDrive:
                GoogleDriveOfficialLogo(size: size)
            case .oneDrive:
                OneDriveOfficialLogo(size: size)
            case .nextcloud:
                NextcloudOfficialLogo(size: size)
            case .local:
                Image(systemName: "internaldrive.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 1. Logo Officiel Dropbox (5 facettes isométriques)

public struct DropboxOfficialLogo: View {
    public var size: CGFloat = 26
    public var isSelected: Bool = false

    public init(size: CGFloat = 26, isSelected: Bool = false) {
        self.size = size
        self.isSelected = isSelected
    }

    private var fillColor: Color {
        if isSelected {
            return .white
        }
        return Color(red: 0.0, green: 0.38, blue: 1.0) // #0061FF officiel Dropbox
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sx = w / 100.0
            let sy = h / 100.0

            ZStack {
                // Facette 1 : Haut-Gauche
                Path { p in
                    p.move(to: CGPoint(x: 25 * sx, y: 10 * sy))
                    p.addLine(to: CGPoint(x: 0 * sx, y: 26 * sy))
                    p.addLine(to: CGPoint(x: 23 * sx, y: 44 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 25 * sy))
                    p.closeSubpath()
                }
                .fill(fillColor)

                // Facette 2 : Haut-Droite
                Path { p in
                    p.move(to: CGPoint(x: 75 * sx, y: 10 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 25 * sy))
                    p.addLine(to: CGPoint(x: 77 * sx, y: 44 * sy))
                    p.addLine(to: CGPoint(x: 100 * sx, y: 26 * sy))
                    p.closeSubpath()
                }
                .fill(fillColor)

                // Facette 3 : Bas-Gauche
                Path { p in
                    p.move(to: CGPoint(x: 0 * sx, y: 58 * sy))
                    p.addLine(to: CGPoint(x: 25 * sx, y: 74 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 58 * sy))
                    p.addLine(to: CGPoint(x: 28 * sx, y: 41 * sy))
                    p.closeSubpath()
                }
                .fill(fillColor)

                // Facette 4 : Bas-Droite
                Path { p in
                    p.move(to: CGPoint(x: 100 * sx, y: 58 * sy))
                    p.addLine(to: CGPoint(x: 72 * sx, y: 41 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 58 * sy))
                    p.addLine(to: CGPoint(x: 75 * sx, y: 74 * sy))
                    p.closeSubpath()
                }
                .fill(fillColor)

                // Facette 5 : Centre inférieur (boîte ouverte)
                Path { p in
                    p.move(to: CGPoint(x: 25 * sx, y: 80 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 96 * sy))
                    p.addLine(to: CGPoint(x: 75 * sx, y: 80 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 64 * sy))
                    p.closeSubpath()
                }
                .fill(fillColor)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

// MARK: - 2. Logo Officiel Google Drive (Ruban tricolore Möbius)

public struct GoogleDriveOfficialLogo: View {
    public var size: CGFloat = 26

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sx = w / 100.0
            let sy = h / 90.0

            ZStack {
                // Ruban Bleu (côté gauche)
                Path { p in
                    p.move(to: CGPoint(x: 35 * sx, y: 6 * sy))
                    p.addLine(to: CGPoint(x: 8 * sx, y: 54 * sy))
                    p.addLine(to: CGPoint(x: 23 * sx, y: 80 * sy))
                    p.addLine(to: CGPoint(x: 50 * sx, y: 32 * sy))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.15, green: 0.52, blue: 0.96)) // #2684FF

                // Ruban Jaune (côté bas horizontal)
                Path { p in
                    p.move(to: CGPoint(x: 23 * sx, y: 80 * sy))
                    p.addLine(to: CGPoint(x: 77 * sx, y: 80 * sy))
                    p.addLine(to: CGPoint(x: 92 * sx, y: 54 * sy))
                    p.addLine(to: CGPoint(x: 38 * sx, y: 54 * sy))
                    p.closeSubpath()
                }
                .fill(Color(red: 1.0, green: 0.73, blue: 0.0)) // #FFBA00

                // Ruban Vert (côté droit descendant)
                Path { p in
                    p.move(to: CGPoint(x: 35 * sx, y: 6 * sy))
                    p.addLine(to: CGPoint(x: 65 * sx, y: 6 * sy))
                    p.addLine(to: CGPoint(x: 92 * sx, y: 54 * sy))
                    p.addLine(to: CGPoint(x: 62 * sx, y: 54 * sy))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.0, green: 0.67, blue: 0.28)) // #00AC47
            }
        }
        .aspectRatio(100.0 / 90.0, contentMode: .fit)
    }
}

// MARK: - 3. Logo Officiel Microsoft OneDrive (Double Nuage Azur Fluent)

public struct OneDriveOfficialLogo: View {
    public var size: CGFloat = 26

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let s = min(w, h) / 100.0

            ZStack {
                // Nuage Arrière (Bleu Azur ciel #00A4EF -> #0078D4)
                Canvas { context, _ in
                    let skyGradient = Gradient(colors: [
                        Color(red: 0.0, green: 0.64, blue: 0.94),
                        Color(red: 0.0, green: 0.47, blue: 0.83)
                    ])

                    var path = Path()
                    // Cercle haut gauche arrière
                    path.addEllipse(in: CGRect(x: 24 * s, y: 22 * s, width: 34 * s, height: 34 * s))
                    // Cercle haut droit arrière
                    path.addEllipse(in: CGRect(x: 48 * s, y: 14 * s, width: 38 * s, height: 38 * s))
                    // Base arrière
                    path.addRoundedRect(in: CGRect(x: 18 * s, y: 34 * s, width: 68 * s, height: 26 * s), cornerSize: CGSize(width: 13 * s, height: 13 * s))

                    context.fill(path, with: .linearGradient(skyGradient, startPoint: CGPoint(x: 30 * s, y: 15 * s), endPoint: CGPoint(x: 70 * s, y: 60 * s)))
                }

                // Nuage Avant (Bleu Profond Microsoft #0078D4 -> #004E8C)
                Canvas { context, _ in
                    let deepGradient = Gradient(colors: [
                        Color(red: 0.0, green: 0.47, blue: 0.83),
                        Color(red: 0.0, green: 0.31, blue: 0.55)
                    ])

                    var path = Path()
                    // Cercle avant gauche
                    path.addEllipse(in: CGRect(x: 8 * s, y: 44 * s, width: 34 * s, height: 34 * s))
                    // Cercle avant centre
                    path.addEllipse(in: CGRect(x: 30 * s, y: 32 * s, width: 44 * s, height: 44 * s))
                    // Cercle avant droit
                    path.addEllipse(in: CGRect(x: 62 * s, y: 46 * s, width: 32 * s, height: 32 * s))
                    // Base avant
                    path.addRoundedRect(in: CGRect(x: 8 * s, y: 52 * s, width: 84 * s, height: 26 * s), cornerSize: CGSize(width: 13 * s, height: 13 * s))

                    context.fill(path, with: .linearGradient(deepGradient, startPoint: CGPoint(x: 20 * s, y: 35 * s), endPoint: CGPoint(x: 80 * s, y: 80 * s)))
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

// MARK: - 4. Logo Officiel Nextcloud (3 Anneaux Connectés sur Bleu Éducation)

public struct NextcloudOfficialLogo: View {
    public var size: CGFloat = 26

    public init(size: CGFloat = 26) {
        self.size = size
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let s = min(w, h) / 100.0

            ZStack {
                // Fond circulaire ou coussin Nextcloud Blue (#0082C9)
                Circle()
                    .fill(Color(red: 0.0, green: 0.51, blue: 0.79)) // #0082C9 officiel

                // 3 Anneaux blancs connectés
                ZStack {
                    // Anneau Central (Grand)
                    Circle()
                        .stroke(Color.white, lineWidth: 5.5 * s)
                        .frame(width: 38 * s, height: 38 * s)

                    // Anneau Gauche (Moyen)
                    Circle()
                        .stroke(Color.white, lineWidth: 4.5 * s)
                        .frame(width: 25 * s, height: 25 * s)
                        .offset(x: -24 * s)

                    // Anneau Droit (Moyen)
                    Circle()
                        .stroke(Color.white, lineWidth: 4.5 * s)
                        .frame(width: 25 * s, height: 25 * s)
                        .offset(x: 24 * s)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}
