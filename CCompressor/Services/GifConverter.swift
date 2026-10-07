import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum GifConverterError: LocalizedError {
    case invalidVideoDuration
    case noVideoTrack
    case cannotGenerateFrames
    case failedToCreateDestination
    case failedToFinalizeGIF
    case cannotReadGIF
    case noValidFramesFound
    case cannotAddWriterInput
    case writingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVideoDuration:
            return "The video duration could not be determined or is invalid."
        case .noVideoTrack:
            return "No video track was found in the media file."
        case .cannotGenerateFrames:
            return "Could not generate frames from the video."
        case .failedToCreateDestination:
            return "Failed to initialize the GIF image destination."
        case .failedToFinalizeGIF:
            return "Failed to write and finalize the GIF file."
        case .cannotReadGIF:
            return "The GIF file could not be read or decoded."
        case .noValidFramesFound:
            return "No valid frames could be extracted from the GIF."
        case .cannotAddWriterInput:
            return "Failed to configure video asset writer input."
        case .writingFailed(let reason):
            return "Video writing failed: \(reason)"
        }
    }
}

public struct GifConverter: Sendable {
    public init() {}

    // MARK: - Video to GIF Conversion

    /// Converts a video file into an animated GIF.
    public func convertVideoToGIF(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let durationTime = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(durationTime)
        guard durationSeconds > 0 && !durationSeconds.isNaN && !durationSeconds.isInfinite else {
            throw GifConverterError.invalidVideoDuration
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw GifConverterError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // Compute transformed dimensions
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let videoWidth = max(2, abs(transformedRect.width))
        let videoHeight = max(2, abs(transformedRect.height))

        // Determine target maximum dimension based on quality preset/slider
        let maxDimension: CGFloat
        if quality >= 0.95 {
            maxDimension = 720
        } else if quality >= 0.75 {
            maxDimension = 600
        } else if quality >= 0.55 {
            maxDimension = 480
        } else if quality >= 0.35 {
            maxDimension = 360
        } else {
            maxDimension = 240
        }

        var targetSize = CGSize(width: videoWidth, height: videoHeight)
        if videoWidth > maxDimension || videoHeight > maxDimension {
            let scale = min(maxDimension / videoWidth, maxDimension / videoHeight)
            targetSize = CGSize(
                width: max(1, round(videoWidth * scale)),
                height: max(1, round(videoHeight * scale))
            )
        }

        // Determine frame rate based on quality and duration
        var targetFPS: Double
        if quality >= 0.8 {
            targetFPS = 18.0
        } else if quality >= 0.5 {
            targetFPS = 14.0
        } else {
            targetFPS = 10.0
        }

        // Cap maximum total frames to prevent memory exhaustion and excessively huge GIFs
        let maxFrames = Int(max(30, min(500, round(quality * 350 + 100))))
        if Int(durationSeconds * targetFPS) > maxFrames {
            targetFPS = max(1.0, Double(maxFrames) / durationSeconds)
        }

        let frameInterval = 1.0 / targetFPS
        var sampleTimes: [CMTime] = []
        var t = 0.0
        while t < durationSeconds {
            sampleTimes.append(CMTime(seconds: t, preferredTimescale: 600))
            t += frameInterval
        }

        guard !sampleTimes.isEmpty else {
            throw GifConverterError.cannotGenerateFrames
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            sampleTimes.count,
            nil
        ) else {
            throw GifConverterError.failedToCreateDestination
        }

        // Configure GIF loop count (0 = infinite loop)
        let gifContainerProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifContainerProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: frameInterval,
                kCGImagePropertyGIFDelayTime: frameInterval
            ],
            kCGImageDestinationLossyCompressionQuality: quality as CFNumber
        ]

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: frameInterval * 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: frameInterval * 0.35, preferredTimescale: 600)

        progressHandler?(0.05)

        var processedCount = 0
        let totalCount = sampleTimes.count

        for try await result in generator.images(for: sampleTimes) {
            if Task.isCancelled {
                throw CancellationError()
            }

            switch result {
            case .success(_, let cgImage, _):
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            case .failure(let requestedTime, let error):
                // Frame decode failure: continue if non-fatal
                print("Failed generating frame at \(requestedTime): \(error)")
            }

            processedCount += 1
            let progress = 0.05 + 0.90 * (Double(processedCount) / Double(totalCount))
            progressHandler?(min(progress, 0.95))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GifConverterError.failedToFinalizeGIF
        }

        progressHandler?(1.0)
    }

    // MARK: - GIF to Video Conversion

    private struct GifFrame {
        let image: CGImage
        let duration: Double
    }

    /// Converts an animated or static GIF into a video file (.mp4 or .mov).
    public func convertGIFToVideo(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
            throw GifConverterError.cannotReadGIF
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw GifConverterError.cannotReadGIF
        }

        guard let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GifConverterError.noValidFramesFound
        }

        // H.264 video encoding requires dimensions to be even numbers
        let videoWidth = max(2, (firstFrame.width / 2) * 2)
        let videoHeight = max(2, (firstFrame.height / 2) * 2)

        // Read all frames with durations and composite over canvas to handle GIF disposal methods
        var frames: [GifFrame] = []
        var totalLoopDuration: Double = 0.0

        let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let canvasContext = CGContext(
            data: nil,
            width: videoWidth,
            height: videoHeight,
            bitsPerComponent: 8,
            bytesPerRow: videoWidth * 4,
            space: sRGBColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw GifConverterError.noValidFramesFound
        }
        canvasContext.interpolationQuality = .high

        let canvasBounds = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)

        for index in 0..<frameCount {
            guard let rawImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            var delay: Double = 0.1
            var disposalMethod = 0

            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0.015 {
                    delay = unclamped
                } else if let clamped = gifDict[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0.015 {
                    delay = clamped
                }
                if let disposal = (gifDict["Disposal" as CFString] as? Int) ?? (gifDict["DisposalMethod" as CFString] as? Int) {
                    disposalMethod = disposal
                }
            }

            // If disposal method is Restore to Background (2), clear the canvas
            if disposalMethod == 2 {
                canvasContext.clear(canvasBounds)
            }

            canvasContext.draw(rawImage, in: canvasBounds)
            if let composited = canvasContext.makeImage() {
                frames.append(GifFrame(image: composited, duration: delay))
                totalLoopDuration += delay
            }
        }

        guard !frames.isEmpty else {
            throw GifConverterError.noValidFramesFound
        }

        // If total loop duration is short (< 2.0s), repeat loops so it plays smoothly in QuickTime/players
        let minimumDuration = 2.0
        let repeatCount: Int
        if totalLoopDuration > 0 && totalLoopDuration < minimumDuration {
            repeatCount = max(1, Int(ceil(minimumDuration / totalLoopDuration)))
        } else {
            repeatCount = 1
        }

        var sequenceToWrite: [GifFrame] = []
        for _ in 0..<repeatCount {
            sequenceToWrite.append(contentsOf: frames)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let fileType: AVFileType = outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        // Calculate bitrate based on resolution and quality setting
        let bitRate = Int(Double(videoWidth * videoHeight) * 4.5 * max(0.2, quality))
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]

        // Do not force AVVideoColorPropertiesKey; omitting it allows macOS VideoToolbox and
        // QuickTime to decode with natural display colorimetry without triggering the ColorSync
        // BT.709 gamma shift (which lifts midtones and causes a yellow hue).
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        // Standard Apple hardware encoder format is 32BGRA
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw GifConverterError.cannotAddWriterInput
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw GifConverterError.writingFailed(writer.error?.localizedDescription ?? "Could not start writing")
        }

        writer.startSession(atSourceTime: .zero)

        var currentTime: Double = 0.0
        let totalFramesCount = sequenceToWrite.count
        var writtenCount = 0

        progressHandler?(0.05)

        for frame in sequenceToWrite {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CancellationError()
            }

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            guard let buffer = createPixelBuffer(
                from: frame.image,
                width: videoWidth,
                height: videoHeight,
                pool: adaptor.pixelBufferPool
            ) else {
                continue
            }

            let presentationTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            if !adaptor.append(buffer, withPresentationTime: presentationTime) {
                throw GifConverterError.writingFailed(writer.error?.localizedDescription ?? "Failed appending pixel buffer")
            }

            currentTime += frame.duration
            writtenCount += 1
            let progress = 0.05 + 0.90 * (Double(writtenCount) / Double(totalFramesCount))
            progressHandler?(min(progress, 0.95))
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw GifConverterError.writingFailed(writer.error?.localizedDescription ?? "Writing finished with failure status")
        }

        progressHandler?(1.0)
    }

    private func createPixelBuffer(
        from image: CGImage,
        width: Int,
        height: Int,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool = pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        }
        if pixelBuffer == nil {
            let attrs = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
            ] as CFDictionary
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attrs,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess else { return nil }
        }
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let pxData = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        // Little-endian premultipliedFirst creates the exact 32BGRA byte arrangement expected by the encoder
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: pxData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: sRGBColorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
