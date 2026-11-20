import PanGalacticCore
import SwiftUI

/// Altitude over the night: twilight bands from the Sun's altitude, 0/30/60° lines,
/// target in accent, Moon dashed (only above the horizon), meridian transit, now line.
struct AltitudeChart: View {
    enum Style { case full, mini }
    let plan: NightPlan
    let now: Date
    let style: Style

    static func band(_ sunAltitude: Double) -> Color {
        switch sunAltitude {
        case ..<(-18): Color(hex: 0x141B1F)
        case ..<(-12): Color(hex: 0x1B252B)
        case ..<(-6): Color(hex: 0x1F2A31)
        case ..<(-0.833): Color(hex: 0x24323A)
        default: Color(hex: 0x2B3B44)
        }
    }

    var body: some View {
        Canvas { context, size in
            let range = plan.chartRange
            let left: CGFloat = style == .full ? 56 : 0
            let bottom: CGFloat = style == .full ? 34 : 0
            let plot = CGRect(x: left, y: 0, width: size.width - left, height: size.height - bottom)
            func x(_ date: Date) -> CGFloat {
                plot.minX + plot.width * CGFloat(date.timeIntervalSince(range.start) / range.duration)
            }
            func y(_ altitude: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(max(0, min(90, altitude)) / 90) }

            // Twilight bands, one rectangle per sample interval.
            for (a, b) in zip(plan.sunCurve, plan.sunCurve.dropFirst()) {
                let rect = CGRect(x: x(a.date), y: plot.minY, width: x(b.date) - x(a.date) + 0.5, height: plot.height)
                context.fill(Path(rect), with: .color(Self.band(a.altitude)))
            }
            if style == .full {
                for altitude in [0.0, 30, 60] {
                    var line = Path()
                    line.move(to: CGPoint(x: plot.minX, y: y(altitude)))
                    line.addLine(to: CGPoint(x: plot.maxX, y: y(altitude)))
                    context.stroke(line, with: .color(Theme.line), style: StrokeStyle(lineWidth: 1, dash: altitude == 0 ? [] : [6, 8]))
                    context.draw(Text(verbatim: "\(Int(altitude))°").font(.pgLabel).foregroundStyle(Theme.text3),
                                 at: CGPoint(x: plot.minX - 10, y: y(altitude)), anchor: .trailing)
                }
                var calendar = Calendar.current
                calendar.timeZone = .current
                let hourFormat = Format.hourWithoutDayPeriod()
                var hour = calendar.nextDate(after: range.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? range.start
                while hour < range.end {
                    if calendar.component(.hour, from: hour) % 2 == 0 {
                        context.draw(Text(verbatim: hourFormat.string(from: hour)).font(.pgLabel).foregroundStyle(Theme.text3),
                                     at: CGPoint(x: x(hour), y: plot.maxY + 18), anchor: .center)
                    }
                    hour = hour.addingTimeInterval(3600)
                }
                if let transit = plan.transit, range.contains(transit) {
                    var meridian = Path()
                    meridian.move(to: CGPoint(x: x(transit), y: plot.minY + 28))
                    meridian.addLine(to: CGPoint(x: x(transit), y: plot.maxY))
                    context.stroke(meridian, with: .color(Theme.text3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 6]))
                    context.draw(Text("Meridian \(transit.formatted(date: .omitted, time: .shortened))").font(.pgLabel).foregroundStyle(Theme.text3),
                                 at: CGPoint(x: x(transit) + 8, y: plot.minY + 14), anchor: .leading)
                }
                // Moon: dashed, only above the horizon.
                var moon = Path()
                var drawing = false
                for point in plan.moonCurve {
                    if point.altitude > 0 {
                        let p = CGPoint(x: x(point.date), y: y(point.altitude))
                        if drawing { moon.addLine(to: p) } else { moon.move(to: p); drawing = true }
                    } else { drawing = false }
                }
                context.stroke(moon, with: .color(Theme.text2), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            }
            if let curve = plan.targetCurve {
                var target = Path()
                for (i, point) in curve.enumerated() {
                    let p = CGPoint(x: x(point.date), y: y(point.altitude))
                    if i == 0 { target.move(to: p) } else { target.addLine(to: p) }
                }
                context.stroke(target, with: .color(Theme.accent), lineWidth: style == .full ? 5 : 3)
            }
            if range.contains(now) {
                var line = Path()
                line.move(to: CGPoint(x: x(now), y: plot.minY))
                line.addLine(to: CGPoint(x: x(now), y: plot.maxY))
                context.stroke(line, with: .color(Theme.focus), lineWidth: style == .full ? 2 : 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}
