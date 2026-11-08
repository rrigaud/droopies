//
//  StudentLabelsPDFGenerator.swift
//  Droopies
//
//  Générateur de PDF haute définition pour les étiquettes de connexion (QR).
//  Format A4, 10 étiquettes par page (2 colonnes de 5), disposition uniforme et compacte,
//  découpage direct au massicot ou ciseaux (pointillés), QR Codes vectoriels agrandis,
//  identifiants/mots de passe, URL du portail, et saut de page systématique à chaque changement de classe.
//  Rendu de texte 100% vectoriel multiplateforme via CoreText.
//

import Foundation
import CoreGraphics
import CoreText
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

public final class StudentLabelsPDFGenerator: @unchecked Sendable {

    // MARK: - Dimensions Page A4 standard (72 DPI)
    public static let pageWidth: CGFloat = 595.2   // A4 Width
    public static let pageHeight: CGFloat = 841.8  // A4 Height

    public static let marginX: CGFloat = 24.0
    public static let marginTop: CGFloat = 25.0
    public static let marginBottom: CGFloat = 24.8

    public static let columnsCount: Int = 2
    public static let rowsPerPage: Int = 5
    public static let labelsPerPage: Int = 10 // 2 colonnes * 5 lignes = 10 étiquettes par page

    public static let columnGap: CGFloat = 16.0
    public static let rowGap: CGFloat = 13.0

    // Largeur et hauteur d'une étiquette (optimisé pour 10 cartes par page)
    public static let cardWidth: CGFloat = (pageWidth - (marginX * 2) - columnGap) / 2.0 // ~265.6 pt
    public static let cardHeight: CGFloat = 148.0 // pt

