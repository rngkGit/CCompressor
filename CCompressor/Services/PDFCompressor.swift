import Foundation
import CoreGraphics
import PDFKit

public struct PDFCompressor: FileCompressorProtocol {
    public init() {}

    public enum PDFCompressorError: LocalizedError {
        case unableToLoadDocument
        case unableToCreateOutputContext
        case compressionFailed

        public var errorDescription: String? {
            switch self {
            case .unableToLoadDocument:
                return "Could not load the source PDF document."
            case .unableToCreateOutputContext:
                return "Could not create destination PDF context."
            case .compressionFailed:
                return "Failed to compress PDF document."
            }
        }
    }

    public func compress(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        progressHandler?(0.05)

        let originalSize = CompressionItem.fileSize(for: inputURL)

        guard let pdfDoc = PDFDocument(url: inputURL),
              let cgDoc = CGPDFDocument(inputURL as CFURL) else {
            throw PDFCompressorError.unableToLoadDocument
        }

        let pageCount = pdfDoc.pageCount
        guard pageCount > 0 else {
            throw PDFCompressorError.unableToLoadDocument
        }

        // Try raster re-compression with scaled resolution
        var currentQuality = quality
        var attempts = 0
        let maxAttempts = 2

        while attempts < maxAttempts {
            attempts += 1
            try renderAndCompressPDF(
                cgDoc: cgDoc,
                pageCount: pageCount,
                outputURL: outputURL,
                quality: currentQuality,
                progressHandler: progressHandler
            )

            let outputSize = CompressionItem.fileSize(for: outputURL)

            if originalSize <= 0 || outputSize < originalSize {
                progressHandler?(1.0)
                return
            }

            // If size increased, step down quality for second attempt
            currentQuality = max(0.20, currentQuality * 0.65)
        }

        // If compressed PDF is still >= originalSize, preserve original file
        let finalSize = CompressionItem.fileSize(for: outputURL)
        if originalSize > 0 && finalSize >= originalSize {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        }

        progressHandler?(1.0)
    }

    private func renderAndCompressPDF(
        cgDoc: CGPDFDocument,
        pageCount: Int,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let consumer = CGDataConsumer(url: outputURL as CFURL) else {
            throw PDFCompressorError.unableToCreateOutputContext
        }

        var firstPageBox = CGRect.zero
        if let firstPage = cgDoc.page(at: 1) {
            firstPageBox = firstPage.getBoxRect(.mediaBox)
        }

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &firstPageBox, nil) else {
            throw PDFCompressorError.unableToCreateOutputContext
        }

        let clampedQuality = min(max(quality, 0.1), 1.0)
        // Scale between 1.0x (72 DPI) and 1.8x (~130 DPI) to prevent raster file explosion
        let scale = 1.0 + (clampedQuality * 0.8)

        for pageIndex in 1...pageCount {
            guard let cgPage = cgDoc.page(at: pageIndex) else { continue }
            var pageMediaBox = cgPage.getBoxRect(.mediaBox)

            pdfContext.beginPage(mediaBox: &pageMediaBox)

            let targetWidth = max(Int(pageMediaBox.width * scale), 100)
            let targetHeight = max(Int(pageMediaBox.height * scale), 100)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            if let bitmapContext = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                bitmapContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                bitmapContext.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

                bitmapContext.saveGState()
                bitmapContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                bitmapContext.drawPDFPage(cgPage)
                bitmapContext.restoreGState()

                if let cgImage = bitmapContext.makeImage() {
                    let imageData = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(imageData as CFMutableData, "public.jpeg" as CFString, 1, nil) {
                        let options: [CFString: Any] = [
                            kCGImageDestinationLossyCompressionQuality: clampedQuality as CFNumber
                        ]
                        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                        CGImageDestinationFinalize(destination)

                        if let compressedSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                           let compressedImage = CGImageSourceCreateImageAtIndex(compressedSource, 0, nil) {
                            pdfContext.draw(compressedImage, in: pageMediaBox)
                        } else {
                            pdfContext.draw(cgImage, in: pageMediaBox)
                        }
                    } else {
                        pdfContext.draw(cgImage, in: pageMediaBox)
                    }
                } else {
                    pdfContext.drawPDFPage(cgPage)
                }
            } else {
                pdfContext.drawPDFPage(cgPage)
            }

            pdfContext.endPage()

            let currentProgress = 0.05 + (Double(pageIndex) / Double(pageCount)) * 0.90
            progressHandler?(currentProgress)
        }

        pdfContext.closePDF()
    }
}
