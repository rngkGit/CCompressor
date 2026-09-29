import SwiftUI
import AppKit

public struct FileRowView: View {
    public let item: CompressionItem
    public let onRemove: () -> Void
    public let onReveal: (URL) -> Void
    public let onPreview: (URL) -> Void
    public let onSelectTargetExtension: (String?) -> Void

    @State private var isHovered: Bool = false

    public init(
        item: CompressionItem,
        onRemove: @escaping () -> Void,
        onReveal: @escaping (URL) -> Void,
        onPreview: @escaping (URL) -> Void,
        onSelectTargetExtension: @escaping (String?) -> Void = { _ in }
    ) {
        self.item = item
        self.onRemove = onRemove
        self.onReveal = onReveal
        self.onPreview = onPreview
        self.onSelectTargetExtension = onSelectTargetExtension
    }

    private var activeURL: URL {
        item.outputURL ?? item.sourceURL
    }

    public var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(url: item.sourceURL, category: item.category, size: 44)

            detailsView

            Spacer(minLength: 8)

            statusView

            actionButtonsView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .overlay(rowOverlay)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onPreview(activeURL)
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Row Subviews

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.availableTargetExtensions.isEmpty {
                    formatMenu
                }
            }

            HStack(spacing: 6) {
                Text("Before: \(item.formattedOriginalSize)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if let compressedSize = item.formattedCompressedSize {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text("After: \(compressedSize)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 6) {
            Button {
                onPreview(activeURL)
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quick Look Preview (Space)")

            if let outputURL = item.outputURL {
                Button {
                    onReveal(outputURL)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal compressed file in Finder")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(isHovered ? .secondary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove from list")
        }
        .opacity(isHovered || item.compressedSize != nil ? 1.0 : 0.6)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.85) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var rowOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isHovered ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onPreview(activeURL)
        } label: {
            Label("Quick Look Preview", systemImage: "eye")
        }

        if let outputURL = item.outputURL {
            Button {
                onReveal(outputURL)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        } else {
            Button {
                onReveal(item.sourceURL)
            } label: {
                Label("Reveal Original in Finder", systemImage: "folder")
            }
        }

        Button {
            NSWorkspace.shared.open(activeURL)
        } label: {
            Label("Open with Default Application", systemImage: "arrow.up.forward.app")
        }

        if !item.availableTargetExtensions.isEmpty {
            Divider()

            Menu {
                Button {
                    onSelectTargetExtension(nil)
                } label: {
                    HStack {
                        Text("Original (\(item.sourceExtension.uppercased()))")
                        if !item.isConvertingFormat {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(item.availableTargetExtensions, id: \.self) { ext in
                    Button {
                        onSelectTargetExtension(ext)
                    } label: {
                        HStack {
                            Text(CompressionItem.displayName(forExtension: ext))
                            if item.targetExtension?.lowercased() == ext.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Convert Format", systemImage: "arrow.triangle.2.circlepath")
            }
        }

        Divider()

        Button(role: .destructive, action: onRemove) {
            Label("Remove from List", systemImage: "trash")
        }
    }

    // MARK: - Format Conversion Menu

    private var formatMenu: some View {
        Menu {
            Button {
                onSelectTargetExtension(nil)
            } label: {
                HStack {
                    Text("Original (\(item.sourceExtension.uppercased()))")
                    if !item.isConvertingFormat {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(item.availableTargetExtensions, id: \.self) { ext in
                Button {
                    onSelectTargetExtension(ext)
                } label: {
                    HStack {
                        Text(CompressionItem.displayName(forExtension: ext))
                        if item.targetExtension?.lowercased() == ext.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                if item.isConvertingFormat {
                    Text("\(item.sourceExtension.uppercased()) \u{2192} \(item.effectiveExtension.uppercased())")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                } else {
                    Text(item.sourceExtension.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
                    .foregroundColor(item.isConvertingFormat ? .accentColor : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(item.isConvertingFormat ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(item.isConvertingFormat ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(item.isConvertingFormat ? "Converting to .\(item.effectiveExtension) — Click to change format" : "Click to convert format")
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending:
            Text("Ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))

        case .compressing(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 64)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

        case .completed:
            if item.isConvertingFormat {
                if let pct = item.savedPercentage, pct > 0 {
                    Text("-\(Int(pct))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                } else if let exp = item.expansionPercentage, exp > 0 {
                    Text("+\(Int(exp))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .help("File format converted (uncompressed output format)")
                } else {
                    Text("Converted")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.teal.opacity(0.15)))
                }
            } else if item.isAlreadyOptimal {
                Text("Optimal")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.blue.opacity(0.12))
                    )
                    .help("File was already maximally compressed.")
            } else if let pct = item.savedPercentage {
                Text("-\(Int(pct))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.green.opacity(0.15))
                    )
            }

        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)

                Text("Failed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
            }
            .help(message)
        }
    }
}
