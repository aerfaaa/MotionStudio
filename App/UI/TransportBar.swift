import SwiftUI
import MotionCore

/// Play, pause, step and the current time.
@MainActor
struct TransportBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame \(model.currentFrame)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(String(format: "%.2f of %.2f seconds",
                            model.currentTime.seconds, model.composition.duration.seconds))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            IconButton(systemName: "backward.end.fill", label: "Go to start") { model.seek(toFrame: 0) }
            IconButton(systemName: "backward.frame.fill", label: "Previous frame") { model.step(by: -1) }
            IconButton(systemName: model.isPlaying ? "pause.fill" : "play.fill",
                       label: model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
            IconButton(systemName: "forward.frame.fill", label: "Next frame") { model.step(by: 1) }
            IconButton(systemName: "repeat", label: model.loopPlayback ? "Looping on" : "Looping off",
                       isActive: model.loopPlayback) { model.loopPlayback.toggle() }
        }
        .padding(.horizontal, 6)
    }
}
