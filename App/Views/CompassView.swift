import PanGalacticCore
import SwiftUI

/// Sky seen from above: N up, E right (as the local compass rose, east to the right when
/// facing north on the map), zenith in the centre, horizon on the rim. Telescope as a dot,
/// Sun and Moon as rings, dashed and on the rim when below the horizon; the telescope dot
/// is dimmed while stale.
struct CompassView: View {
    let now: NightNow
    let telescope: Horizontal?
    /// Dimmed like every stale value: the pointing is from the last successful poll.
    var telescopeIsStale = false

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2 - 4
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ h: Horizontal) -> CGPoint {
                let d = r * CGFloat(max(0, 90 - max(h.altitude, 0)) / 90)
                let a = h.azimuth * .pi / 180
                return CGPoint(x: c.x + d * sin(a), y: c.y - d * cos(a))
            }
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.fill(disc, with: .color(Color(hex: 0x141B1F)))
            context.stroke(disc, with: .color(Theme.line), lineWidth: 2)
            for f in [1.0 / 3, 2.0 / 3] {
                let rr = r * f
                context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                               with: .color(Theme.line), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            }
            let labels: [(LocalizedStringKey, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
            for (label, az) in labels {
                let a = az * .pi / 180
                context.draw(Text(label).font(.pgRubric).foregroundStyle(Theme.text2),
                             at: CGPoint(x: c.x + (r - 22) * sin(a), y: c.y - (r - 22) * cos(a)))
            }
            func ring(_ h: Horizontal, _ color: Color) {
                let p = point(h)
                let rect = CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
                context.stroke(Path(ellipseIn: rect), with: .color(color),
                               style: StrokeStyle(lineWidth: 3, dash: h.altitude < 0 ? [4, 3] : []))
            }
            ring(now.sun, Theme.warn)
            ring(now.moon, Theme.text2)
            if let telescope {
                let p = point(telescope)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)), with: .color(Theme.accent.opacity(telescopeIsStale ? 0.55 : 1)))
            }
        }
        .accessibilityHidden(true)
    }

    /// Eight-point compass name for an azimuth (N, NE, E, … in the UI language).
    static func point(_ azimuth: Double) -> LocalizedStringKey {
        let names: [LocalizedStringKey] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((normalized + 22.5) / 45) % 8]
    }
}
