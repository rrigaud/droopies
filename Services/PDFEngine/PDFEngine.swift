//
//  PDFEngine.swift
//  Dropies
//
//  Moteur PDF natif basé sur PDFKit et CoreGraphics.
//  Gère le chargement, le découpage, le rendu de vignettes pour l'OCR
//  et la compression haute performance.
//

import Foundation
import PDFKit
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public final class PDFEngine: @unchecked Sendable {
    public static let shared = PDFEngine()

    public init() {}

    // MARK: - Chargement & Validation

    /// Charge un document PDF depuis une URL locale
    public func loadDocument(from url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw PDFEngineError.cannotOpenDocument(url: url)
        }
        guard document.pageCount > 0 else {
            throw PDFEngineError.emptyDocument
        }
        return document
    }

    // MARK: - Découpage de PDF

    /// Découpe un document PDF en paquets de `pagesPerCopy` pages
    public func sliceDocument(_ document: PDFDocument, pagesPerCopy: Int) -> [PDFDocument] {
        let pagesPerSlice = max(1, pagesPerCopy)
        let totalPages = document.pageCount
        var slices: [PDFDocument] = []

        var startIndex = 0
        while startIndex < totalPages {
            let slice = PDFDocument()
            let endIndex = min(startIndex + pagesPerSlice, totalPages)

            for pageIndex in startIndex..<endIndex {
                if let page = document.page(at: pageIndex) {
                    slice.insert(page, at: slice.pageCount)
                }
            }

            if slice.pageCount > 0 {
                slices.append(slice)
            }
            startIndex += pagesPerSlice
        }

        return slices
    }

    /// Extrait un sous-document PDF correspondant à une plage de pages [startPage, endPage] (indices 1-based)
    public func extractSlice(from document: PDFDocument, pageStart: Int, pageEnd: Int) -> PDFDocument? {
        guard pageStart >= 1, pageEnd >= pageStart, pageEnd <= document.pageCount else {
            return nil
        }

        let slice = PDFDocument()
        for pageIndex in (pageStart - 1)..<pageEnd {
            if let page = document.page(at: pageIndex) {
                slice.insert(page, at: slice.pageCount)
            }
        }
        return slice
    }

    // MARK: - Rendu d'images & Crop d'en-tête (pour l'UI et l'OCR Vision)

    /// Génère une image de la partie supérieure de la page (ex: 35 % supérieur)
    /// pour permettre à l'OCR de lire le nom manuscrit et afficher l'en-tête à l'enseignant.
    public func renderHeaderCrop(for page: PDFPage, cropHeightRatio: CGFloat = 0.35) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 1600 // Résolution optimale pour l'OCR Apple Vision
        let scale = targetWidth / pageBounds.width
        let cropHeight = pageBounds.height * cropHeightRatio

        let targetSize = CGSize(width: targetWidth, height: cropHeight * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Fond blanc propre
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: targetSize))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: -(pageBounds.height - cropHeight))

        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }

    // MARK: - Sauvegarde & Compression

    /// Enregistre un document PDF sur disque avec optimisation de poids
    public func saveDocument(_ document: PDFDocument, to destinationURL: URL) throws {
        let parent = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        guard document.write(to: destinationURL) else {
            throw PDFEngineError.writeFailed(url: destinationURL)
        }
    }
}

public enum PDFEngineError: LocalizedError {
    case cannotOpenDocument(url: URL)
    case emptyDocument
    case writeFailed(url: URL)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenDocument(let url):
            return "Impossible d'ouvrir le document PDF : \(url.lastPathComponent)"
        case .emptyDocument:
            return "Le document PDF ne contient aucune page."
        case .writeFailed(let url):
            return "Impossible d'enregistrer le fichier PDF à l'emplacement : \(url.path)"
        }
    }
}
