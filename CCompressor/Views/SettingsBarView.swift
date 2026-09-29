import SwiftUI

public struct SettingsBarView: View {
    @Bindable public var manager: CompressionManager

    public init(manager: CompressionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    // Section 1: Quality
                    qualityCard

                    // Section 2: Format Conversion
                    conversionCard

                    // Section 3: Destination & Suffix
                    destinationCard

                    // Section 4: Readjusted Batch Metrics (Before & After)
                    if !manager.items.isEmpty {
                        metricsCard
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }

            // Pinned Primary Action Button at bottom
            VStack(spacing: 0) {
                Divider()
                actionButton
                    .padding(12)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        }
    }

    // MARK: - Quality Card (Compact, Non-Clipping, Fully Visible)

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quality", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("\(Int(manager.settings.quality * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)
            }

            // Adaptive Preset Pills (replaces segmented control to prevent clipping in narrow sidebar)
            HStack(spacing: 4) {
                ForEach(QualityPreset.allCases) { preset in
                    let isSelected = manager.settings.selectedPreset == preset
                    Button {
                        manager.settings.setPreset(preset)
                    } label: {
                        Text(presetTitle(preset))
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Continuous Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Slider(
                        value: Binding(
                            get: { manager.settings.quality },
                            set: { manager.settings.setQuality($0) }
                        ),
                        in: 0.05...1.0,
                        step: 0.01
                    )

                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Text(qualityDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func presetTitle(_ preset: QualityPreset) -> String {
        switch preset {
        case .lossless:
            return "Lossless"
        case .maxQuality:
            return "High"
        case .balanced:
            return "Balanced"
        case .maxCompression:
            return "Low"
        case .custom:
            return "Custom"
        }
    }

    private var qualityDescription: String {
        switch manager.settings.selectedPreset {
        case .lossless:
            return "Lossless (100%): Preserves original data with zero compression; converts format only if selected."
        case .maxQuality:
            return "High (80%): High fidelity preservation with moderate compression."
        case .balanced:
            return "Balanced (65%): Optimal balance of quality and file size reduction."
        case .maxCompression:
            return "Low (40%): Maximum compression for rapid sharing and minimal footprint."
        case .custom:
            return "Custom: \(Int(manager.settings.quality * 100))% quality setting."
        }
    }

    // MARK: - Format Conversion Card

    private var conversionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Format Conversion", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))

            if manager.hasConvertibleItems {
                VStack(spacing: 8) {
                    if manager.hasImageItems {
                        formatPickerRow(
                            label: "Images",
                            icon: "photo",
                            selection: Binding(
                                get: { manager.settings.defaultImageFormat },
                                set: { newFormat in
                                    manager.settings.defaultImageFormat = newFormat
                                    manager.setDefaultFormat(for: .image, extensionName: newFormat.extensionName)
                                }
                            ),
                            options: ImageOutputFormat.allCases
                        )
                    }

                    if manager.hasAudioItems {
                        formatPickerRow(
                            label: "Audio",
                            icon: "waveform",
                            selection: Binding(
                                get: { manager.settings.defaultAudioFormat },
                                set: { newFormat in
                                    manager.settings.defaultAudioFormat = newFormat
                                    manager.setDefaultFormat(for: .audio, extensionName: newFormat.extensionName)
                                }
                            ),
                            options: AudioOutputFormat.allCases
                        )
                    }

                    if manager.hasVideoItems {
                        formatPickerRow(
                            label: "Video",
                            icon: "film",
                            selection: Binding(
                                get: { manager.settings.defaultVideoFormat },
                                set: { newFormat in
                                    manager.settings.defaultVideoFormat = newFormat
                                    manager.setDefaultFormat(for: .video, extensionName: newFormat.extensionName)
                                }
                            ),
                            options: VideoOutputFormat.allCases
                        )
                    }
                }
            } else {
                Text("No files ready for format conversion.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func formatPickerRow<T: Identifiable & Hashable & RawRepresentable>(
        label: String,
        icon: String,
        selection: Binding<T>,
        options: [T]
    ) -> some View where T.RawValue == String {
        HStack(spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 4)

            Picker("", selection: selection) {
                ForEach(options) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    // MARK: - Destination & Suffix Card

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Output Destination", systemImage: "folder")
                .font(.system(size: 13, weight: .semibold))

            Picker("Output Destination", selection: $manager.settings.destinationMode) {
                ForEach(OutputDestinationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if manager.settings.destinationMode == .customFolder {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 11))

                        if let customURL = manager.settings.customDestinationURL {
                            Text(customURL.lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(customURL.path)
                        } else {
                            Text("No folder selected")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button("Choose...") {
                            manager.chooseCustomDestinationFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let customURL = manager.settings.customDestinationURL {
                        Text(customURL.path)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.leading, 18)
            }

            Divider()

            // Universal Suffix Configuration
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("File Suffix:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("e.g. _compressed", text: $manager.settings.fileSuffix)
                        .textFieldStyle(.roundedBorder)
                }

                Text(suffixPreviewText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var suffixPreviewText: String {
        let suffix = manager.settings.fileSuffix
        let ext = manager.settings.defaultImageFormat.extensionName ?? "jpg"
        if manager.settings.destinationMode == .customFolder, let customURL = manager.settings.customDestinationURL {
            return "Example: [\(customURL.lastPathComponent)]/photo\(suffix).\(ext)"
        } else {
            return "Example: photo\(suffix).\(ext)"
        }
    }

    // MARK: - Readjusted Batch Metrics Card (Before & After)

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with responsive status pill
            HStack(alignment: .center) {
                Label("Batch Metrics", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 6)

                Text(completionStatusText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(manager.failedCount > 0 ? .red : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(manager.failedCount > 0 ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Storage Comparison Bar
            if manager.hasCompletedItems {
                StorageComparisonBarView(
                    originalBytes: manager.completedOriginalBytes,
                    compressedBytes: manager.completedCompressedBytes,
                    savedBytes: manager.netSavedBytes,
                    savingsPercentage: manager.netSavingsPercentage
                )
            }

            // Before & After Breakdown Grid
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                if manager.hasCompletedItems {
                    // Before (Original or Processed)
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(manager.isAllCompleted ? "Before (Original):" : "Before (Processed):")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("avg \(manager.formattedCompletedAverageOriginal) / file")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }

                        Text(manager.formattedCompletedOriginal)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .gridColumnAlignment(.trailing)
                    }

                    // After (Compressed)
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("After (Compressed):")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("avg \(manager.formattedAverageCompressed) / file")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }

                        Text(manager.formattedCompletedCompressed)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .gridColumnAlignment(.trailing)
                    }

                    Divider()
                        .gridCellColumns(2)

                    // Total Difference
                    GridRow {
                        Text("Total Difference:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)

                        differenceText
                            .gridColumnAlignment(.trailing)
                    }
                } else {
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Total Queue:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("avg \(manager.formattedAverageOriginal) / file")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }

                        Text(manager.formattedTotalOriginal)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .gridColumnAlignment(.trailing)
                    }

                    GridRow {
                        Text("Status:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("Ready (\(manager.items.count) file\(manager.items.count == 1 ? "" : "s"))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var differenceText: some View {
        if manager.isNetSaved {
            Text("-\(manager.formattedNetDifference) (-\(Int(manager.netSavingsPercentage))%)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if manager.isNetExpansion {
            Text("+\(manager.formattedNetDifference) (+\(Int(abs(manager.netSavingsPercentage)))%)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("0 B (0%)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var completionStatusText: String {
        if manager.failedCount > 0 {
            return "\(manager.completedCount)/\(manager.items.count) (\(manager.failedCount) failed)"
        } else {
            return "\(manager.completedCount)/\(manager.items.count) completed"
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if manager.isProcessing {
                Button(role: .destructive) {
                    manager.cancel()
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Cancel Compression")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    manager.compressAll()
                } label: {
                    Label(
                        manager.items.isEmpty ? "Compress Files" : "Compress \(manager.items.count) File\(manager.items.count == 1 ? "" : "s")",
                        systemImage: "arrow.down.right.and.arrow.up.left"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(manager.items.isEmpty)
                .keyboardShortcut("r", modifiers: .command)
                .help("Start compressing all files (⌘R)")
            }
        }
    }
}
