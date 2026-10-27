import SwiftUI
import UIKit

/// A round icon button with a comfortable 44 point touch target.
struct IconButton: View {
    let systemName: String
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

enum KeyframeState {
    /// The property is a fixed value.
    case fixed
    /// The property has keyframes, but none at the current frame.
    case animated
    /// There is a keyframe at the current frame.
    case onKeyframe
}

/// The diamond that adds or removes a keyframe at the current frame.
struct KeyframeButton: View {
    let state: KeyframeState
    let propertyName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .onKeyframe ? "diamond.fill" : "diamond")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state == .fixed ? Theme.textSecondary : Theme.keyframe)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .onKeyframe ? "Remove \(propertyName) keyframe" : "Add \(propertyName) keyframe")
    }
}

/// A number the user can type. The value is applied when they press Return or leave the field.
struct NumberField: View {
    let title: String
    let value: Double
    let onCommit: (Double) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($isFocused)
                .onSubmit(commit)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .onAppear { text = format(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = format(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(cleaned), abs(parsed - value) > 0.0001 {
            onCommit(parsed)
        }
        text = format(value)
    }

    private func format(_ number: Double) -> String {
        number == number.rounded() ? String(format: "%.0f", number) : String(format: "%.1f", number)
    }
}


/// Presents an exported file using the system share sheet, including Save to Files.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
