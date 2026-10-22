import SwiftUI

/// A fixed-length bar with one tick per photo. Drag along it to flip through a project,
/// like a quick preview of the timelapse.
struct FrameScrubber: View {
    let count: Int
    @Binding var index: Int

    @AppStorage("haptics") private var haptics = true
    /// Counts index changes made by dragging, so page swipes don't buzz too.
    @State private var scrubTicks = 0

    private let knobSize: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let step = count > 1 ? width / CGFloat(count - 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                Canvas { context, size in
                    guard count > 1 else { return }
                    for tick in 0..<count {
                        let x = CGFloat(tick) * size.width / CGFloat(count - 1)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: size.height * 0.3))
                        line.addLine(to: CGPoint(x: x, y: size.height * 0.7))
                        context.stroke(line, with: .color(Color.white.opacity(0.45)), lineWidth: 1)
                    }
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Color.black.opacity(0.3), radius: 2)
                    .offset(x: CGFloat(index) * step - knobSize / 2)
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard count > 1, width > 0 else { return }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        let target = Int((fraction * CGFloat(count - 1)).rounded())
                        if target != index {
                            index = target
                            scrubTicks += 1
                        }
                    }
            )
        }
        .frame(height: 36)
        // Room for half the knob at each end.
        .padding(.horizontal, knobSize / 2)
        .sensoryFeedback(trigger: scrubTicks) { _, _ in
            haptics ? SensoryFeedback.selection : nil
        }
        .accessibilityElement()
        .accessibilityLabel("Photo")
        .accessibilityValue("\(index + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }
}
