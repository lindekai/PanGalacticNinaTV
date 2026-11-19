import PanGalacticCore
import SwiftUI

/// Guiding on the overview: state and RMS in a compact header, RA/Dec curves of
/// N.I.N.A.'s guide graph below. The total RMS is coloured by its grade.
struct GuidingChartPanel: View {
    let model: GuidingChartModel
    let guider: NINAEquipmentSummary.Guider?
    let graphFailed: Bool
    let light: StatusLight

    private var connected: Bool { guider?.device.connected == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            plot.frame(maxWidth: .infinity, minHeight: 56, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "target").resizable().scaledToFit().frame(width: 26, height: 26).foregroundStyle(Theme.text2)
            Text("Guiding").font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
                .lineLimit(1).fixedSize()
            StatusLED(light).padding(.leading, 6)
            // While guiding the green LED and the rubric say it; other states are spelled out.
            if !model.isGuiding {
                Text(verbatim: stateText).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 12)
            if connected {
                HStack(spacing: 6) {
                    Text("Total").foregroundStyle(Theme.text2)
                    Text(verbatim: model.total.map(Format.guideValue) ?? "—")
                        .foregroundStyle(model.total == nil ? Theme.text3 : Theme.color(for: model.grade))
                }
                .fixedSize()
                legend("RA", value: model.ra, color: Theme.guideRA)
                legend("Dec", value: model.dec, color: Theme.guideDec)
            }
        }
        .font(.pgLabel.monospacedDigit())
        .lineLimit(1)
        .frame(height: 30)
    }

    private var stateText: String {
        guard connected else { return String(localized: "Not connected") }
        return Format.guiderState(guider?.state) ?? "—"
    }

    private func legend(_ label: LocalizedStringKey, value: GuideValue?, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
            Text(verbatim: value.map(Format.guideValue) ?? "—")
        }
        .fixedSize()
        .foregroundStyle(Theme.text2)
        .padding(.leading, 14)
    }

    // MARK: Plot

    @ViewBuilder private var plot: some View {
        if !connected {
            Color.clear
        } else if graphFailed {
            placeholder("Guiding chart not available")
        } else if model.points.isEmpty {
            placeholder("No guide steps yet")
        } else {
            Canvas { context, size in draw(in: &context, size: size) }
        }
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.pgLabel).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let labelWidth: CGFloat = 44
        let width = size.width - labelWidth
        let mid = size.height / 2
        let half = size.height / 2 - 2
        let range = model.range
        func y(_ value: Double) -> CGFloat { mid - CGFloat(value / range) * half }
        func x(_ position: Double) -> CGFloat { CGFloat(position) * width }
        let unit = model.unit == .arcseconds ? "″" : " px"

        func horizontal(_ value: Double) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: y(value))); $0.addLine(to: CGPoint(x: width, y: y(value))) }
        }
        context.stroke(horizontal(0), with: .color(Theme.line), lineWidth: 1)
        for line in GuidingChartModel.gridlines where abs(line) <= range {
            context.stroke(horizontal(line), with: .color(Theme.line), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        for (value, label) in [(1.0, "+1" + unit), (0, "0"), (-1.0, "−1" + unit)] {
            context.draw(Text(verbatim: label).font(.system(size: 14)).foregroundStyle(Theme.text3),
                         at: CGPoint(x: size.width, y: y(value)), anchor: .trailing)
        }
        for position in model.ditherPositions {
            let path = Path { $0.move(to: CGPoint(x: x(position), y: 0)); $0.addLine(to: CGPoint(x: x(position), y: size.height)) }
            context.stroke(path, with: .color(Theme.text3), lineWidth: 1)
        }
        // Old curves after a stop are kept by N.I.N.A.; dim them so they are not read as live.
        for (keyPath, color) in [(\GuidingChartModel.Point.dec, Theme.guideDec), (\GuidingChartModel.Point.ra, Theme.guideRA)] {
            var path = Path()
            for (i, point) in model.points.enumerated() {
                let p = CGPoint(x: x(point.position), y: y(point[keyPath: keyPath]))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(model.isGuiding ? color : Theme.text3),
                           style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }
}
