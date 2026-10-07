import Foundation
import UniformTypeIdentifiers
import AppKit

public enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case image = "Image"
    case audio = "Audio"
    case video = "Video"
    case pdf = "PDF"
    case unsupported = "Unsupported"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .video:
            return "film"
        case .pdf:
            return "doc.richtext"
        case .unsupported:
            return "questionmark.circle"
        }
    }

    public var supportedOutputExtensions: [String] {
        switch self {
        case .image:
            return ["jpg", "png", "heic", "tiff", "gif"]
        case .audio:
            return ["wav", "m4a", "aiff"]
        case .video:
            return ["mp4", "mov", "gif"]
        case .pdf:
            return ["pdf"]
        case .unsupported:
            return []
        }
    }

    public static func displayName(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg":
            return "JPEG (.jpg)"
        case "png":
            return "PNG (.png)"
        case "heic":
            return "HEIC (.heic)"
        case "tiff", "tif":
            return "TIFF (.tiff)"
        case "gif":
            return "GIF (.gif)"
        case "wav":
            return "WAV (.wav)"
        case "m4a":
            return "M4A (.m4a)"
        case "aiff", "aif":
            return "AIFF (.aiff)"
        case "mp3":
            return "MP3 (.mp3)"
        case "mp4":
            return "MP4 (.mp4)"
        case "mov":
            return "MOV (.mov)"
        case "pdf":
            return "PDF (.pdf)"
        default:
            return ext.uppercased()
        }
    }
}

public enum CompressionStatus: Equatable, Sendable {
    case pending
    case compressing(progress: Double)
    case completed(outputURL: URL, compressedSize: Int64)
    case failed(message: String)

    public var isFinished: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .pending, .compressing:
            return false
        }
    }
}

public struct CompressionItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let fileName: String
    public let originalSize: Int64
    public let category: FileCategory
    public var status: CompressionStatus
    public var targetExtension: String?

    public static func fileSize(for url: URL) -> Int64 {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    public static func displayName(forExtension ext: String) -> String {
        FileCategory.displayName(forExtension: ext)
    }

    public init(url: URL, targetExtension: String? = nil) {
        self.id = UUID()
        self.sourceURL = url
        self.fileName = url.lastPathComponent
        self.originalSize = CompressionItem.fileSize(for: url)
        self.targetExtension = targetExtension

        let resources = try? url.resourceValues(forKeys: [.contentTypeKey])
        if let contentType = resources?.contentType {
            if contentType.conforms(to: .image) {
                self.category = .image
            } else if contentType.conforms(to: .audio) {
                self.category = .audio
            } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                self.category = .video
            } else if contentType.conforms(to: .pdf) {
                self.category = .pdf
            } else {
                self.category = .unsupported
            }
        } else {
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "webp", "tiff", "tif", "bmp", "gif", "avif"].contains(ext) {
                self.category = .image
            } else if ["mp3", "wav", "m4a", "aac", "flac", "aiff", "aif", "caf", "alac", "ogg"].contains(ext) {
                self.category = .audio
            } else if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) {
                self.category = .video
            } else if ext == "pdf" {
                self.category = .pdf
            } else {
                self.category = .unsupported
            }
        }

        self.status = .pending
    }

    public var sourceExtension: String {
        sourceURL.pathExtension.lowercased()
    }

    public var effectiveExtension: String {
        targetExtension?.lowercased() ?? sourceExtension
    }

    public var isConvertingFormat: Bool {
        guard let target = targetExtension else { return false }
        return target.lowercased() != sourceExtension
    }

    public var availableTargetExtensions: [String] {
        if sourceExtension == "gif" {
            return ["mp4", "mov", "jpg", "png", "heic", "tiff"]
        }
        return category.supportedOutputExtensions
    }

    public var compressedSize: Int64? {
        if case .completed(_, let size) = status {
            return size
        }
        return nil
    }

    public var outputURL: URL? {
        if case .completed(let url, _) = status {
            return url
        }
        return nil
    }

    public var isAlreadyOptimal: Bool {
        guard let compressedSize = compressedSize else { return false }
        if isConvertingFormat { return false }
        return compressedSize >= originalSize
    }

    public var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    public var formattedCompressedSize: String? {
        guard let compressedSize = compressedSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    public var savedPercentage: Double? {
        guard let compressedSize = compressedSize, originalSize > 0 else { return nil }
        let diff = Double(originalSize - compressedSize)
        return max(0.0, (diff / Double(originalSize)) * 100.0)
    }

    public var isSizeIncreased: Bool {
        guard let compressedSize = compressedSize else { return false }
        return compressedSize > originalSize
    }

    public var expansionPercentage: Double? {
        guard let compressedSize = compressedSize, originalSize > 0, compressedSize > originalSize else { return nil }
        let diff = Double(compressedSize - originalSize)
        return (diff / Double(originalSize)) * 100.0
    }

    public var savedBytes: Int64? {
        guard let compressedSize = compressedSize else { return nil }
        return max(0, originalSize - compressedSize)
    }
}
