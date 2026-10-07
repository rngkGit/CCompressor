import Foundation
import SwiftUI
import AppKit

public struct UnsupportedFileAlertInfo: Identifiable, Sendable {
    public let id = UUID()
    public let fileNames: [String]

    public init(fileNames: [String]) {
        self.fileNames = fileNames
    }

    public var title: String {
        fileNames.count == 1 ? "Unsupported File" : "Unsupported Files"
    }

    public var message: String {
        if fileNames.count == 1 {
            return "The file “\(fileNames[0])” is not supported.\n\nCCompressor supports image, audio, video, and PDF files."
        } else {
            let displayedNames = fileNames.prefix(5).map { "• \($0)" }.joined(separator: "\n")
            let remaining = fileNames.count - 5
            let suffix = remaining > 0 ? "\n• ...and \(remaining) more" : ""
            return "The following \(fileNames.count) files are not supported:\n\(displayedNames)\(suffix)\n\nCCompressor supports image, audio, video, and PDF files."
        }
    }
}

@MainActor
@Observable
public final class CompressionManager {
    public var items: [CompressionItem] = []
    public var settings: CompressionSettings = CompressionSettings()
    public var isProcessing: Bool = false
    public var isTargetedForDrop: Bool = false
    public var statusMessage: String = ""
    public var unsupportedFileAlert: UnsupportedFileAlertInfo? = nil

    private var activeCompressionTask: Task<Void, Never>? = nil
    private let dispatcher = FileCompressionDispatcher()
    private var grantedFolderURLs: [URL: URL] = [:]

    public init() {}

    // MARK: - Computed Batch Stats (Before & After)

    public var totalOriginalBytes: Int64 {
        items.reduce(0) { $0 + $1.originalSize }
    }

    public var completedOriginalBytes: Int64 {
        items.reduce(0) { total, item in
            if case .completed = item.status {
                return total + item.originalSize
            }
            return total
        }
    }

    public var completedCompressedBytes: Int64 {
        items.reduce(0) { total, item in
            if case .completed(_, let size) = item.status {
                return total + size
            }
            return total
        }
    }

    public var totalCompressedBytes: Int64 {
        completedCompressedBytes
    }

    public var netSavedBytes: Int64 {
        completedOriginalBytes - completedCompressedBytes
    }

    public var completedSavedBytes: Int64 {
        max(0, netSavedBytes)
    }

    public var totalSavedBytes: Int64 {
        completedSavedBytes
    }

    public var isNetSaved: Bool {
        netSavedBytes > 0
    }

    public var isNetExpansion: Bool {
        netSavedBytes < 0
    }

    public var netSavingsPercentage: Double {
        guard completedOriginalBytes > 0 else { return 0.0 }
        return (Double(netSavedBytes) / Double(completedOriginalBytes)) * 100.0
    }

    public var completedSavingsPercentage: Double {
        max(0.0, netSavingsPercentage)
    }

    public var totalSavingsPercentage: Double {
        completedSavingsPercentage
    }

    public var averageOriginalBytes: Int64 {
        guard !items.isEmpty else { return 0 }
        return totalOriginalBytes / Int64(items.count)
    }

    public var formattedAverageOriginal: String {
        ByteCountFormatter.string(fromByteCount: averageOriginalBytes, countStyle: .file)
    }

    public var completedAverageOriginalBytes: Int64 {
        guard completedCount > 0 else { return 0 }
        return completedOriginalBytes / Int64(completedCount)
    }

    public var formattedCompletedAverageOriginal: String {
        ByteCountFormatter.string(fromByteCount: completedAverageOriginalBytes, countStyle: .file)
    }

    public var averageCompressedBytes: Int64 {
        guard completedCount > 0 else { return 0 }
        return completedCompressedBytes / Int64(completedCount)
    }

    public var formattedAverageCompressed: String {
        ByteCountFormatter.string(fromByteCount: averageCompressedBytes, countStyle: .file)
    }

