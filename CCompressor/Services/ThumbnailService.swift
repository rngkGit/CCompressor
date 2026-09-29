import Foundation
import QuickLookThumbnailing
import AppKit

/// Service responsible for generating and caching file thumbnails using QuickLookThumbnailing.
@MainActor
public final class ThumbnailService {
    public static let shared = ThumbnailService()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    /// Fetches or generates a thumbnail for the specified file URL.
    public func getThumbnail(for url: URL, size: CGSize = CGSize(width: 88, height: 88)) async -> NSImage? {
        let nsURL = url as NSURL
        if let cachedImage = cache.object(forKey: nsURL) {
            return cachedImage
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2.0,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = representation.nsImage
            cache.setObject(image, forKey: nsURL)
            return image
        } catch {
            return nil
        }
    }
}
