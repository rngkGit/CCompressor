import SwiftUI

public struct StorageComparisonBarView: View {
    public let originalBytes: Int64
    public let compressedBytes: Int64
    public let savedBytes: Int64
    public let savingsPercentage: Double

    public init(
        originalBytes: Int64,
        compressedBytes: Int64,
        savedBytes: Int64,
        savingsPercentage: Double
    ) {
        self.originalBytes = originalBytes
        self.compressedBytes = compressedBytes
        self.savedBytes = savedBytes
        self.savingsPercentage = savingsPercentage
    }

    private var isExpanded: Bool {
        compressedBytes > originalBytes
    }

    private var compressedFraction: Double {
        guard originalBytes > 0 else { return 0 }
        return min(max(Double(compressedBytes) / Double(originalBytes), 0.0), 1.0)
    }

    private var savedFraction: Double {
        guard originalBytes > 0 else { return 0 }
        return min(max(Double(max(0, savedBytes)) / Double(originalBytes), 0.0), 1.0)
    }

    private var diffText: String {
        if savingsPercentage > 0 {
            return " (-\(Int(savingsPercentage))%)"
        } else if savingsPercentage < 0 {
            return " (+\(Int(abs(savingsPercentage)))%)"
        } else {
            return ""
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Graphical Bar
            GeometryReader { geometry in
                let totalWidth = geometry.size.width

                ZStack(alignment: .leading) {
                    // Base background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)

                    if isExpanded {
                        // Size expanded beyond original
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange.gradient)
                            .frame(width: totalWidth, height: 8)
                    } else {
                        // Compressed + Saved portions
                        let compWidth = max(0, min(totalWidth, totalWidth * compressedFraction))
                        let savedWidth = max(0, min(totalWidth - compWidth, totalWidth * savedFraction))

                        HStack(spacing: 0) {
                            if compWidth > 0 {
                                Rectangle()
                                    .fill(Color.accentColor.gradient)
                                    .frame(width: compWidth, height: 8)
                            }

                            if savedWidth > 0 {
                                Rectangle()
                                    .fill(Color.green.gradient)
                                    .frame(width: savedWidth, height: 8)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(height: 8)

            // Before & After Legend (Adapts automatically to available width)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text("Before: \(formattedBytes(originalBytes))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(isExpanded ? Color.orange : Color.accentColor)
                            .frame(width: 6, height: 6)

                        Text("After: \(formattedBytes(compressedBytes))\(diffText)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(isExpanded ? .orange : .primary)
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text("Before: \(formattedBytes(originalBytes))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(isExpanded ? Color.orange : Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text("After: \(formattedBytes(compressedBytes))\(diffText)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(isExpanded ? .orange : .primary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
