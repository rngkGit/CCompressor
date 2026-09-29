import Foundation

public enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case lossless = "Lossless (100%)"
    case maxQuality = "High (80%)"
    case balanced = "Balanced (65%)"
    case maxCompression = "Smallest (40%)"
    case custom = "Custom"

    public var id: String { rawValue }

    public var defaultQuality: Double {
        switch self {
        case .lossless:
            return 1.0
        case .maxQuality:
            return 0.80
        case .balanced:
            return 0.65
        case .maxCompression:
            return 0.40
        case .custom:
            return 0.65
        }
    }
}

public enum OutputDestinationMode: String, CaseIterable, Identifiable, Sendable {
    case sameFolder = "Same folder as original"
    case customFolder = "Custom folder"

    public var id: String { rawValue }
}

public enum ImageOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case matchOriginal = "Original"
    case jpeg = "JPEG (.jpg)"
    case png = "PNG (.png)"
    case heic = "HEIC (.heic)"
    case tiff = "TIFF (.tiff)"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .matchOriginal: return "Original"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    public var extensionName: String? {
        switch self {
        case .matchOriginal: return nil
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }
}

public enum AudioOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case matchOriginal = "Original"
    case wav = "WAV (.wav)"
    case m4a = "M4A (.m4a)"
    case aiff = "AIFF (.aiff)"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .matchOriginal: return "Original"
        case .wav: return "WAV"
        case .m4a: return "M4A"
        case .aiff: return "AIFF"
        }
    }

    public var extensionName: String? {
        switch self {
        case .matchOriginal: return nil
        case .wav: return "wav"
        case .m4a: return "m4a"
        case .aiff: return "aiff"
        }
    }
}

public enum VideoOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case matchOriginal = "Original"
    case mp4 = "MP4 (.mp4)"
    case mov = "MOV (.mov)"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .matchOriginal: return "Original"
        case .mp4: return "MP4"
        case .mov: return "MOV"
        }
    }

    public var extensionName: String? {
        switch self {
        case .matchOriginal: return nil
        case .mp4: return "mp4"
        case .mov: return "mov"
        }
    }
}

public struct CompressionSettings: Sendable {
    public var selectedPreset: QualityPreset = .balanced
    public var quality: Double = 0.65
    public var destinationMode: OutputDestinationMode = .sameFolder
    public var customDestinationURL: URL? = nil
    public var fileSuffix: String = "_compressed"

    public var defaultImageFormat: ImageOutputFormat = .matchOriginal
    public var defaultAudioFormat: AudioOutputFormat = .matchOriginal
    public var defaultVideoFormat: VideoOutputFormat = .matchOriginal

    public var isLossless: Bool {
        selectedPreset == .lossless
    }

    public init() {}

    public mutating func setPreset(_ preset: QualityPreset) {
        selectedPreset = preset
        if preset != .custom {
            quality = preset.defaultQuality
        }
    }

    public mutating func setQuality(_ newQuality: Double) {
        quality = min(max(newQuality, 0.05), 1.0)
        selectedPreset = .custom
    }
}
