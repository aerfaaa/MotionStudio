import SwiftUI
import MotionCore

/// Change the composition's size, frame rate and length. Layers keep their pixel size and position,
/// so artwork is never stretched when the canvas changes.
@MainActor
struct CompositionSettingsSheet: View {
    let model: EditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var width: Int
    @State private var height: Int
    @State private var rate: FrameRateOption
    @State private var seconds: Double

    init(model: EditorModel) {
        self.model = model
        let composition = model.composition
        _width = State(initialValue: composition.width)
        _height = State(initialValue: composition.height)
        let current = FrameRateOption.all.first(where: { $0.rate == composition.frameRate })
            ?? FrameRateOption(label: composition.frameRate.displayName, rate: composition.frameRate)
        _rate = State(initialValue: current)
        _seconds = State(initialValue: (composition.duration.seconds * 100).rounded() / 100)
    }

    private var rateOptions: [FrameRateOption] {
        FrameRateOption.all.contains(rate) ? FrameRateOption.all : FrameRateOption.all + [rate]
    }

    private var isValid: Bool {
        width >= SetCompositionSettings.minimumSize && width <= SetCompositionSettings.maximumSize
            && height >= SetCompositionSettings.minimumSize && height <= SetCompositionSettings.maximumSize
            && seconds > 0 && seconds <= 3600
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ResolutionPreset.all) { preset in
                        Button {
                            width = preset.width
                            height = preset.height
                        } label: {
                            HStack {
                                Text(preset.label).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if preset.width == width && preset.height == height {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: $width, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: $height, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                } header: {
                    Text("Size in pixels")
                } footer: {
                    Text("From \(SetCompositionSettings.minimumSize) to \(SetCompositionSettings.maximumSize) pixels. Layers keep their size and position, so nothing is stretched.")
                }

                Section("Timing") {
                    Picker("Frame rate", selection: $rate) {
                        ForEach(rateOptions) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    HStack {
                        Text("Length in seconds")
                        Spacer()
                        TextField("Seconds", value: $seconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                if !isValid {
                    Section {
                        Text("Check the values: sizes must be \(SetCompositionSettings.minimumSize) to \(SetCompositionSettings.maximumSize) pixels and the length must be between 0 and 3600 seconds.")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Composition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.applyCompositionSettings(width: width, height: height,
                                                       frameRate: rate.rate, durationSeconds: seconds)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
