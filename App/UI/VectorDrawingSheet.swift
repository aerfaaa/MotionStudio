import SwiftUI
import MotionCore

/// A small freehand drawing surface that creates an editable vector-path layer.
struct VectorDrawingSheet: View {
    let compositionWidth: Int
    let compositionHeight: Int
    let onSave: ([Vec2]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var points: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Draw one continuous stroke. It becomes an editable vector layer on the timeline.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceRaised)
                        RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1)
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                        }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .onAppear { canvasSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in canvasSize = size }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = CGPoint(x: min(max(0, value.location.x), geometry.size.width),
                                                y: min(max(0, value.location.y), geometry.size.height))
                            if points.isEmpty || hypot(point.x - (points.last?.x ?? point.x), point.y - (points.last?.y ?? point.y)) >= 2 {
                                points.append(point)
                            }
                        }
                    )
                }
                .aspectRatio(CGFloat(compositionWidth) / CGFloat(max(1, compositionHeight)), contentMode: .fit)
                HStack {
                    Button("Clear", systemImage: "eraser") { points.removeAll() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Add Vector Layer", systemImage: "checkmark") {
                        guard points.count >= 2 else { return }
                        let scaleX = Double(compositionWidth) / max(1, Double(canvasSize.width))
                        let scaleY = Double(compositionHeight) / max(1, Double(canvasSize.height))
                        let mapped = points.map { Vec2(x: Double($0.x) * scaleX, y: Double($0.y) * scaleY) }
                        onSave(mapped)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(points.count < 2)
                }
            }
            .padding(16)
            .navigationTitle("Vector Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
