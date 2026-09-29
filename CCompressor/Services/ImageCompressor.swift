import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

public struct ImageCompressor: FileCompressorProtocol {
    public init() {}

    public enum ImageCompressorError: LocalizedError {
        case unableToReadSource
        case unableToCreateDestination
        case compressionFailed
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .unableToReadSource:
                return "Could not read source image file."
            case .unableToCreateDestination:
                return "Could not initialize image destination."
            case .compressionFailed:
                return "Failed to finalize compressed image."
            case .unsupportedFormat:
                return "Unsupported image format."
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
        let isFormatConversion = outputURL.pathExtension.lowercased() != inputURL.pathExtension.lowercased()

        // Try initial compression
        var currentQuality = quality
        var attempts = 0
        let maxAttempts = isFormatConversion ? 1 : 3

        while attempts < maxAttempts {
            attempts += 1
            try encodeImage(
                inputURL: inputURL,
                outputURL: outputURL,
                quality: currentQuality,
                progressHandler: progressHandler
            )

            let outputSize = CompressionItem.fileSize(for: outputURL)

            // For format conversion, user requested the new format, so keep it
            if isFormatConversion {
                progressHandler?(1.0)
                return
            }

            // If compressed file is smaller than original or original size couldn't be determined, we succeeded
            if originalSize <= 0 || outputSize < originalSize {
                progressHandler?(1.0)
                return
            }

            // File size increased or stayed same: adaptively decrease quality for next attempt
            if currentQuality > 0.25 && attempts < maxAttempts {
                currentQuality = max(0.15, currentQuality * 0.70)
            } else {
                break
            }
        }

        // If not a format conversion and file is still larger or equal to original, preserve original file
        let finalSize = CompressionItem.fileSize(for: outputURL)
        if !isFormatConversion && originalSize > 0 && finalSize >= originalSize {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        }

        progressHandler?(1.0)
    }

    private func encodeImage(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) throws {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
            throw ImageCompressorError.unableToReadSource
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw ImageCompressorError.unableToReadSource
        }

        let ext = outputURL.pathExtension.lowercased()
        let uti: CFString
        if ext == "jpg" || ext == "jpeg" {
            uti = UTType.jpeg.identifier as CFString
        } else if ext == "png" {
            uti = UTType.png.identifier as CFString
        } else if ext == "heic" {
            uti = UTType.heic.identifier as CFString
        } else if ext == "tiff" || ext == "tif" {
            uti = UTType.tiff.identifier as CFString
        } else if let outputType = UTType(filenameExtension: ext)?.identifier {
            uti = outputType as CFString
        } else if let sourceType = CGImageSourceGetType(source) {
            uti = sourceType
        } else {
            uti = UTType.jpeg.identifier as CFString
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            uti,
            frameCount,
            nil
        ) else {
            throw ImageCompressorError.unableToCreateDestination
        }

        let clampedQuality = min(max(quality, 0.05), 1.0)
        let isConvertingToJPEG = (uti == (UTType.jpeg.identifier as CFString))

        let imageOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: clampedQuality as CFNumber,
            kCGImageDestinationMergeMetadata: true as CFBoolean
        ]

        if let containerProperties = CGImageSourceCopyProperties(source, nil) {
            CGImageDestinationSetProperties(destination, containerProperties)
        }

        for index in 0..<frameCount {
            // When converting transparent formats (like PNG) to JPEG, flatten onto a white background
            if isConvertingToJPEG,
               let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil),
               hasAlphaChannel(cgImage) {
                if let flattenedImage = flattenOnWhiteBackground(cgImage) {
                    CGImageDestinationAddImage(destination, flattenedImage, imageOptions as CFDictionary)
                } else {
                    CGImageDestinationAddImage(destination, cgImage, imageOptions as CFDictionary)
                }
            } else if let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] {
                var mergedProperties = frameProperties
                mergedProperties[kCGImageDestinationLossyCompressionQuality] = clampedQuality as CFNumber
                CGImageDestinationAddImageFromSource(destination, source, index, mergedProperties as CFDictionary)
            } else {
                CGImageDestinationAddImageFromSource(destination, source, index, imageOptions as CFDictionary)
            }

            let currentProgress = 0.1 + (Double(index + 1) / Double(frameCount)) * 0.75
            progressHandler?(currentProgress)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressorError.compressionFailed
        }
    }

    private func hasAlphaChannel(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    private func flattenOnWhiteBackground(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }
}
