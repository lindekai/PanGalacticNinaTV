import SwiftUI

/// Minimal trend: baseline, one grey curve, newest point in teal. Hidden below two values.
struct Sparkline: View {
    let values: [Double]

    init(_ values: [Double]) { self.values = values }

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 0.0001)
            let inset: CGFloat = 5
            func point(_ index: Int) -> CGPoint {
                let x = inset + (size.width - 2 * inset) * CGFloat(index) / CGFloat(values.count - 1)
                let y = inset + (size.height - 2 * inset) * (1 - CGFloat((values[index] - low) / span))
                return CGPoint(x: x, y: y)
            }
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(baseline, with: .color(Theme.line), lineWidth: 1)
            var curve = Path()
            curve.move(to: point(0))
            for index in 1..<values.count { curve.addLine(to: point(index)) }
            context.stroke(curve, with: .color(Theme.text2), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)),
                         with: .color(Theme.accent))
        }
        .accessibilityHidden(true)
    }
}