    public var completedCount: Int {
        items.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    public var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    public var hasCompletedItems: Bool {
        completedCount > 0
    }

    public var isAllCompleted: Bool {
        !items.isEmpty && completedCount == items.count
    }

    public var hasImageItems: Bool {
        items.contains { $0.category == .image }
    }

    public var hasNonGifImageItems: Bool {
        items.contains { $0.category == .image && $0.sourceExtension != "gif" }
    }

    public var hasAudioItems: Bool {
        items.contains { $0.category == .audio }
    }

    public var hasVideoItems: Bool {
        items.contains { $0.category == .video }
    }

    public var hasGifItems: Bool {
        items.contains { $0.sourceExtension == "gif" }
    }

    public var hasConvertibleItems: Bool {
        hasNonGifImageItems || hasAudioItems || hasVideoItems || hasGifItems
    }

    public var formattedTotalOriginal: String {
        ByteCountFormatter.string(fromByteCount: totalOriginalBytes, countStyle: .file)
    }

    public var formattedTotalCompressed: String {
        ByteCountFormatter.string(fromByteCount: totalCompressedBytes, countStyle: .file)
    }

    public var formattedCompletedOriginal: String {
        ByteCountFormatter.string(fromByteCount: completedOriginalBytes, countStyle: .file)
    }

    public var formattedCompletedCompressed: String {
        ByteCountFormatter.string(fromByteCount: completedCompressedBytes, countStyle: .file)
    }

    public var formattedCompletedSaved: String {
        ByteCountFormatter.string(fromByteCount: completedSavedBytes, countStyle: .file)
    }

    public var formattedNetDifference: String {
        ByteCountFormatter.string(fromByteCount: abs(netSavedBytes), countStyle: .file)
    }

    // MARK: - Folder Permission Verification

    public func verifyOrRequestFolderPermission(for folderURL: URL) async -> Bool {
        if let existing = grantedFolderURLs[folderURL] {
            if FileManager.default.isWritableFile(atPath: existing.path) {
                return true
            }
        }

        if FileManager.default.isWritableFile(atPath: folderURL.path) {
            let testFileURL = folderURL.appendingPathComponent(".ccompressor_test_\(UUID().uuidString)")
            if FileManager.default.createFile(atPath: testFileURL.path, contents: Data()) {
                try? FileManager.default.removeItem(at: testFileURL)
                return true
            }
        }

        let granted = await MainActor.run { () -> Bool in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = folderURL
            panel.prompt = "Grant Access"
            panel.title = "Permission Required"
            panel.message = "CCompressor needs permission to write compressed files to “\(folderURL.lastPathComponent)”. Please select this folder to grant permission."

            if panel.runModal() == .OK, let selectedURL = panel.url {
                _ = selectedURL.startAccessingSecurityScopedResource()
                self.grantedFolderURLs[folderURL] = selectedURL
                return FileManager.default.isWritableFile(atPath: selectedURL.path)
            }
            return false
        }

        return granted
    }

    // MARK: - Item Management

    public func addFiles(urls: [URL]) {
        var discoveredURLs: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        for case let fileURL as URL in enumerator {
                            if let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                               isRegular == true {
                                discoveredURLs.append(fileURL)
                            }
                        }
                    }
                } else {
                    discoveredURLs.append(url)
                }
            }
        }

        let existingPaths = Set(items.map { $0.sourceURL.path })
        var unsupportedNames: [String] = []

        for url in discoveredURLs {
            if !existingPaths.contains(url.path) {
                var item = CompressionItem(url: url)
                if item.category != .unsupported {
                    // Apply default target format from settings if set
                    if item.sourceExtension == "gif" {
                        item.targetExtension = settings.defaultGifFormat.extensionName
                    } else {
                        switch item.category {
                        case .image:
                            item.targetExtension = settings.defaultImageFormat.extensionName
                        case .audio:
                            item.targetExtension = settings.defaultAudioFormat.extensionName
                        case .video:
                            item.targetExtension = settings.defaultVideoFormat.extensionName
                        case .pdf, .unsupported:
                            break
                        }
                    }
                    items.append(item)
                } else {
                    if !unsupportedNames.contains(url.lastPathComponent) {
                        unsupportedNames.append(url.lastPathComponent)
                    }
                }
            }
        }

        if !unsupportedNames.isEmpty {
            unsupportedFileAlert = UnsupportedFileAlertInfo(fileNames: unsupportedNames)
        }

        if items.isEmpty && !discoveredURLs.isEmpty {
            statusMessage = "No supported image, audio, video, or PDF files found."
        } else {
            statusMessage = "\(items.count) file\(items.count == 1 ? "" : "s") ready."
        }
    }

    public func setTargetExtension(for itemID: UUID, extensionName: String?) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].targetExtension = extensionName
            if case .completed = items[index].status {
                items[index].status = .pending
            }
        }
    }

    public func setDefaultFormat(for category: FileCategory, extensionName: String?) {
        for i in 0..<items.count {
            if items[i].category == category {
                if category == .image && items[i].sourceExtension == "gif" {
                    continue
                }
                items[i].targetExtension = extensionName
                if case .completed = items[i].status {
                    items[i].status = .pending
                }
            }
        }
    }

    public func setDefaultFormatForGifs(extensionName: String?) {
        for i in 0..<items.count {
            if items[i].sourceExtension == "gif" {
                items[i].targetExtension = extensionName
                if case .completed = items[i].status {
                    items[i].status = .pending
                }
            }
        }
    }

    public func removeItem(_ item: CompressionItem) {
        items.removeAll { $0.id == item.id }
    }

    public func clearAll() {
        cancel()
        items.removeAll()
        statusMessage = ""
        unsupportedFileAlert = nil
    }

    // MARK: - Compression Execution

    public func compressAll() {
        guard !isProcessing, !items.isEmpty else { return }

        isProcessing = true
        statusMessage = "Compressing files..."

        activeCompressionTask = Task { [dispatcher, settings] in
            let maxConcurrency = 2
            let pendingItems = items.filter { item in
                switch item.status {
                case .completed:
                    return false
                default:
                    return true
                }
            }

            var currentIndex = 0

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<min(maxConcurrency, pendingItems.count) {
                    if currentIndex < pendingItems.count {
                        let item = pendingItems[currentIndex]
                        currentIndex += 1
                        group.addTask {
                            await self.processItem(item, dispatcher: dispatcher, settings: settings)
                        }
                    }
                }

                while await group.next() != nil {
                    if Task.isCancelled { break }
                    if currentIndex < pendingItems.count {
                        let item = pendingItems[currentIndex]
                        currentIndex += 1
                        group.addTask {
                            await self.processItem(item, dispatcher: dispatcher, settings: settings)
                        }
                    }
                }
            }

            self.isProcessing = false
            let completed = self.completedCount
            self.statusMessage = "Compression finished (\(completed)/\(self.items.count) files)."
        }
    }

    private func processItem(
        _ item: CompressionItem,
        dispatcher: FileCompressionDispatcher,
        settings: CompressionSettings
    ) async {
        guard !Task.isCancelled else { return }

        let targetFolderURL: URL
        if settings.destinationMode == .customFolder, let customURL = settings.customDestinationURL {
            targetFolderURL = customURL
        } else {
            targetFolderURL = item.sourceURL.deletingLastPathComponent()
        }

        let hasPermission = await verifyOrRequestFolderPermission(for: targetFolderURL)
        if !hasPermission {
            self.updateItemStatus(
                id: item.id,
                status: .failed(message: "Permission denied: Cannot write to folder '\(targetFolderURL.lastPathComponent)'. Please grant folder permission or choose a custom destination folder.")
            )
            return
        }

        self.updateItemStatus(id: item.id, status: .compressing(progress: 0.05))

        do {
            let outputURL = try await dispatcher.compress(
                item: item,
                settings: settings,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateItemStatus(id: item.id, status: .compressing(progress: progress))
                    }
                }
            )

            let compressedSize = CompressionItem.fileSize(for: outputURL)

            self.updateItemStatus(
                id: item.id,
                status: .completed(outputURL: outputURL, compressedSize: compressedSize)
            )
        } catch {
            if Task.isCancelled {
                self.updateItemStatus(id: item.id, status: .pending)
            } else {
                let nsError = error as NSError
                let isPermError = nsError.domain == NSCocoaErrorDomain &&
                    (nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError) ||
                    (error as? POSIXError)?.code == .EACCES

                let errorMessage: String
                if isPermError {
                    errorMessage = "Permission denied: Cannot write to folder '\(targetFolderURL.lastPathComponent)'. Please grant access or choose a custom folder."
                } else {
                    errorMessage = error.localizedDescription
                }

                self.updateItemStatus(id: item.id, status: .failed(message: errorMessage))
            }
        }
    }

    private func updateItemStatus(id: UUID, status: CompressionStatus) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = status
        }
    }

    public func cancel() {
        activeCompressionTask?.cancel()
        activeCompressionTask = nil
        isProcessing = false
        statusMessage = "Compression cancelled."
    }

    // MARK: - Finder & Folder Helpers

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func chooseCustomDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            _ = selectedURL.startAccessingSecurityScopedResource()
            grantedFolderURLs[selectedURL] = selectedURL
            settings.customDestinationURL = selectedURL
            settings.destinationMode = .customFolder
        }
    }

    public func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Files"

        if panel.runModal() == .OK {
            addFiles(urls: panel.urls)
        }
    }
}
