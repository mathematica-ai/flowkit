import Foundation

#if canImport(Vision)
import Vision
import ImageIO
import CoreGraphics

/// On-device OCR — the native replacement for the server Docling tool. Uses Apple Vision to extract
/// text from receipt/invoice/document images. Images are passed as encoded data (PNG/JPEG/HEIC),
/// which keeps the tool `Sendable` and matches how the app already carries attachments.
public struct VisionOCRTool: LangflowTool {
    public let name: String
    public let description: String
    private let images: [Data]

    public init(name: String = "ocr",
                description: String = "Extract text from receipt, invoice, or document images.",
                images: [Data]) {
        self.name = name
        self.description = description
        self.images = images
    }

    public func call(_ input: String) async throws -> String {
        guard !images.isEmpty else { return "No images provided." }
        var blocks: [String] = []
        for (index, data) in images.enumerated() {
            guard let cgImage = Self.cgImage(from: data) else {
                blocks.append("[image \(index)] (unreadable)")
                continue
            }
            let text = try Self.recognizeText(in: cgImage)
            blocks.append("[image \(index)]\n\(text)")
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
#endif