    // MARK: - Palette Couleurs Graphiques (CGColor sRGB)
    private static let colorNavy = CGColor(srgbRed: 0.12, green: 0.23, blue: 0.54, alpha: 1.0)
    private static let colorBlue = CGColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0)
    private static let colorDarkText = CGColor(srgbRed: 0.08, green: 0.12, blue: 0.22, alpha: 1.0)
    private static let colorSubText = CGColor(srgbRed: 0.45, green: 0.50, blue: 0.58, alpha: 1.0)
    private static let colorCardBg = CGColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1.0)
    private static let colorHeaderBg = CGColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1.0)
    private static let colorBorder = CGColor(srgbRed: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
    private static let colorHeaderBorder = CGColor(srgbRed: 0.85, green: 0.88, blue: 0.92, alpha: 1.0)
    private static let colorDottedGuide = CGColor(srgbRed: 0.78, green: 0.82, blue: 0.88, alpha: 1.0)
    private static let colorWhite = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

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

    // MARK: - Génération Principale

    /// Génère le document PDF complet sous forme de `PDFDocument`
    public static func generatePDFDocument(
        students: [Student],
        portalURL: String,
        schoolYear: String = AppSettings.currentSchoolYear
    ) -> PDFDocument? {
        guard let data = generatePDFData(students: students, portalURL: portalURL, schoolYear: schoolYear) else {
            return nil
        }
        return PDFDocument(data: data)
    }

    /// Génère les données brutes PDF (`Data`)
    public static func generatePDFData(
        students: [Student],
        portalURL: String,
        schoolYear: String = AppSettings.currentSchoolYear
    ) -> Data? {
        guard !students.isEmpty else { return nil }

        // 1. Grouper les élèves par classe
        let grouped = Dictionary(grouping: students, by: { $0.classe.isEmpty ? "Sans_Classe" : $0.classe })
        let sortedClasses = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        // 2. Parcourir chaque classe : NOUVELLE PAGE À CHAQUE CHANGEMENT DE CLASSE
        for classe in sortedClasses {
            guard let classStudents = grouped[classe], !classStudents.isEmpty else { continue }
            let sortedStudents = classStudents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Découpage en pages de 10 étiquettes max (2 colonnes x 5 lignes)
            let studentChunks = stride(from: 0, to: sortedStudents.count, by: labelsPerPage).map {
                Array(sortedStudents[$0..<min($0 + labelsPerPage, sortedStudents.count)])
            }

            for (_, chunk) in studentChunks.enumerated() {
                context.beginPDFPage(nil)

                // Système de coordonnées Quartz (origine en bas à gauche)
                // Inversion vers origine en haut à gauche pour simplifier la disposition
                context.saveGState()
                context.translateBy(x: 0, y: pageHeight)
                context.scaleBy(x: 1.0, y: -1.0)

                // Dessiner la grille de 10 étiquettes (uniforme sur toute la page)
                let startY = marginTop
                for (index, student) in chunk.enumerated() {
                    let col = index % columnsCount
                    let row = index / columnsCount

                    let cardX = marginX + CGFloat(col) * (cardWidth + columnGap)
                    let cardY = startY + CGFloat(row) * (cardHeight + rowGap)
                    let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

                    drawLabel(
                        in: context,
                        rect: cardRect,
                        student: student,
                        portalURL: portalURL
                    )
                }

                // Dessiner les repères de coupe pointillés entre les étiquettes
                let rowsCount = (chunk.count + columnsCount - 1) / columnsCount
                drawCuttingGuides(in: context, startY: startY, rowsCount: rowsCount)

                context.restoreGState()
                context.endPDFPage()
            }
        }

        context.closePDF()
        return pdfData as Data
    }

    // MARK: - Dessin d'une Étiquette Compacte

    private static func drawLabel(
        in context: CGContext,
        rect: CGRect,
        student: Student,
        portalURL: String
    ) {
        context.saveGState()

        // 1. Fond carte avec coins arrondis
        let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(colorCardBg)
        context.fillPath()

        // Bordure fine
        context.addPath(path)
        context.setStrokeColor(colorBorder)
        context.setLineWidth(1.0)
        context.strokePath()

        // 2. Bandeau supérieur : Nom de l'élève & badge classe (hauteur 28 pt)
        let headerHeight: CGFloat = 28.0
        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        let headerPath = CGPath(
            roundedRect: headerRect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        context.saveGState()
        context.addPath(headerPath)
        context.clip()
        context.setFillColor(colorHeaderBg)
        context.fill(headerRect)
        context.restoreGState()

        // Nom de l'élève (avec zone de clipping pour éviter tout débordement sur le badge)
        let badgeWidth: CGFloat = 46.0
        let maxNameWidth = rect.width - badgeWidth - 24.0
        let nameX = rect.minX + 10.0
        let nameY = rect.minY + 6.5
        context.saveGState()
        context.clip(to: CGRect(x: nameX, y: rect.minY, width: maxNameWidth, height: headerHeight))
        drawText(student.name, x: nameX, y: nameY, fontSize: 11.5, style: .bold, color: colorDarkText, in: context)
        context.restoreGState()

        // Badge Classe (rectangle arrondi bleu)
        let badgeHeight: CGFloat = 16.0
        let badgeRect = CGRect(x: rect.maxX - badgeWidth - 8.0, y: rect.minY + 6.0, width: badgeWidth, height: badgeHeight)
        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(badgePath)
        context.setFillColor(colorBlue)
        context.fillPath()

        drawText(
            student.classe,
            x: badgeRect.midX,
            y: badgeRect.midY - 5.5,
            fontSize: 9.0,
            style: .bold,
            color: colorWhite,
            alignment: .center,
            in: context
        )

        // Séparateur fin sous le bandeau
        context.setStrokeColor(colorHeaderBorder)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: rect.minX, y: rect.minY + headerHeight))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + headerHeight))
        context.strokePath()

        // 3. QR Code à gauche (carré 96x96 pt)
        let qrSize: CGFloat = 96.0
        let qrX = rect.minX + 10.0
        let qrY = rect.minY + headerHeight + 11.0
        let qrRect = CGRect(x: qrX, y: qrY, width: qrSize, height: qrSize)

        // Valeur du QR code : lien de partage direct Cloud de l'élève
        let qrPayload = student.urlDropbox.isEmpty ? "\(portalURL)?id=\(student.login)" : student.urlDropbox
        if let qrCGImage = generateQRCode(from: qrPayload, size: qrSize) {
            // Fond blanc sous le QR code avec bordure fine
            let qrBgPath = CGPath(roundedRect: qrRect.insetBy(dx: -2, dy: -2), cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(qrBgPath)
            context.setFillColor(colorWhite)
            context.fillPath()
            context.addPath(qrBgPath)
            context.setStrokeColor(colorHeaderBorder)
            context.setLineWidth(0.5)
            context.strokePath()

            // Dessin du QR Code (inversion locale car l'image CGImage a son origine en bas)
            context.saveGState()
            context.translateBy(x: qrRect.minX, y: qrRect.maxY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(qrCGImage, in: CGRect(x: 0, y: 0, width: qrSize, height: qrSize))
            context.restoreGState()
        }

        // 4. Bloc d'Accès à droite (Portail web, Identifiant, Mot de passe)
        let textX = qrRect.maxX + 12.0
        var currentY = rect.minY + headerHeight + 10.0

        // A. Portail web
        drawText("Portail web :", x: textX, y: currentY, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        currentY += 10.0

        let cleanPortal = portalURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        drawText(cleanPortal, x: textX, y: currentY, fontSize: 8.5, style: .bold, color: colorNavy, in: context)
        currentY += 16.0

        // B. Identifiant
        drawText("Identifiant :", x: textX, y: currentY, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        currentY += 10.0

        drawText(student.login, x: textX, y: currentY, fontSize: 10.0, style: .mono, color: colorDarkText, in: context)
        currentY += 16.0

        // C. Mot de passe
        drawText("Mot de passe :", x: textX, y: currentY, fontSize: 7.5, style: .bold, color: colorSubText, in: context)
        currentY += 10.0

        drawText(student.password, x: textX, y: currentY, fontSize: 10.0, style: .mono, color: colorBlue, in: context)

        // Coupe directe compacte : aucun texte superflu en pied de carte

        context.restoreGState()
    }

    // MARK: - Pointillés et Repères de Coupe

    private static func drawCuttingGuides(
        in context: CGContext,
        startY: CGFloat,
        rowsCount: Int
    ) {
        guard rowsCount > 0 else { return }

        context.saveGState()
        context.setStrokeColor(colorDottedGuide)
        context.setLineWidth(0.6)
        let dashes: [CGFloat] = [3.0, 3.0]
        context.setLineDash(phase: 0, lengths: dashes)

        // Ligne verticale médiane de séparation
        let midX = marginX + cardWidth + (columnGap / 2.0)
        let totalHeight = CGFloat(rowsCount) * cardHeight + CGFloat(max(0, rowsCount - 1)) * rowGap
        context.move(to: CGPoint(x: midX, y: startY - 4))
        context.addLine(to: CGPoint(x: midX, y: startY + totalHeight + 4))
        context.strokePath()

        // Lignes horizontales de séparation entre les lignes d'étiquettes
        for row in 1..<rowsCount {
            let lineY = startY + CGFloat(row) * cardHeight + CGFloat(row - 1) * rowGap + (rowGap / 2.0)
            context.move(to: CGPoint(x: marginX - 6, y: lineY))
            context.addLine(to: CGPoint(x: pageWidth - marginX + 6, y: lineY))
            context.strokePath()
        }

        context.restoreGState()
    }

    // MARK: - Génération QR Code Vectoriel CoreImage

    private static func generateQRCode(from text: String, size: CGFloat) -> CGImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }

        // Mettre à l'échelle pour une netteté cristalline à 300 DPI
        let scale = (size * 3.0) / output.extent.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ciContext = CIContext()
        return ciContext.createCGImage(transformed, from: transformed.extent)
    }
}
