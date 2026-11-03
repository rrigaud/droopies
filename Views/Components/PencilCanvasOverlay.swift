//
//  PencilCanvasOverlay.swift
//  Dropies
//
//  Calque d'annotation tactile Apple Pencil (PencilKit).
//  Sur iPadOS : PKCanvasView transparent à 120 Hz avec palette PKToolPicker.
//  Sur macOS : Rendu visuel et compatibilité transparente.
//

import SwiftUI
import PencilKit

#if os(iOS)
import UIKit

public struct PencilCanvasOverlay: UIViewRepresentable {
    @Binding public var drawing: PKDrawing
    public var isToolPickerVisible: Bool = true

    public init(drawing: Binding<PKDrawing>, isToolPickerVisible: Bool = true) {
        self._drawing = drawing
        self.isToolPickerVisible = isToolPickerVisible
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput

        if #available(iOS 14.0, *) {
            let toolPicker = PKToolPicker()
            toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    public func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.drawing != drawing {
            canvasView.drawing = drawing
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasOverlay

        init(_ parent: PencilCanvasOverlay) {
            self.parent = parent
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            Task { @MainActor in
                self.parent.drawing = canvasView.drawing
            }
        }
    }
}

#elseif os(macOS)
import AppKit

public struct PencilCanvasOverlay: View {
    @Binding public var drawing: PKDrawing
    public var isToolPickerVisible: Bool = true

    public init(drawing: Binding<PKDrawing>, isToolPickerVisible: Bool = true) {
        self._drawing = drawing
        self.isToolPickerVisible = isToolPickerVisible
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Rendu des traits vectoriels PencilKit existants sous macOS
                let image = drawing.image(from: CGRect(origin: .zero, size: geo.size), scale: 2.0)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
        }
    }
}
#endif
