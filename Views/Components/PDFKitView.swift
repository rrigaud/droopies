//
//  PDFKitView.swift
//  Dropies
//
//  Wrapper SwiftUI multiplateforme pour PDFView (PDFKit).
//  Supporte macOS (NSViewRepresentable) et iPadOS (UIViewRepresentable).
//

import SwiftUI
import PDFKit

#if os(macOS)
import AppKit

public struct PDFKitView: NSViewRepresentable {
    public let document: PDFDocument?
    public var currentPageIndex: Int = 0
    public var autoScales: Bool = true

    public init(document: PDFDocument?, currentPageIndex: Int = 0, autoScales: Bool = true) {
        self.document = document
        self.currentPageIndex = currentPageIndex
        self.autoScales = autoScales
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = autoScales
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.document = document
        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.autoScales = autoScales

        if let doc = document, currentPageIndex >= 0, currentPageIndex < doc.pageCount {
            if let targetPage = doc.page(at: currentPageIndex), pdfView.currentPage != targetPage {
                pdfView.go(to: targetPage)
            }
        }
    }
}

public struct PDFContinuousPreviewView: NSViewRepresentable {
    public let document: PDFDocument?

    public init(document: PDFDocument?) {
        self.document = document
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.document = document
        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}

#elseif os(iOS)
import UIKit

public struct PDFKitView: UIViewRepresentable {
    public let document: PDFDocument?
    public var currentPageIndex: Int = 0
    public var autoScales: Bool = true

    public init(document: PDFDocument?, currentPageIndex: Int = 0, autoScales: Bool = true) {
        self.document = document
        self.currentPageIndex = currentPageIndex
        self.autoScales = autoScales
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = autoScales
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true)
        pdfView.document = document
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.autoScales = autoScales

        if let doc = document, currentPageIndex >= 0, currentPageIndex < doc.pageCount {
            if let targetPage = doc.page(at: currentPageIndex), pdfView.currentPage != targetPage {
                pdfView.go(to: targetPage)
            }
        }
    }
}

public struct PDFContinuousPreviewView: UIViewRepresentable {
    public let document: PDFDocument?

    public init(document: PDFDocument?) {
        self.document = document
    }

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.document = document
        pdfView.backgroundColor = .clear
        return pdfView
    }

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
#endif
