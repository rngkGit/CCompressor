import Foundation

public struct FileCompressionDispatcher: Sendable {
    private let imageCompressor = ImageCompressor()
    private let audioCompressor = AudioCompressor()
    private let videoCompressor = VideoCompressor()
    private let pdfCompressor = PDFCompressor()
    private let gifConverter = GifConverter()

    public init() {}

    public enum DispatcherError: LocalizedError {
        case unsupportedFormat
        case invalidDestination
        case permissionDenied(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "The file format is not supported for compression or conversion."
            case .invalidDestination:
                return "Could not determine a valid destination path."
            case .permissionDenied(let path):
                return "Permission denied: Cannot write to '\(path)'. Please grant access to this folder."
            }
        }
    }

    public func destinationURL(for item: CompressionItem, settings: CompressionSettings) -> URL {
        let baseDir: URL
        if settings.destinationMode == .customFolder, let customURL = settings.customDestinationURL {
            baseDir = customURL
        } else {
            baseDir = item.sourceURL.deletingLastPathComponent()
        }

        let didStartAccessing = baseDir.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let originalName = item.sourceURL.deletingPathExtension().lastPathComponent
        let ext = item.effectiveExtension
        let suffix = settings.fileSuffix

        var candidateName = "\(originalName)\(suffix)"
        var candidateURL = baseDir.appendingPathComponent(candidateName).appendingPathExtension(ext)

        // Avoid collision with input URL or existing files
        var counter = 1
        while candidateURL == item.sourceURL || FileManager.default.fileExists(atPath: candidateURL.path) {
            candidateName = "\(originalName)\(suffix) (\(counter))"
            candidateURL = baseDir.appendingPathComponent(candidateName).appendingPathExtension(ext)
            counter += 1
        }

        return candidateURL
    }

    public func compress(
        item: CompressionItem,
        settings: CompressionSettings,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let outputURL = destinationURL(for: item, settings: settings)
        let outputDir = outputURL.deletingLastPathComponent()

        let didStartAccessing = outputDir.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                outputDir.stopAccessingSecurityScopedResource()
            }
        }

        // Ensure parent directory exists
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            } catch {
                throw DispatcherError.permissionDenied(outputDir.lastPathComponent)
            }
        }

        let inputExt = item.sourceURL.pathExtension.lowercased()
        let outputExt = outputURL.pathExtension.lowercased()
        let isFormatConversion = outputExt != inputExt

        // Lossless quality preset: if no file conversion is applicable, skip compression entirely and copy original
        if settings.isLossless && !isFormatConversion {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: item.sourceURL, to: outputURL)
            progressHandler?(1.0)
            return outputURL
        }

        // Two-way Video <-> GIF conversion routing
        if item.category == .video && outputExt == "gif" {
            try await gifConverter.convertVideoToGIF(
                inputURL: item.sourceURL,
                outputURL: outputURL,
                quality: settings.quality,
                progressHandler: progressHandler
            )
        } else if inputExt == "gif" && (outputExt == "mp4" || outputExt == "mov") {
            try await gifConverter.convertGIFToVideo(
                inputURL: item.sourceURL,
                outputURL: outputURL,
                quality: settings.quality,
                progressHandler: progressHandler
            )
        } else {
            switch item.category {
            case .image:
                try await imageCompressor.compress(
                    inputURL: item.sourceURL,
                    outputURL: outputURL,
                    quality: settings.quality,
                    progressHandler: progressHandler
                )
            case .audio:
                try await audioCompressor.compress(
                    inputURL: item.sourceURL,
                    outputURL: outputURL,
                    quality: settings.quality,
                    progressHandler: progressHandler
                )
            case .video:
                try await videoCompressor.compress(
                    inputURL: item.sourceURL,
                    outputURL: outputURL,
                    quality: settings.quality,
                    progressHandler: progressHandler
                )
            case .pdf:
                try await pdfCompressor.compress(
                    inputURL: item.sourceURL,
                    outputURL: outputURL,
                    quality: settings.quality,
                    progressHandler: progressHandler
                )
            case .unsupported:
                throw DispatcherError.unsupportedFormat
            }
        }

        // Universal invariant: ensure output file never exceeds the original file size (only when compressing in same format)
        let originalSize = CompressionItem.fileSize(for: item.sourceURL)
        let outputSize = CompressionItem.fileSize(for: outputURL)

        if !isFormatConversion && originalSize > 0 && outputSize >= originalSize {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: item.sourceURL, to: outputURL)
        }

        return outputURL
    }
}
