import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// "The Night" (spec M4.1): darkness, the target's altitude, Sun, Moon and compass,
/// computed on the device. Display only; Menu returns.
struct NightView: View {
    @Environment(AppModel.self) private var app
    let model: NightModel
    let connection: InstanceConnection

    var body: some View {
        // The overview's timeline may pause while this page covers it; keep the now line moving here.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            page(date: context.date)
                .onChange(of: context.date) { update(at: context.date) }
        }
        .onAppear { update(at: .now) }
    }

    private func update(at date: Date) {
        model.update(connection: connection, cached: app.siteStore.site(for: connection.instance.id), at: date)
    }

    private func page(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("Night").font(.pgDisplay).foregroundStyle(Theme.text)
                Text(verbatim: "\(connection.instance.displayName) · \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer()
                siteLabel.font(.pgLabel).foregroundStyle(Theme.text3).lineLimit(1)
            }
            if let plan = model.plan, let now = model.now {
                HStack(alignment: .top, spacing: Theme.columnGap) {
                    altitudePanel(plan: plan, now: now, date: date).frame(width: 1120)
                    VStack(spacing: Theme.moduleGap) {
                        compassPanel(now: now)
                        sunPanel(plan: plan)
                        moonPanel(plan: plan, now: now)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer()
                Text("Site unknown – connect the mount once").font(.pgValue).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, Theme.marginVertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .ignoresSafeArea()
        // A display-only page still needs one focusable element so Menu returns reliably.
        .focusable()
    }

    @ViewBuilder private var siteLabel: some View {
        switch model.siteSource {
        case .mount: Text("Site from the mount")
        case .cached(let reported): Text("Site last reported on \(reported.formatted(date: .abbreviated, time: .omitted))")
        case nil: EmptyView()
        }
    }

    private func time(_ date: Date?) -> String? { date?.formatted(date: .omitted, time: .shortened) }

    // MARK: Altitude

    private func altitudePanel(plan: NightPlan, now: NightNow, date: Date) -> some View {
        NightPanel("Altitude above horizon", fillHeight: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let target = plan.target {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(verbatim: target.name ?? "—").font(.pgTileValue)
                                    .foregroundStyle(target.name == nil ? Theme.text3 : Theme.text)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .opacity(model.targetIsStale ? 0.55 : 1)
                                Text(target.source == .sequence ? "from the sequence" : "from the mount")
                                    .font(.pgLabel).foregroundStyle(Theme.text3).lineLimit(1)
                            }
                            if target.source == .sequence {
                                HStack(spacing: 8) {
                                    Text("RA")
                                    Text(verbatim: Format.rightAscension(target.coordinates.ra)).monospacedDigit()
                                    Text(verbatim: "·")
                                    Text("Dec")
                                    Text(verbatim: Format.declination(target.coordinates.dec)).monospacedDigit()
                                    Text(verbatim: "· J2000")
                                }
                                .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
                            }
                        } else {
                            Text("No target").font(.pgTileValue).foregroundStyle(Theme.text3)
                        }
                    }
                    Spacer(minLength: 24)
                    KeyFigure(now.target.map { Format.degrees($0.altitude) }, unit: "°", label: "now")
                        .opacity(model.targetIsStale ? 0.55 : 1)
                }
                AltitudeChart(plan: plan, now: date, style: .full)
                    .frame(minHeight: 520, maxHeight: .infinity)
                    .overlay {
                        if plan.targetVisibility == .neverRises {
                            Text("Not above the horizon tonight").font(.pgValue).foregroundStyle(Theme.text2)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Theme.surface.opacity(0.85), in: .rect(cornerRadius: Theme.radius))
                        }
                    }
                legend(plan: plan)
            }
        }
    }

    private func legend(plan: NightPlan) -> some View {
        HStack(spacing: 32) {
            if let target = plan.target {
                HStack(spacing: 10) {
                    Capsule().fill(Theme.accent).frame(width: 32, height: 5)
                    if let name = target.name { Text(verbatim: name) } else { Text(verbatim: "—") }
                }
            }
            HStack(spacing: 10) {
                DashedLine().stroke(Theme.text2, style: StrokeStyle(lineWidth: 3, dash: [8, 6])).frame(width: 32, height: 3)
                Text("Moon")
            }
            HStack(spacing: 10) {
                Rectangle().fill(Theme.focus).frame(width: 2, height: 22)
                Text("now")
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(AltitudeChart.band(-20)).frame(width: 32, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
                Text("Darkness")
            }
        }
        .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
    }

    // MARK: Compass

    private func compassPanel(now: NightNow) -> some View {
        NightPanel("Compass") {
            HStack(alignment: .center, spacing: 28) {
                CompassView(now: now, telescope: model.telescope).frame(width: 260, height: 260)
                VStack(alignment: .leading, spacing: 10) {
                    if let telescope = model.telescope {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(CompassView.point(telescope.azimuth))
                            Text(verbatim: "\(Int(telescope.azimuth.rounded()) % 360)°")
                        }
                        .font(.pgTileValue).foregroundStyle(Theme.text).lineLimit(1)
                        HStack(spacing: 8) {
                            Text("Telescope")
                            Text(verbatim: "·")
                            Text("Altitude \(Int(telescope.altitude.rounded()))°")
                        }
                        .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
                    } else {
                        Text(verbatim: "—").font(.pgTileValue).foregroundStyle(Theme.text3)
                        Text("Telescope").font(.pgLabel).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 18) {
                            legendMark(Circle().fill(Theme.accent), "Telescope")
                            legendMark(Circle().stroke(Theme.text2, lineWidth: 3), "Moon")
                            legendMark(Circle().stroke(Theme.warn, lineWidth: 3), "Sun")
                        }
                        Text("dashed = below the horizon").foregroundStyle(Theme.text3)
                    }
                    .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 260)
        }
    }

    private func legendMark(_ shape: some View, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            shape.frame(width: 16, height: 16)
            Text(label)
        }
    }

    // MARK: Sun

    private func sunPanel(plan: NightPlan) -> some View {
        NightPanel("Sun") {
            VStack(alignment: .leading, spacing: 14) {
                switch plan.darkness {
                case .astronomical(let from, let until):
                    darkValues(fromLabel: "Astronomical dark from", from: from, until: until)
                case .nautical(let from, let until):
                    darkValues(fromLabel: "Nautical dark from", from: from, until: until)
                    Text("No astronomical darkness").font(.pgLabel).foregroundStyle(Theme.text2)
                case .none:
                    Text("No astronomical darkness").font(.pgValue).foregroundStyle(Theme.text2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sunset \(time(plan.events.sunset) ?? "—") · Sunrise \(time(plan.events.sunrise) ?? "—")")
                    if plan.events.sunAlwaysUp { Text("Sun does not set") }
                    if plan.events.sunAlwaysDown { Text("Sun does not rise") }
                }
                .font(.pgLabel).foregroundStyle(Theme.text3).lineLimit(1)
            }
        }
    }

    private func darkValues(fromLabel: LocalizedStringKey, from: Date, until: Date) -> some View {
        let minutes = Int((until.timeIntervalSince(from) / 60).rounded())
        return HStack(alignment: .top, spacing: 24) {
            ValueColumn(time(from), label: fromLabel)
            Spacer(minLength: 0)
            ValueColumn(time(until), label: "until")
            Spacer(minLength: 0)
            ValueColumn(String(format: "%d h %02d", minutes / 60, minutes % 60), label: "Darkness")
        }
    }

    // MARK: Moon

    private func moonPanel(plan: NightPlan, now: NightNow) -> some View {
        let waxingRight = now.moonWaxing == (plan.site.latitude >= 0)
        let next = now.nextMoonEvent
        return NightPanel("Moon", fillHeight: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    MoonPhaseView(illuminated: now.moonIlluminated, litOnRight: waxingRight)
                        .frame(width: 60, height: 60)
                    ValueColumn("\(Int((now.moonIlluminated * 100).rounded())) %",
                                label: now.moonWaxing ? "illuminated, waxing" : "illuminated, waning")
                    Spacer(minLength: 0)
                    ValueColumn(time(next?.date), label: next?.rising == true ? "Moonrise" : "Moonset")
                    Spacer(minLength: 0)
                    ValueColumn(now.moonSeparation.map { "\(Int($0.rounded()))°" }, label: "Separation")
                }
                Text("Moonrise \(time(plan.events.moonrise) ?? "—") · Moonset \(time(plan.events.moonset) ?? "—") · Full moon \(now.nextFullMoon.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.pgLabel).foregroundStyle(Theme.text3).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: Pieces

/// The module surface of the overview without icon and LED: rubric, hairline, content.
private struct NightPanel<Content: View>: View {
    let title: LocalizedStringKey
    let fillHeight: Bool
    let content: Content

    init(_ title: LocalizedStringKey, fillHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.fillHeight = fillHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
                .lineLimit(1)
                .frame(height: 44, alignment: .leading)
            Rectangle().fill(Theme.line).frame(height: 1)
            content.padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
    }
}

/// A value over its label; `nil` renders as a dash in `text3`.
private struct ValueColumn: View {
    let value: String?
    let label: LocalizedStringKey

    init(_ value: String?, label: LocalizedStringKey) {
        self.value = value
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value ?? "—").font(.pgValue).foregroundStyle(value == nil ? Theme.text3 : Theme.text)
            Text(label).font(.pgLabel).foregroundStyle(Theme.text2)
        }
        .lineLimit(1)
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The Moon's phase: dark disc, the lit part bounded by the limb and the terminator
/// (an ellipse whose half-width follows the illuminated fraction).
private struct MoonPhaseView: View {
    let illuminated: Double
    let litOnRight: Bool

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.line))
            let side: CGFloat = litOnRight ? 1 : -1
            let e = r * CGFloat(2 * max(0, min(1, illuminated)) - 1)
            var lit = Path()
            let steps = 48
            for i in 0 ... steps {
                // Limb on the lit side, top to bottom.
                let t = Double.pi * Double(i) / Double(steps)
                let p = CGPoint(x: c.x + side * r * CGFloat(sin(t)), y: c.y - r * CGFloat(cos(t)))
                if i == 0 { lit.move(to: p) } else { lit.addLine(to: p) }
            }
            for i in 0 ... steps {
                // Terminator, bottom to top.
                let t = Double.pi * Double(steps - i) / Double(steps)
                lit.addLine(to: CGPoint(x: c.x - side * e * CGFloat(sin(t)), y: c.y - r * CGFloat(cos(t))))
            }
            lit.closeSubpath()
            context.fill(lit, with: .color(Theme.text))
        }
        .accessibilityHidden(true)
    }
}
