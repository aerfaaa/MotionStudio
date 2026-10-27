import SwiftUI

/// Export controls are kept in a separate sheet so the editor stays uncluttered.
struct VideoExportSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var bitrateMbps: Double
    let durationSeconds: Double
    let width: Int
    let height: Int
    let onExport: () -> Void

    private let presets: [(title: String, value: Double)] = [
        ("Smaller", 4), ("Balanced", 8), ("High", 12), ("Very high", 20), ("Maximum", 35)
    ]

    private var resolutionLabel: String {
        // Bitrate is a target, not a guarantee; recommendations depend on pixel count.
        let pixels = width * height
        let recommended = pixels >= 3_500_000 ? 24.0 : (pixels >= 2_000_000 ? 12.0 : 8.0)
        if bitrateMbps < recommended * 0.5 { return "Smaller file · visible compression may occur" }
        if bitrateMbps < recommended { return "Balanced file size · some fine detail may soften" }
        if bitrateMbps < recommended * 1.8 { return "Good target for this resolution" }
        return "High detail target · larger file"
    }

    private var estimatedVideoSizeMB: Double {
        max(0, bitrateMbps) * max(0, durationSeconds) / 8
    }

    private var estimatedSizeText: String {
        if estimatedVideoSizeMB >= 1_000 {
            return String(format: "%.2f GB", estimatedVideoSizeMB / 1_000)
        }
        return String(format: "%.0f MB", estimatedVideoSizeMB)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Video bitrate", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text("Bitrate controls how much data is used for each second of video. Higher values can preserve more detail, but create larger files.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Target bitrate")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(bitrateMbps)) Mbps")
                            .font(.title2.weight(.semibold).monospacedDigit())
                    }
                    Slider(value: $bitrateMbps, in: 2...50, step: 1)
                        .tint(Theme.accent)
                    HStack {
                        Text("2 Mbps")
                        Spacer()
                        Text("50 Mbps")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    Text(resolutionLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    HStack {
                        Text("Estimated video data")
                        Spacer()
                        Text(estimatedSizeText)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick presets")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(presets, id: \.value) { preset in
                            Button {
                                bitrateMbps = preset.value
                            } label: {
                                VStack(spacing: 4) {
                                    Text(preset.title)
                                        .font(.caption.weight(.semibold))
                                    Text("\(Int(preset.value)) Mbps")
                                        .font(.caption2.monospacedDigit())
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Int(bitrateMbps) == Int(preset.value) ? Theme.accent.opacity(0.18) : Theme.surface,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Int(bitrateMbps) == Int(preset.value) ? Theme.accent : Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                Text("The chosen bitrate is applied to the H.264 MP4 video. Actual file size varies with duration, frame rate, motion, and image complexity.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)

                Spacer(minLength: 0)

                Button(action: onExport) {
                    Label("Render MP4", systemImage: "film.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Export video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
