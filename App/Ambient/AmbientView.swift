import PanGalacticCore
import PanGalacticServices
import SwiftUI
import UIKit

/// Full-screen newest frame with a slim glass strip (spec: "Ambient mode"). Shows the
/// thumbnail at once and the 1920 px render when it arrives – one render per new frame,
/// the same request the viewer makes. New frames cross-fade; the strip wanders against burn-in.
struct AmbientView: View {
    let connection: InstanceConnection
    let service: ImageRenderService?
    let exit: () -> Void

    @State private var rendered: (index: Int, image: UIImage)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .bottom) {
                Color.black
                frame
                strip(now: context.date)
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onExitCommand(perform: exit)
        .onPlayPauseCommand(perform: exit)
        .onMoveCommand { _ in exit() }
        .onTapGesture(perform: exit)
        .task(id: connection.latestImageIndex) { await load() }
    }

    @ViewBuilder private var frame: some View {
        let index = connection.latestImageIndex
        let shown = rendered.flatMap { $0.index == index ? $0.image : nil }
            ?? connection.latestThumbnail.flatMap(UIImage.init(data:))
        if let shown {
            Image(uiImage: shown)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(index)
                .transition(.opacity.animation(.easeInOut(duration: 0.6)))
        }
    }

    private func strip(now: Date) -> some View {
        let shift = AmbientPolicy.stripShift(at: now)
        let sequence = SequenceDisplay.state(connection.sequence, phase: connection.phase, now: now)
        var parts: [String] = []
        if let target = connection.latestImage?.targetName { parts.append(target) }
        if case .running = sequence { parts.append(Format.sequence(sequence)) }
        return HStack(spacing: 16) {
            StatusLED(light)
            Text(verbatim: (parts + [status(now: now)]).joined(separator: " · "))
                .font(.pgValue).foregroundStyle(Theme.text).lineLimit(1)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(Theme.raised.opacity(0.72), in: .capsule)
        .offset(x: shift.x, y: shift.y)
        .padding(.bottom, Theme.marginVertical)
        .animation(.easeInOut(duration: 2), value: shift.x)
    }

    private var light: StatusLight {
        switch connection.phase {
        case .live: .normal
        case .stale: .warning
        case .offline: .fault
        case .connecting: .unknown
        }
    }

    private func status(now: Date) -> String {
        let time = now.formatted(date: .omitted, time: .shortened)
        switch connection.phase {
        case .live: return String(localized: "LIVE · \(time)")
        case .stale:
            let since = connection.lastSuccess?.formatted(date: .omitted, time: .shortened) ?? "—"
            return String(localized: "Stale · as of \(since)")
        case .offline: return String(localized: "Offline")
        case .connecting: return String(localized: "Connecting…")
        }
    }

    private func load() async {
        guard let service, let index = connection.latestImageIndex, rendered?.index != index else { return }
        let request = ImageRenderService.Request(index: index)
        guard let data = try? await service.render(request) else { return }
        let maxPixel = request.size.map { max($0.width, $0.height) } ?? ImageViewer.maxFullPixel
        let image = await Task.detached(priority: .utility) { ImageViewer.downsample(data, maxPixel: maxPixel) }.value
        if let image, !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.6)) { rendered = (index, image) }
        }
    }
}
