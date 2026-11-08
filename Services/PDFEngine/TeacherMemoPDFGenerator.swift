//
//  TeacherMemoPDFGenerator.swift
//  Droopies
//
//  Générateur de PDF haute définition pour le Mémo des Accès Élèves.
//  Format A4, mise en page compacte, sobre et ultra-lisible (jusqu'à 36 élèves par page A4).
//  Tableau récapitulatif des identifiants, mots de passe, classes et statuts de partage Cloud.
//  Affiche le service Cloud utilisé (avec son icône) et le dossier source en en-tête.
//  Rendu vectoriel direct multiplateforme via CoreText.
//

import Foundation
import CoreGraphics
import CoreText
import PDFKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public final class TeacherMemoPDFGenerator: @unchecked Sendable {

    // MARK: - Dimensions Page A4 standard (72 DPI)
    public static let pageWidth: CGFloat = 595.2   // A4 Width
    public static let pageHeight: CGFloat = 841.8  // A4 Height

    public static let marginX: CGFloat = 36.0
    public static let marginTop: CGFloat = 32.0
    public static let marginBottom: CGFloat = 30.0

    // Largeur utile
    public static let contentWidth: CGFloat = pageWidth - (marginX * 2) // 523.2 pt

    // MARK: - Hauteurs & Grille
    public static let headerDocHeight: CGFloat = 52.0
    public static let tableHeaderHeight: CGFloat = 20.0
    public static let rowHeight: CGFloat = 19.0 // 19 pt permet jusqu'à 36 élèves sur 1 seule page A4 !
    public static let footerHeight: CGFloat = 18.0

    // MARK: - Palette Couleurs Graphiques (CGColor sRGB)
    private static let colorNavy = CGColor(srgbRed: 0.10, green: 0.20, blue: 0.45, alpha: 1.0)
    private static let colorBlue = CGColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0)
    private static let colorDarkText = CGColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 1.0)
    private static let colorSubText = CGColor(srgbRed: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
    private static let colorHeaderBg = CGColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
    private static let colorBorder = CGColor(srgbRed: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
    private static let colorRowAlt = CGColor(srgbRed: 0.975, green: 0.985, blue: 0.995, alpha: 1.0)
    private static let colorRowWhite = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    private static let colorSuccess = CGColor(srgbRed: 0.12, green: 0.65, blue: 0.35, alpha: 1.0)

    // MARK: - Colonnes du tableau (Total = 523.2 pt)
    public static let colClassWidth: CGFloat = 55.0
    public static let colNameWidth: CGFloat = 175.0
    public static let colLoginWidth: CGFloat = 125.0
    public static let colPasswordWidth: CGFloat = 115.0
    public static let colCloudWidth: CGFloat = 53.2

    // MARK: - Typographie CoreText

    public enum FontStyle {
        case regular, bold, mono
        var fontName: String {
            switch self {
            case .regular: return "Helvetica"
            case .bold: return "Helvetica-Bold"
            case .mono: return "Courier-Bold"
            }
        }
    }

    public enum TextAlign {
        case left, center, right
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat,
        style: FontStyle = .regular,
        color: CGColor,
        alignment: TextAlign = .left,
        in context: CGContext
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = CTFontCreateWithName(style.fontName as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        var drawX = x
        if alignment == .center {
            drawX = x - (width / 2.0)
        } else if alignment == .right {
            drawX = x - width
        }

        let baselineY = y + ascent

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.textPosition = CGPoint(x: drawX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()

        return width
    }

    // MARK: - Rendu Vectoriel des Logos Officiels Cloud (Identique Splash & Settings)

    /// Dessine le logo officiel de la marque Cloud choisie en pur vectoriel Quartz haute résolution
    public static func drawCloudBrandLogo(
        providerType: AppSettings.StorageProviderType,
        in context: CGContext,
        rect: CGRect
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let x = rect.origin.x
        let y = rect.origin.y
        let w = rect.size.width
        let h = rect.size.height

        switch providerType {
        case .dropbox:
            // 5 Facettes Isométriques Officielles Dropbox (#0061FF)
            let sx = w / 100.0
            let sy = h / 100.0
            let colorDropbox = CGColor(srgbRed: 0.0, green: 0.38, blue: 1.0, alpha: 1.0)
            context.setFillColor(colorDropbox)

            // Facette 1 : Haut-Gauche
            context.beginPath()
            context.move(to: CGPoint(x: x + 25 * sx, y: y + 10 * sy))
            context.addLine(to: CGPoint(x: x + 0 * sx, y: y + 26 * sy))
            context.addLine(to: CGPoint(x: x + 23 * sx, y: y + 44 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 25 * sy))
            context.closePath()
            context.fillPath()

            // Facette 2 : Haut-Droite
            context.beginPath()
            context.move(to: CGPoint(x: x + 75 * sx, y: y + 10 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 25 * sy))
            context.addLine(to: CGPoint(x: x + 77 * sx, y: y + 44 * sy))
            context.addLine(to: CGPoint(x: x + 100 * sx, y: y + 26 * sy))
            context.closePath()
            context.fillPath()

            // Facette 3 : Bas-Gauche
            context.beginPath()
            context.move(to: CGPoint(x: x + 0 * sx, y: y + 58 * sy))
            context.addLine(to: CGPoint(x: x + 25 * sx, y: y + 74 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 58 * sy))
            context.addLine(to: CGPoint(x: x + 28 * sx, y: y + 41 * sy))
            context.closePath()
            context.fillPath()

            // Facette 4 : Bas-Droite
            context.beginPath()
            context.move(to: CGPoint(x: x + 100 * sx, y: y + 58 * sy))
            context.addLine(to: CGPoint(x: x + 72 * sx, y: y + 41 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 58 * sy))
            context.addLine(to: CGPoint(x: x + 75 * sx, y: y + 74 * sy))
            context.closePath()
            context.fillPath()

            // Facette 5 : Boîte inférieure
            context.beginPath()
            context.move(to: CGPoint(x: x + 25 * sx, y: y + 80 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 96 * sy))
            context.addLine(to: CGPoint(x: x + 75 * sx, y: y + 80 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 64 * sy))
            context.closePath()
            context.fillPath()

        case .googleDrive:
            // Ruban tricolore officiel Möbius (Bleu #2684FF, Jaune #FFBA00, Vert #00AC47)
            let sx = w / 100.0
            let sy = h / 90.0

            // Ruban Bleu
            let colorBlue = CGColor(srgbRed: 0.15, green: 0.52, blue: 0.96, alpha: 1.0)
            context.setFillColor(colorBlue)
            context.beginPath()
            context.move(to: CGPoint(x: x + 35 * sx, y: y + 6 * sy))
            context.addLine(to: CGPoint(x: x + 8 * sx, y: y + 54 * sy))
            context.addLine(to: CGPoint(x: x + 23 * sx, y: y + 80 * sy))
            context.addLine(to: CGPoint(x: x + 50 * sx, y: y + 32 * sy))
            context.closePath()
            context.fillPath()

            // Ruban Jaune
            let colorYellow = CGColor(srgbRed: 1.0, green: 0.73, blue: 0.0, alpha: 1.0)
            context.setFillColor(colorYellow)
            context.beginPath()
            context.move(to: CGPoint(x: x + 23 * sx, y: y + 80 * sy))
            context.addLine(to: CGPoint(x: x + 77 * sx, y: y + 80 * sy))
            context.addLine(to: CGPoint(x: x + 92 * sx, y: y + 54 * sy))
            context.addLine(to: CGPoint(x: x + 38 * sx, y: y + 54 * sy))
            context.closePath()
            context.fillPath()

            // Ruban Vert
            let colorGreen = CGColor(srgbRed: 0.0, green: 0.67, blue: 0.28, alpha: 1.0)
            context.setFillColor(colorGreen)
            context.beginPath()
            context.move(to: CGPoint(x: x + 35 * sx, y: y + 6 * sy))
            context.addLine(to: CGPoint(x: x + 65 * sx, y: y + 6 * sy))
            context.addLine(to: CGPoint(x: x + 92 * sx, y: y + 54 * sy))
            context.addLine(to: CGPoint(x: x + 62 * sx, y: y + 54 * sy))
            context.closePath()
            context.fillPath()

        case .oneDrive:
            // Double Nuage Azur Fluent
            let s = min(w, h) / 100.0

            // Nuage arrière (Ciel #00A4EF)
            let colorSky = CGColor(srgbRed: 0.0, green: 0.64, blue: 0.94, alpha: 1.0)
            context.setFillColor(colorSky)
            context.fillEllipse(in: CGRect(x: x + 24 * s, y: y + 22 * s, width: 34 * s, height: 34 * s))
            context.fillEllipse(in: CGRect(x: x + 48 * s, y: y + 14 * s, width: 38 * s, height: 38 * s))
            let pathBack = CGPath(roundedRect: CGRect(x: x + 18 * s, y: y + 34 * s, width: 68 * s, height: 26 * s), cornerWidth: 13 * s, cornerHeight: 13 * s, transform: nil)
            context.addPath(pathBack)
            context.fillPath()

            // Nuage avant (Azur Profond #0078D4)
            let colorDeep = CGColor(srgbRed: 0.0, green: 0.47, blue: 0.83, alpha: 1.0)
            context.setFillColor(colorDeep)
            context.fillEllipse(in: CGRect(x: x + 8 * s, y: y + 44 * s, width: 34 * s, height: 34 * s))
            context.fillEllipse(in: CGRect(x: x + 30 * s, y: y + 32 * s, width: 44 * s, height: 44 * s))
            context.fillEllipse(in: CGRect(x: x + 62 * s, y: y + 46 * s, width: 32 * s, height: 32 * s))
            let pathFront = CGPath(roundedRect: CGRect(x: x + 8 * s, y: y + 52 * s, width: 84 * s, height: 26 * s), cornerWidth: 13 * s, cornerHeight: 13 * s, transform: nil)
            context.addPath(pathFront)
            context.fillPath()

        case .nextcloud:
            // Écusson Nextcloud Blue (#0082C9) avec 3 anneaux connectés
            let s = min(w, h) / 100.0
            let colorNextcloud = CGColor(srgbRed: 0.0, green: 0.51, blue: 0.79, alpha: 1.0)
            context.setFillColor(colorNextcloud)
            context.fillEllipse(in: rect)

            // Anneaux blancs
            let colorWhite = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            context.setStrokeColor(colorWhite)

            // Anneau central
            context.setLineWidth(5.5 * s)
            let cx = x + (w / 2.0)
            let cy = y + (h / 2.0)
            context.strokeEllipse(in: CGRect(x: cx - 19 * s, y: cy - 19 * s, width: 38 * s, height: 38 * s))

            // Anneaux gauche et droit
            context.setLineWidth(4.5 * s)
            context.strokeEllipse(in: CGRect(x: cx - 24 * s - 12.5 * s, y: cy - 12.5 * s, width: 25 * s, height: 25 * s))
            context.strokeEllipse(in: CGRect(x: cx + 24 * s - 12.5 * s, y: cy - 12.5 * s, width: 25 * s, height: 25 * s))

        case .local:
            let colorGray = CGColor(srgbRed: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
            context.setFillColor(colorGray)
            let diskPath = CGPath(roundedRect: CGRect(x: x + 2, y: y + 3, width: w - 4, height: h - 6), cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(diskPath)
            context.fillPath()
        }
    }

    // MARK: - Génération Principale

    /// Génère le document PDF complet sous forme de `PDFDocument`
    public static func generatePDFDocument(
        students: [Student],
        portalURL: String,
        providerType: AppSettings.StorageProviderType = .dropbox,
        cloudServiceName: String = "Dropbox",
        cloudFolderPath: String = "/Test",
        schoolYear: String = AppSettings.currentSchoolYear
    ) -> PDFDocument? {
        guard let data = generatePDFData(
            students: students,
            portalURL: portalURL,
            providerType: providerType,
            cloudServiceName: cloudServiceName,
            cloudFolderPath: cloudFolderPath,
            schoolYear: schoolYear
        ) else {
            return nil
        }
        return PDFDocument(data: data)
    }

    /// Génère les données brutes PDF (`Data`)
    public static func generatePDFData(
        students: [Student],
        portalURL: String,
        providerType: AppSettings.StorageProviderType = .dropbox,
        cloudServiceName: String = "Dropbox",
        cloudFolderPath: String = "/Test",
        schoolYear: String = AppSettings.currentSchoolYear
    ) -> Data? {
        guard !students.isEmpty else { return nil }

        // 1. Grouper par classe pour assurer un saut de page propre par classe
        let grouped = Dictionary(grouping: students, by: { $0.classe.isEmpty ? "Sans_Classe" : $0.classe })
        let sortedClasses = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Calcul du nombre de lignes max par page
        let tableAvailableHeight = pageHeight - marginTop - headerDocHeight - tableHeaderHeight - footerHeight - marginBottom
        let rowsPerPage = Int(floor(tableAvailableHeight / rowHeight)) // ~36 élèves

        // Déterminer le nombre total de pages à l'avance pour la pagination Page X / Y
        var totalPages = 0
        for c in sortedClasses {
            let count = grouped[c]?.count ?? 0
            totalPages += max(1, (count + rowsPerPage - 1) / rowsPerPage)
        }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "fr_FR")
        let formattedDate = dateFormatter.string(from: Date())

        var currentPage = 1

        for classe in sortedClasses {
            guard let classStudents = grouped[classe], !classStudents.isEmpty else { continue }
            let sorted = classStudents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let chunks = stride(from: 0, to: sorted.count, by: rowsPerPage).map {
                Array(sorted[$0..<min($0 + rowsPerPage, sorted.count)])
            }

            for chunk in chunks {
                context.beginPDFPage(nil)

                // Inversion Quartz (origine en haut à gauche)
                context.saveGState()
                context.translateBy(x: 0, y: pageHeight)
                context.scaleBy(x: 1.0, y: -1.0)

                // 1. En-tête du document avec identification Cloud officielle et Dossier source
                drawDocumentHeader(
                    in: context,
                    schoolYear: schoolYear,
                    portalURL: portalURL,
                    cloudServiceName: cloudServiceName,
                    providerType: providerType,
                    cloudFolderPath: cloudFolderPath
                )

                // 2. En-tête du tableau
                let tableStartY = marginTop + headerDocHeight
                drawTableHeader(in: context, startY: tableStartY)

                // 3. Lignes d'élèves (alternance blanc/gris très doux)
                var currentY = tableStartY + tableHeaderHeight
                for (index, student) in chunk.enumerated() {
                    drawStudentRow(
                        in: context,
                        student: student,
                        y: currentY,
                        isAlternate: index % 2 != 0
                    )
                    currentY += rowHeight
                }

                // Bordure globale du tableau
                let totalTableHeight = tableHeaderHeight + CGFloat(chunk.count) * rowHeight
                let tableRect = CGRect(x: marginX, y: tableStartY, width: contentWidth, height: totalTableHeight)
                context.setStrokeColor(colorBorder)
                context.setLineWidth(0.8)
                context.stroke(tableRect)

                // 4. Pied de page
                drawFooter(
                    in: context,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    dateString: formattedDate
                )

                context.restoreGState()
                context.endPDFPage()

                currentPage += 1
            }
        }

        context.closePDF()
        return pdfData as Data
    }

    // MARK: - En-tête du Document

    private static func drawDocumentHeader(
        in context: CGContext,
        schoolYear: String,
        portalURL: String,
        cloudServiceName: String,
        providerType: AppSettings.StorageProviderType,
        cloudFolderPath: String
    ) {
        // A. Côté Gauche : Titre officiel & Portail
        drawText("DROOPIES • MÉMO DES ACCÈS ÉLÈVES", x: marginX, y: marginTop, fontSize: 13.0, style: .bold, color: colorNavy, in: context)

        let cleanPortal = portalURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        drawText("Portail web : \(cleanPortal)", x: marginX, y: marginTop + 17.0, fontSize: 8.5, style: .bold, color: colorBlue, in: context)

        drawText("Confidentiel — Répertoire officiel des identifiants et mots de passe", x: marginX, y: marginTop + 31.0, fontSize: 7.5, style: .regular, color: colorSubText, in: context)

        // B. Côté Droit : Service Cloud (avec logo officiel vectoriel), Dossier source, et Année
        let rightX = pageWidth - marginX

        // 1. Nom du Cloud + Logo officiel vectoriel (Dropbox, Drive, OneDrive, Nextcloud)
        let cloudWidth = drawText(cloudServiceName, x: rightX, y: marginTop + 1.0, fontSize: 10.5, style: .bold, color: colorNavy, alignment: .right, in: context)

        let iconSize: CGFloat = 14.0
        let iconX = rightX - cloudWidth - iconSize - 5.5
        let iconY = marginTop - 0.5
        drawCloudBrandLogo(providerType: providerType, in: context, rect: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

        // 2. Dossier source
        drawText("Dossier source : \(cloudFolderPath)", x: rightX, y: marginTop + 17.0, fontSize: 8.5, style: .bold, color: colorDarkText, alignment: .right, in: context)

        // 3. Année scolaire
        drawText("Année scolaire \(schoolYear)", x: rightX, y: marginTop + 31.0, fontSize: 7.5, style: .regular, color: colorSubText, alignment: .right, in: context)

        // Séparateur fin sous l'en-tête
        context.setStrokeColor(colorBorder)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: marginX, y: marginTop + 44.0))
        context.addLine(to: CGPoint(x: pageWidth - marginX, y: marginTop + 44.0))
        context.strokePath()
    }

    // MARK: - En-tête du Tableau

    private static func drawTableHeader(in context: CGContext, startY: CGFloat) {
        let rect = CGRect(x: marginX, y: startY, width: contentWidth, height: tableHeaderHeight)

        // Fond gris doux
        context.setFillColor(colorHeaderBg)
        context.fill(rect)

        // Ligne de séparation sous l'en-tête
        context.setStrokeColor(colorBorder)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: marginX, y: startY + tableHeaderHeight))
        context.addLine(to: CGPoint(x: marginX + contentWidth, y: startY + tableHeaderHeight))
        context.strokePath()

        // Titres des colonnes
        var curX = marginX
        drawText("CLASSE", x: curX + 6.0, y: startY + 5.5, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        curX += colClassWidth

        drawText("NOM & PRÉNOM", x: curX + 6.0, y: startY + 5.5, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        curX += colNameWidth

        drawText("IDENTIFIANT", x: curX + 6.0, y: startY + 5.5, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        curX += colLoginWidth

        drawText("MOT DE PASSE", x: curX + 6.0, y: startY + 5.5, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        curX += colPasswordWidth

        drawText("CLOUD", x: curX + (colCloudWidth / 2.0), y: startY + 5.5, fontSize: 7.5, style: .bold, color: colorSubText, alignment: .center, in: context)
    }

    // MARK: - Ligne Élève

    private static func drawStudentRow(
        in context: CGContext,
        student: Student,
        y: CGFloat,
        isAlternate: Bool
    ) {
        let rowRect = CGRect(x: marginX, y: y, width: contentWidth, height: rowHeight)

        // Fond zébré
        context.setFillColor(isAlternate ? colorRowAlt : colorRowWhite)
        context.fill(rowRect)

        // Filet séparateur horizontal fin
        context.setStrokeColor(colorBorder)
        context.setLineWidth(0.4)
        context.move(to: CGPoint(x: marginX, y: y + rowHeight))
        context.addLine(to: CGPoint(x: marginX + contentWidth, y: y + rowHeight))
        context.strokePath()

        var curX = marginX

        // 1. Classe
        drawText(student.classe, x: curX + 6.0, y: y + 4.5, fontSize: 8.5, style: .bold, color: colorDarkText, in: context)
        curX += colClassWidth

        // 2. Nom & Prénom
        drawText(student.name, x: curX + 6.0, y: y + 4.5, fontSize: 9.0, style: .bold, color: colorDarkText, in: context)
        curX += colNameWidth

        // 3. Identifiant (Police Monospaced)
        drawText(student.login, x: curX + 6.0, y: y + 4.5, fontSize: 9.0, style: .mono, color: colorDarkText, in: context)
        curX += colLoginWidth

        // 4. Mot de passe (Police Monospaced bleue)
        drawText(student.password, x: curX + 6.0, y: y + 4.5, fontSize: 9.0, style: .mono, color: colorBlue, in: context)
        curX += colPasswordWidth

        // 5. Statut Cloud
        let hasCloud = !student.urlDropbox.isEmpty
        drawText(
            hasCloud ? "Actif" : "—",
            x: curX + (colCloudWidth / 2.0),
            y: y + 4.5,
            fontSize: 7.5,
            style: .bold,
            color: hasCloud ? colorSuccess : colorSubText,
            alignment: .center,
            in: context
        )
    }

    // MARK: - Pied de Page

    private static func drawFooter(
        in context: CGContext,
        currentPage: Int,
        totalPages: Int,
        dateString: String
    ) {
        let footerY = pageHeight - marginBottom + 6.0

        drawText("Généré le \(dateString) par Droopies", x: marginX, y: footerY, fontSize: 7.5, style: .regular, color: colorSubText, in: context)
        drawText("Page \(currentPage) / \(totalPages)", x: pageWidth - marginX, y: footerY, fontSize: 7.5, style: .bold, color: colorSubText, alignment: .right, in: context)
    }
}
