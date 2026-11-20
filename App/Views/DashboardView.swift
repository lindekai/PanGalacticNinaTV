import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Overview of one N.I.N.A. instance (spec: "Overview details"). Answers at a glance:
/// is everything running, how good is the newest frame, how is the camera set, where
/// is the object. Unknown values are "—"; data that is not live is labelled with its age.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AmbientController.self) private var ambient
    let connection: InstanceConnection
    @State private var viewerItem: ViewerItem?
    @State private var visible = false
    @FocusState private var imageFocused: Bool
    @State private var focusedFirstImage = false
    #if DEBUG
    @State private var debugOpenSequence = false
    @State private var debugOpenNight = false
    #endif

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 24) {
                header(now: context.date)
                if let version = connection.incompatibility {
                    Label("Advanced API \(version) is not supported yet (supported: 2.x). Monitoring stopped.",
                          systemImage: "xmark.octagon.fill")
                        .font(.pgValue).foregroundStyle(Theme.fault)
                    Spacer()
                } else {
                    if connection.phase == .offline { offlineBanner(now: context.date) }
                    overview(now: context.date)
                    NavigationLink(value: Destination.sequence) {
                        SequenceStrip(steps: connection.sequenceTree.map(SequenceSteps.init(tree:)),
                                      dimmed: asOf != nil)
                    }
                    .buttonStyle(LiftButtonStyle(scale: 1.01))
                    // Full width like the header: a swipe down from the image reaches the strip,
                    // a swipe up returns to the image.
                    .focusSection()
                    .accessibilityLabel(Text("Sequence"))
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.marginVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .ignoresSafeArea()
            .defaultFocus($imageFocused, true)
            .onChange(of: context.date) {
                connection.refreshPhase()
                updateNight(at: context.date)
                evaluateAmbient(now: context.date)
            }
            .fullScreenCover(isPresented: Binding(get: { ambient.isShowing }, set: { if !$0 { ambient.registerInput() } })) {
                AmbientView(connection: connection, service: model.renderService) { ambient.registerInput() }
            }
        }
        // The image card is disabled until the first frame is known, so focus starts in the
        // header; move it to the image once, when the frame arrives.
        .onChange(of: connection.latestImage == nil, initial: true) { _, noImage in
            guard !noImage, !focusedFirstImage else { return }
            focusedFirstImage = true
            imageFocused = true
        }
        .onAppear {
            visible = true
            ambient.overviewVisible(true)
            updateNight(at: .now)
        }
        .onDisappear {
            visible = false
            ambient.overviewVisible(false)
        }
        #if DEBUG
        // Simulator gate tests have no remote: `-debug.openViewer YES` opens the viewer once an image is known.
        .onChange(of: connection.latestImageIndex) { _, index in
            if let index, UserDefaults.standard.bool(forKey: "debug.openViewer"), viewerItem == nil {
                viewerItem = ViewerItem(index: index)
            }
        }
        // `-debug.openSequence YES` opens the sequence page once the tree is known.
        .onChange(of: connection.sequenceTree != nil) { _, known in
            if known, UserDefaults.standard.bool(forKey: "debug.openSequence") { debugOpenSequence = true }
        }
        .navigationDestination(isPresented: $debugOpenSequence) { SequenceView(connection: connection) }
        // `-debug.openNight YES` opens the night page once a plan is known.
        .onChange(of: model.night?.plan != nil) { _, known in
            if known, UserDefaults.standard.bool(forKey: "debug.openNight") { debugOpenNight = true }
        }
        .navigationDestination(isPresented: $debugOpenNight) {
            if let night = model.night { NightView(model: night, connection: connection) }
        }
        #endif
        .fullScreenCover(item: $viewerItem) { item in
            ImageViewer(index: item.index, image: connection.latestImage, thumbnail: connection.latestThumbnail,
                        service: model.renderService)
        }
    }

    private func updateNight(at date: Date) {
        model.night?.update(connection: connection, cached: model.siteStore.site(for: connection.instance.id), at: date)
    }

    /// Only the overview itself gives way to the ambient view: not the image viewer, not Settings.
    private func evaluateAmbient(now: Date) {
        let exposure = ExposureDisplay.state(camera: connection.equipment?.camera, phase: connection.phase, now: now)
        ambient.evaluate(now: now, alarm: AmbientPolicy.isAlarm(phase: connection.phase, exposure: exposure),
                         eligible: visible && viewerItem == nil)
    }

    private var asOf: Date? {
        connection.phase == .live ? nil : connection.lastSuccess
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: connection.instance.displayName).font(.pgDisplay).foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let plugin = connection.pluginVersion {
                    Text("N.I.N.A. \(connection.ninaVersion ?? "?") · Advanced API \(plugin)")
                        .font(.pgLabel).foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: 24)
            sequencePill(now: now)
            exposurePill(now: now)
            livePill(now: now)
            if model.store.instances.count > 1 {
                Button { model.deactivate() } label: { Image(systemName: "rectangle.2.swap") }
                    .buttonStyle(GearButtonStyle())
                    .accessibilityLabel(Text("Switch Observatory"))
            }
            NavigationLink(value: Destination.night) { Image(systemName: "moon.stars") }
                .buttonStyle(GearButtonStyle())
                .accessibilityLabel(Text("Night"))
            NavigationLink(value: Destination.devices) { Image(systemName: "cable.connector") }
                .buttonStyle(GearButtonStyle())
                .accessibilityLabel(Text("Devices"))
            NavigationLink(value: Destination.settings) { Image(systemName: "gearshape") }
                .buttonStyle(GearButtonStyle())
                .accessibilityLabel(Text("Settings"))
        }
        // The gear sits far right, the image far left: as full-width focus sections,
        // a swipe down from the gear reaches the image and a swipe up returns.
        .focusSection()
    }

    private func sequencePill(now: Date) -> some View {
        StatusPill("Sequence", value: Format.sequence(SequenceDisplay.state(connection.sequence, phase: connection.phase, now: now)))
    }

    /// Widest usual countdown, so the pill keeps its width while the exposure ticks down.
    private static var exposureReserve: String { String(localized: "\(Format.countdown(5999)) left") }

    private func exposurePill(now: Date) -> some View {
        switch ExposureDisplay.state(camera: connection.equipment?.camera, phase: connection.phase, now: now) {
        case .overdue:
            return StatusPill("Exposure", value: String(localized: "Overdue"), light: .warning, reserve: Self.exposureReserve)
        case .running(let left):
            return StatusPill("Exposure", value: String(localized: "\(Format.countdown(left)) left"), reserve: Self.exposureReserve)
        case .idle, .unknown:
            return StatusPill("Exposure", value: "—", reserve: Self.exposureReserve)
        }
    }

    private func livePill(now: Date) -> some View {
        let time = now.formatted(date: .omitted, time: .shortened)
        switch connection.phase {
        case .live:
            return StatusPill(nil, value: String(localized: "LIVE · \(time)"), light: .normal)
        case .stale:
            let since = connection.lastSuccess?.formatted(date: .omitted, time: .shortened) ?? "—"
            return StatusPill(nil, value: String(localized: "Stale · as of \(since)"), light: .warning)
        case .offline:
            return StatusPill(nil, value: String(localized: "Offline"), light: .fault)
        case .connecting:
            return StatusPill(nil, value: String(localized: "Connecting…"), light: .unknown)
        }
    }

    /// Factual banner below the header – never a modal.
    private func offlineBanner(now: Date) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.fault)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: offlineTitle(now: now)).font(.pgValue).foregroundStyle(Theme.text).lineLimit(1)
                if let error = offlineCause {
                    Text(verbatim: error).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(2)
                }
            }
            Spacer()
            Button("Retry Now", systemImage: "arrow.clockwise") { connection.retryNow() }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.fault.opacity(0.16), in: .rect(cornerRadius: Theme.radius))
    }

    private func offlineTitle(now: Date) -> String {
        guard let next = connection.nextAttempt else { return String(localized: "N.I.N.A. not reachable") }
        let seconds = max(0, Int(next.timeIntervalSince(now).rounded(.up)))
        return String(localized: "N.I.N.A. not reachable · retry in \(seconds) s")
    }

    /// Service messages are stable English sentences used as catalog keys.
    private var offlineCause: String? {
        connection.lastError.map { String(localized: String.LocalizationValue($0)) }
    }

    // MARK: Body

    private func overview(now: Date) -> some View {
        let equipment = connection.equipment
        let phase = connection.phase
        return HStack(alignment: .top, spacing: Theme.columnGap) {
            LatestImageCard(image: connection.latestImage, thumbnail: connection.latestThumbnail,
                            hfrSeries: connection.recentHFR,
                            asOf: asOf, now: now) {
                if let index = connection.latestImageIndex { viewerItem = ViewerItem(index: index) }
            }
            .frame(width: Theme.imageWidth)
            .focused($imageFocused)

            VStack(spacing: Theme.moduleGap) {
                CameraModule(camera: equipment?.camera, light: StatusLight.camera(equipment?.camera, phase: phase, now: now))
                NavigationLink(value: Destination.night) { ObjectModule(night: model.night) }
                    .buttonStyle(LiftButtonStyle(scale: 1.01))
                    .accessibilityLabel(Text("Night"))
                HStack(alignment: .top, spacing: Theme.moduleGap) {
                    MountTile(mount: equipment?.mount, light: StatusLight.device(equipment?.mount?.device, phase: phase))
                        .frame(maxWidth: .infinity).frame(maxHeight: .infinity, alignment: .top)
                    MeridianTile(flip: MeridianFlipDisplay(mount: equipment?.mount, now: now))
                        .frame(width: Theme.meridianTileWidth).frame(maxHeight: .infinity, alignment: .top)
                    FilterTile(wheel: equipment?.filterWheel, light: StatusLight.device(equipment?.filterWheel?.device, phase: phase))
                        .frame(width: Theme.filterTileWidth).frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
                GuidingChartPanel(model: GuidingChartModel(guider: equipment?.guider, graph: connection.guiderGraph),
                                  guider: equipment?.guider, graphFailed: connection.guiderGraphFailed,
                                  light: StatusLight.guider(equipment?.guider, phase: phase))
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(asOf != nil && equipment != nil ? 0.55 : 1)
        }
        // Both columns as tall as the taller one, so the guiding chart reaches the image's bottom edge.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }
}

private struct ViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: Modules

struct CameraModule: View {
    let camera: NINAEquipmentSummary.Camera?
    let light: StatusLight

    var body: some View {
        ModulePanel("Camera", icon: Image(systemName: "camera"), light: light) {
            let on = camera?.device.connected == true
            HStack(alignment: .bottom) {
                KeyFigure(on ? camera?.gain.map(String.init) : nil, label: "Gain")
                Spacer(minLength: 24)
                SideValues([
                    ("Sensor", on ? camera?.temperature.map(Format.celsius) : nil),
                    // Setpoint only while the cooler runs (#5: driver value, not the panel value).
                    ("Setpoint", on ? camera?.activeSetpoint.map(Format.celsius) : nil),
                    ("Cooler", on ? coolerText : nil),
                ])
            }
        }
    }

    private var coolerText: String? {
        guard let camera, let coolerOn = camera.coolerOn else { return nil }
        guard coolerOn else { return String(localized: "Off") }
        return camera.coolerPower.map(Format.percent) ?? String(localized: "On")
    }
}

struct ObjectModule: View {
    let night: NightModel?

    var body: some View {
        ModulePanel("Object", icon: Image(systemName: "scope"), light: nil, accessory: night?.plan?.target?.name) {
            HStack(alignment: .bottom, spacing: 24) {
                if night?.plan == nil {
                    KeyFigure(nil, unit: "°", label: "Site unknown")
                } else {
                    KeyFigure(night?.now?.target.map { Format.degrees($0.altitude) }, unit: "°", label: "Altitude above horizon")
                        .opacity(night?.targetIsStale == true ? 0.55 : 1)
                }
                Spacer(minLength: 0)
                // Nothing to draw while the target stays below the horizon over the chart.
                if let plan = night?.plan, plan.targetRisesInChart {
                    AltitudeChart(plan: plan, now: Date(), style: .mini)
                        .frame(width: 300, height: 90)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
        }
    }
}

struct MountTile: View {
    let mount: NINAEquipmentSummary.Mount?
    let light: StatusLight

    var body: some View {
        // No SF Symbol for an equatorial mount exists on tvOS 26; custom template vector.
        ModulePanel("Mount", icon: Image("TelescopeMount"), light: light, fillHeight: true) {
            TileValue(mount.flatMap { Format.mountActivity($0.activity) }, detail: pierText)
        }
    }

    private var pierText: String? {
        switch mount?.sideOfPier {
        case .east: String(localized: "Pier side east")
        case .west: String(localized: "Pier side west")
        case nil: nil
        }
    }
}

struct MeridianTile: View {
    let flip: MeridianFlipDisplay?

    var body: some View {
        ModulePanel("Meridian", icon: Image(systemName: "globe"), light: nil, fillHeight: true) {
            if let flip {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: Format.flipRemaining(flip.wholeMinutes)).font(.pgTileValue).foregroundStyle(Theme.text)
                        Text(verbatim: "h").font(.system(size: 28)).foregroundStyle(Theme.text2)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("until flip").font(.pgLabel).foregroundStyle(Theme.text2).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        // Approximate: N.I.N.A.'s countdown added to the TV's clock.
                        Text(verbatim: "≈ " + Format.clockWithoutDayPeriod(flip.flipAt))
                            .font(.system(size: 18)).foregroundStyle(Theme.text3).fixedSize()
                    }
                    .lineLimit(1)
                }
            } else {
                TileValue(nil, detail: nil)
            }
        }
    }
}

struct FilterTile: View {
    let wheel: NINAEquipmentSummary.FilterWheel?
    let light: StatusLight

    var body: some View {
        ModulePanel("Filter", icon: Image("FilterWheel"), light: light, fillHeight: true) {
            TileValue(wheel?.device.connected == true ? wheel?.selectedFilter : nil, detail: nil)
        }
    }
}
