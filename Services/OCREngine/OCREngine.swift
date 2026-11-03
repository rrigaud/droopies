//
//  OCREngine.swift
//  Dropies
//
//  Moteur de reconnaissance optique de caractères (OCR)
//  utilisant le framework natif Apple Vision et le Neural Engine local.
//

import Foundation
import Vision
import CoreGraphics

public struct RecognizedTextLine: Sendable {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public final class OCREngine: @unchecked Sendable {
    public static let shared = OCREngine()

    public init() {}

    /// Analyse une image (en-tête de copie) et extrait les lignes de texte manuscrites
    public func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let lines = observations.compactMap { observation -> RecognizedTextLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedTextLine(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
