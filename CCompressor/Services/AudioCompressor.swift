import Foundation
import AudioToolbox
import AVFoundation

public struct AudioCompressor: FileCompressorProtocol {
    public init() {}

    public enum AudioCompressorError: LocalizedError {
        case unableToOpenSource(OSStatus)
        case unableToCreateDestination(OSStatus)
        case configurationFailed(OSStatus)
        case readFailed(OSStatus)
        case writeFailed(OSStatus)
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .unableToOpenSource(let status):
                return "Could not open source audio file (error code \(status))."
            case .unableToCreateDestination(let status):
                return "Could not create destination audio file (error code \(status))."
            case .configurationFailed(let status):
                return "Failed to configure audio converter (error code \(status))."
            case .readFailed(let status):
                return "Failed to read audio data (error code \(status))."
            case .writeFailed(let status):
                return "Failed to write audio data (error code \(status))."
            case .unsupportedFormat:
                return "Unsupported audio format."
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

        try await transcodeAudio(
            inputURL: inputURL,
            outputURL: outputURL,
            quality: quality,
            progressHandler: progressHandler
        )

        // Universal invariant: if same format and size didn't reduce, preserve original
        let finalSize = CompressionItem.fileSize(for: outputURL)
        if !isFormatConversion && originalSize > 0 && finalSize >= originalSize {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        }

        progressHandler?(1.0)
    }

    private func transcodeAudio(
        inputURL: URL,
        outputURL: URL,
        quality: Double,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        var sourceFile: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(inputURL as CFURL, &sourceFile)
        guard status == noErr, let source = sourceFile else {
            throw AudioCompressorError.unableToOpenSource(status)
        }
        defer {
            ExtAudioFileDispose(source)
        }

        // Get source file audio format
        var sourceFormat = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(source, kExtAudioFileProperty_FileDataFormat, &propSize, &sourceFormat)
        guard status == noErr else {
            throw AudioCompressorError.unableToOpenSource(status)
        }

        // Get total frame length for progress estimation
        var totalFrames: Int64 = 0
        var framePropSize = UInt32(MemoryLayout<Int64>.size)
        _ = ExtAudioFileGetProperty(source, kExtAudioFileProperty_FileLengthFrames, &framePropSize, &totalFrames)

        let channels = max(sourceFormat.mChannelsPerFrame, 1)
        let sampleRate = sourceFormat.mSampleRate > 0 ? sourceFormat.mSampleRate : 44100.0

        let targetExt = outputURL.pathExtension.lowercased()
        let fileTypeID: AudioFileTypeID
        var destFormat = AudioStreamBasicDescription()

        switch targetExt {
        case "wav":
            fileTypeID = kAudioFileWAVEType
            destFormat = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2 * channels,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2 * channels,
                mChannelsPerFrame: channels,
                mBitsPerChannel: 16,
                mReserved: 0
            )

        case "aiff", "aif":
            fileTypeID = kAudioFileAIFFType
            destFormat = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2 * channels,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2 * channels,
                mChannelsPerFrame: channels,
                mBitsPerChannel: 16,
                mReserved: 0
            )

        case "m4a", "aac":
            fileTypeID = kAudioFileM4AType
            destFormat = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: min(channels, 2),
                mBitsPerChannel: 0,
                mReserved: 0
            )

        default:
            // Fallback default: M4A AAC
            fileTypeID = kAudioFileM4AType
            destFormat = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: min(channels, 2),
                mBitsPerChannel: 0,
                mReserved: 0
            )
        }

        var destinationFile: ExtAudioFileRef?
        status = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            fileTypeID,
            &destFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &destinationFile
        )
        guard status == noErr, let dest = destinationFile else {
            throw AudioCompressorError.unableToCreateDestination(status)
        }
        defer {
            ExtAudioFileDispose(dest)
        }

        // Configure client PCM format for streaming between source and dest
        let clientChannels = destFormat.mChannelsPerFrame
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2 * clientChannels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * clientChannels,
            mChannelsPerFrame: clientChannels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        let clientFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileSetProperty(source, kExtAudioFileProperty_ClientDataFormat, clientFormatSize, &clientFormat)
        guard status == noErr else {
            throw AudioCompressorError.configurationFailed(status)
        }

        status = ExtAudioFileSetProperty(dest, kExtAudioFileProperty_ClientDataFormat, clientFormatSize, &clientFormat)
        guard status == noErr else {
            throw AudioCompressorError.configurationFailed(status)
        }

        // Configure bit rate for AAC compression if applicable
        if destFormat.mFormatID == kAudioFormatMPEG4AAC {
            var converter: AudioConverterRef?
            var convSize = UInt32(MemoryLayout<AudioConverterRef?>.size)
            if ExtAudioFileGetProperty(dest, kExtAudioFileProperty_AudioConverter, &convSize, &converter) == noErr,
               let conv = converter {
                let clampedQuality = min(max(quality, 0.05), 1.0)
                // Map quality to bitrate: 64 kbps to 256 kbps (per channel adjusted)
                let baseBitrate = UInt32(64_000 + (clampedQuality * 192_000))
                var targetBitrate = baseBitrate * clientChannels / 2
                targetBitrate = max(64_000, min(targetBitrate, 320_000))
                _ = AudioConverterSetProperty(conv, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &targetBitrate)
            }
        }

        // Buffer and process audio in chunks
        let bufferFrameCapacity: UInt32 = 4096
        let bufferByteCapacity = bufferFrameCapacity * clientFormat.mBytesPerFrame
        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferByteCapacity), alignment: 16)
        defer {
            rawBuffer.deallocate()
        }

        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = clientChannels

        var processedFrames: Int64 = 0

        while true {
            if Task.isCancelled {
                throw CancellationError()
            }

            var framesToRead = bufferFrameCapacity
            bufferList.mBuffers.mDataByteSize = bufferByteCapacity
            bufferList.mBuffers.mData = rawBuffer

            status = ExtAudioFileRead(source, &framesToRead, &bufferList)
            guard status == noErr else {
                throw AudioCompressorError.readFailed(status)
            }

            if framesToRead == 0 {
                break
            }

            status = ExtAudioFileWrite(dest, framesToRead, &bufferList)
            guard status == noErr else {
                throw AudioCompressorError.writeFailed(status)
            }

            processedFrames += Int64(framesToRead)
            if totalFrames > 0 {
                let progress = 0.05 + (Double(processedFrames) / Double(totalFrames)) * 0.90
                progressHandler?(min(max(progress, 0.05), 0.99))
            }
        }
    }
}
