import Foundation
import AVFoundation

public struct VideoCompressor: FileCompressorProtocol {
    public init() {}

    public enum VideoCompressorError: LocalizedError {
        case noCompatibleExportPreset
        case failedToInitializeExportSession
        case exportFailed(String)
        case exportCancelled

        public var errorDescription: String? {
            switch self {
            case .noCompatibleExportPreset:
                return "No compatible export preset found for this video."
            case .failedToInitializeExportSession:
                return "Failed to initialize AVAssetExportSession."
            case .exportFailed(let reason):
                return "Video export failed: \(reason)"
            case .exportCancelled:
                return "Video export was cancelled."
            }
        }
    }

    public func compress(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let originalSize = CompressionItem.fileSize(for: inputURL)
        let isFormatConversion = outputURL.pathExtension.lowercased() != inputURL.pathExtension.lowercased()
        let asset = AVURLAsset(url: inputURL)

        let presetsToTry = await determinePresetTiers(for: asset, quality: quality)
        guard !presetsToTry.isEmpty else {
            throw VideoCompressorError.noCompatibleExportPreset
        }

        var exportSuccess = false

        for presetName in presetsToTry {
            do {
                try await exportWithPreset(
                    asset: asset,
                    presetName: presetName,
                    outputURL: outputURL,
                    progressHandler: progressHandler
                )

                let outputSize = CompressionItem.fileSize(for: outputURL)

                if isFormatConversion || originalSize <= 0 || outputSize < originalSize {
                    exportSuccess = true
                    break
                }
                // If output was larger or equal, try the next lower preset in presetsToTry
            } catch {
                if Task.isCancelled {
                    throw error
                }
                // Try next preset
                continue
            }
        }

        // If not converting formats and after trying presets the size still exceeds original, copy original file
        let finalSize = CompressionItem.fileSize(for: outputURL)
        if !isFormatConversion && originalSize > 0 && (!exportSuccess || finalSize >= originalSize) {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        }

        progressHandler?(1.0)
    }

    private func exportWithPreset(
        asset: AVAsset,
        presetName: String,
        outputURL: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoCompressorError.failedToInitializeExportSession
        }

        let ext = outputURL.pathExtension.lowercased()
        let fileType: AVFileType
        if ext == "mov" {
            fileType = .mov
        } else if ext == "m4v" {
            fileType = .m4v
        } else {
            fileType = .mp4
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = fileType
        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let p = Double(exportSession.progress)
                progressHandler?(min(max(p, 0.0), 0.99))
            }
        }

        defer {
            progressTask.cancel()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    let err = exportSession.error?.localizedDescription ?? "Unknown export error"
                    continuation.resume(throwing: VideoCompressorError.exportFailed(err))
                case .cancelled:
                    continuation.resume(throwing: VideoCompressorError.exportCancelled)
                default:
                    let err = exportSession.error?.localizedDescription ?? "Export ended with status \(exportSession.status.rawValue)"
                    continuation.resume(throwing: VideoCompressorError.exportFailed(err))
                }
            }
        }
    }

    private func determinePresetTiers(for asset: AVAsset, quality: Double) async -> [String] {
        let compatiblePresets = await AVAssetExportSession.exportPresets(compatibleWith: asset)

        var candidatePresets: [String] = []

        if quality >= 0.75 {
            // For high quality, prefer HEVC 1080p, standard 1080p, then 720p or medium
            candidatePresets = [
                AVAssetExportPresetHEVC1920x1080,
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPresetLowQuality
            ]
        } else if quality >= 0.50 {
            // Balanced
            candidatePresets = [
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset960x540,
                AVAssetExportPresetLowQuality
            ]
        } else {
            // Smallest
            candidatePresets = [
                AVAssetExportPreset960x540,
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality
            ]
        }

        var matched = candidatePresets.filter { compatiblePresets.contains($0) }
        if matched.isEmpty {
            matched = compatiblePresets
        }
        return matched
    }
}
