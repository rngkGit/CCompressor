import SwiftUI
import UniformTypeIdentifiers
import QuickLook

public struct ContentView: View {
    @State private var manager = CompressionManager()
    @State private var previewURL: URL? = nil
    @State private var isInspectorPresented: Bool = true

    public init() {}

    public var body: some View {
        ZStack {
            if manager.items.isEmpty {
                emptyStateDropZone
            } else {
                fileListView
            }

            // Frosted Drag Overlay
            if manager.isTargetedForDrop {
                dragTargetOverlay
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .inspector(isPresented: $isInspectorPresented) {
            SettingsBarView(manager: manager)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 480)
        }
        .onDrop(of: [.fileURL], isTargeted: $manager.isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .quickLookPreview($previewURL)
        .alert(
            manager.unsupportedFileAlert?.title ?? "Unsupported File",
            isPresented: Binding(
                get: { manager.unsupportedFileAlert != nil },
                set: { if !$0 { manager.unsupportedFileAlert = nil } }
            ),
            presenting: manager.unsupportedFileAlert
        ) { _ in
            Button("OK", role: .cancel) {
                manager.unsupportedFileAlert = nil
            }
        } message: { alertInfo in
            Text(alertInfo.message)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    manager.openFilePicker()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
                .help("Add Files (⌘O)")

                if !manager.items.isEmpty {
                    Button(role: .destructive) {
                        manager.clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Clear file queue (⌘K)")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isInspectorPresented.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Settings Inspector (⌃⌘I)")
            }
        }
    }

    // MARK: - Empty State & Drop Zone

    private var emptyStateDropZone: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 88, height: 88)

                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.accentColor.gradient)
            }

            VStack(spacing: 8) {
                Text("Drop Files to Compress & Convert")
                    .font(.system(size: 19, weight: .bold))

                Text("Reduce file sizes and convert formats for images, audio, video, and PDF documents.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Supported Format Badges
            HStack(spacing: 6) {
                formatBadge("JPG")
                formatBadge("PNG")
                formatBadge("HEIC")
                formatBadge("MP3")
                formatBadge("WAV")
                formatBadge("M4A")
                formatBadge("MP4")
                formatBadge("MOV")
                formatBadge("PDF")
            }
            .padding(.top, 2)

            Button {
                manager.openFilePicker()
            } label: {
                Label("Browse Files...", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
                .padding(24)
        )
    }

    private func formatBadge(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
    }

    // MARK: - Drag Target Overlay

    private var dragTargetOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor.gradient)

                Text("Drop Files to Add")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            )

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .padding(12)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - File List View

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(manager.items) { item in
                    FileRowView(
                        item: item,
                        onRemove: {
                            manager.removeItem(item)
                        },
                        onReveal: { outputURL in
                            manager.revealInFinder(url: outputURL)
                        },
                        onPreview: { previewTargetURL in
                            previewURL = previewTargetURL
                        },
                        onSelectTargetExtension: { targetExt in
                            manager.setTargetExtension(for: item.id, extensionName: targetExt)
                        }
                    )
                }
            }
            .padding(14)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task {
            var droppedURLs: [URL] = []

            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                    if let url = item as? URL {
                        droppedURLs.append(url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        droppedURLs.append(url)
                    }
                }
            }

            if !droppedURLs.isEmpty {
                await MainActor.run {
                    manager.addFiles(urls: droppedURLs)
                }
            }
        }
        return true
    }
}

#Preview {
    ContentView()
}
