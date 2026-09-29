import SwiftUI
import AppKit

public struct FileThumbnailView: View {
    public let url: URL
    public let category: FileCategory
    public var size: CGFloat = 44

    @State private var thumbnail: NSImage? = nil
    @State private var isLoading: Bool = true

    public init(url: URL, category: FileCategory, size: CGFloat = 44) {
        self.url = url
        self.category = category
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(categoryTintColor.opacity(0.12))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: category.iconName)
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundColor(categoryTintColor)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Small extension pill badge
            Text(fileExtension)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(categoryTintColor.opacity(0.85))
                )
                .offset(x: 2, y: 2)
        }
        .task(id: url) {
            let loaded = await ThumbnailService.shared.getThumbnail(
                for: url,
                size: CGSize(width: size * 2, height: size * 2)
            )
            await MainActor.run {
                self.thumbnail = loaded
                self.isLoading = false
            }
        }
    }

    private var fileExtension: String {
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }

    private var categoryTintColor: Color {
        switch category {
        case .image:
            return .blue
        case .audio:
            return .teal
        case .video:
            return .purple
        case .pdf:
            return .red
        case .unsupported:
            return .gray
        }
    }
}
