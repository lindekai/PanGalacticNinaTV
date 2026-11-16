import ImageIO
import PanGalacticCore
import PanGalacticServices
import SwiftUI
import UIKit

/// Full-screen view of one history image, rendered by N.I.N.A. on request.
/// Shows the thumbnail immediately and swaps in the 1920 px render when it arrives.
/// A click zooms one step closer (fit, then 75 % … 400 %), Menu one step back, Play/Pause
/// back to fit. Swipes drag the picture, arrow clicks move a quarter screen. Every change
/// briefly shows the step and a map of the visible part. The full resolution is rendered
/// once, on the first zoom.
struct ImageViewer: View {
    let index: Int
    let image: NINAImageSaveStatistics?
    let thumbnail: Data?
    let service: ImageRenderService?

    /// Upper bound for decoding the full-resolution render (26 MP frames are 6248 px wide).
    nonisolated static let maxFullPixel = 8192

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var rendered: UIImage?
    @State private var full: UIImage?
    @State private var failure: String?
    @State private var fullFailure: String?
    @State private var started = Date()
    @State private var fullStarted: Date?
    @State private var zoom = ImageZoom()
    @State private var screenPoints = CGSize(width: 1920, height: 1080)
    /// Bumped on every zoom or pan; the indicator hides two seconds after the last bump.
    @State private var indicatorToken = 0
    @State private var indicatorVisible = false
    /// Swipes can also arrive as move commands; those are ignored right after a drag.
    @State private var lastDrag = Date.distantPast
    #if DEBUG
    @State private var debugSteps = 0
    #endif

    var body: some View {
        // The whole cover ignores the safe area so the frame is centred on the screen,
        // not on the asymmetric safe-area rectangle; the caption uses the grid margins.
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black
                picture(screen: geo.size)
                caption
            }
            .overlay(alignment: .top) { indicator }
            .onAppear { screenPoints = geo.size }
            .onChange(of: geo.size) { screenPoints = geo.size }
        }
        .ignoresSafeArea()
        .background { RemotePanSurface(isEnabled: zoom.needsFullResolution && full != nil, onPan: drag) }
        .focusable()
        .onTapGesture { change { _ = $0.zoomIn(image: fullPixels, screen: screenPixels) } }
        .onMoveCommand { direction in pan(direction) }
        .onPlayPauseCommand { change { $0.reset() } }
        .onExitCommand {
            if zoom.isFitted { dismiss() } else { change { _ = $0.zoomOut(image: fullPixels, screen: screenPixels) } }
        }
        .task(id: index) { await load() }
        #if DEBUG
        // Simulator gate tests have no remote: `-debug.zoom N` clicks N times, the
        // steps beyond the first once the full resolution has arrived.
        .onAppear {
            debugSteps = UserDefaults.standard.integer(forKey: "debug.zoom")
            if debugSteps > 0 { debugSteps -= 1; zoom.zoomIn(image: nil, screen: screenPixels) }
        }
        .onChange(of: full != nil) {
            for _ in 0..<debugSteps { zoom.zoomIn(image: fullPixels, screen: screenPixels) }
            debugSteps = 0
            showIndicator()
        }
        #endif
        .task(id: zoom.needsFullResolution) { if zoom.needsFullResolution { await loadFull() } }
        .task(id: indicatorToken) {
            guard indicatorToken > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.4)) { indicatorVisible = false } }
        }
    }

    private var fullPixels: CGSize? {
        full.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
    }

    private var screenPixels: CGSize {
        CGSize(width: screenPoints.width * displayScale, height: screenPoints.height * displayScale)
    }

    @ViewBuilder private func picture(screen: CGSize) -> some View {
        if zoom.needsFullResolution, let full, let pixels = fullPixels {
            // Points per image pixel = (screen pixels per image pixel) / screen scale.
            let scale = zoom.scale(image: pixels, screen: screenPixels)
            let points = scale / displayScale
            let width = pixels.width * points, height = pixels.height * points
            Image(uiImage: full)
                .resizable()
                // From 1:1 on, show the sensor's pixels as squares instead of blurring stars.
                .interpolation(scale >= 1 ? .none : .high)
                .frame(width: width, height: height)
                .offset(x: (0.5 - zoom.centerX) * width, y: (0.5 - zoom.centerY) * height)
                .frame(width: screen.width, height: screen.height)
                .clipped()
        } else if let base = overviewImage {
            Image(uiImage: base)
                .resizable()
                .scaledToFit()
                .frame(width: screen.width, height: screen.height)
        }
    }

    private var overviewImage: UIImage? {
        rendered ?? full ?? thumbnail.flatMap(UIImage.init(data:))
    }

    /// Step name with one dot per step, plus a map of the visible part while zoomed.
    @ViewBuilder private var indicator: some View {
        if indicatorVisible {
            let count = fullPixels.map { ImageZoom.stepCount(image: $0, screen: screenPixels) } ?? 2
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    Text(stepLabel).font(.pgValue).monospacedDigit()
                    HStack(spacing: 10) {
                        ForEach(0..<count, id: \.self) { step in
                            Circle()
                                .fill(step == min(zoom.step, count - 1) ? Theme.text : Theme.text3)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 18)
                .background(.ultraThinMaterial.opacity(0.8), in: .rect(cornerRadius: 20))
                if zoom.needsFullResolution, let pixels = fullPixels, let map = overviewImage {
                    ZoomMap(image: map, visible: zoom.visibleRect(image: pixels, screen: screenPixels))
                }
            }
            .padding(.top, Theme.marginVertical)
            .transition(.opacity)
        }
    }

    private var stepLabel: String {
        guard zoom.needsFullResolution, let pixels = fullPixels else {
            return zoom.isFitted ? String(localized: "Whole frame") : String(localized: "Zooming…")
        }
        let scale = zoom.scale(image: pixels, screen: screenPixels)
        let percent = (scale * 100).formatted(.number.precision(.fractionLength(0)))
        return scale == 1 ? String(localized: "\(percent) % · 1:1") : "\(percent) %"
    }

    private var caption: some View {
        HStack(alignment: .bottom) {
            if let image {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: image.targetName ?? "—").font(.title3.bold())
                    Text(verbatim: [image.filter, image.exposureTime.map(Format.seconds), image.imageType]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                }
            }
            Spacer()
            status
        }
        .padding(28)
        .background(.ultraThinMaterial.opacity(0.6), in: .rect(cornerRadius: 20))
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, Theme.marginVertical)
    }

    /// Zoomed, only the full-resolution render matters; the 1920 px render it may have
    /// superseded (one request at a time) is not reported as a failure.
    @ViewBuilder private var status: some View {
        if zoom.needsFullResolution {
            if let fullFailure {
                Label("Full resolution unavailable: \(String(localized: String.LocalizationValue(fullFailure)))",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if full == nil, let fullStarted {
                progress(since: fullStarted, Text("N.I.N.A. is rendering the full resolution…"))
            } else {
                Text(zoomLabel).font(.callout).foregroundStyle(.secondary)
            }
        } else if let failure, full == nil {
            Label("Full image unavailable: \(String(localized: String.LocalizationValue(failure)))",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if rendered == nil, full == nil {
            progress(since: started, Text("N.I.N.A. is rendering the full image…"))
        } else {
            Text(zoomLabel).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var zoomLabel: LocalizedStringKey {
        zoom.isFitted ? "Click to zoom" : "Click: closer · Menu: wider · Play/Pause: whole frame"
    }

    private func progress(since start: Date, _ title: Text) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            HStack(spacing: 16) {
                ProgressView()
                title.font(.callout)
                Text(verbatim: "\(Int(context.date.timeIntervalSince(start))) s").font(.callout).monospacedDigit()
            }
        }
    }

    private func change(_ update: (inout ImageZoom) -> Void) {
        withAnimation(.easeInOut(duration: 0.25)) { update(&zoom) }
        showIndicator()
    }

    private func showIndicator() {
        withAnimation(.easeIn(duration: 0.15)) { indicatorVisible = true }
        indicatorToken += 1
    }

    /// The picture follows the finger: a swipe to the right reveals what lies to the left.
    private func drag(_ translation: CGSize) {
        guard let pixels = fullPixels else { return }
        lastDrag = Date()
        let delta = CGSize(width: -translation.width * displayScale, height: -translation.height * displayScale)
        zoom.drag(by: delta, image: pixels, screen: screenPixels)
        showIndicator()
    }

    private func pan(_ direction: MoveCommandDirection) {
        guard let pixels = fullPixels, Date().timeIntervalSince(lastDrag) > 0.4 else { return }
        let mapped: ImageZoom.Direction
        switch direction {
        case .left: mapped = .left
        case .right: mapped = .right
        case .up: mapped = .up
        case .down: mapped = .down
        @unknown default: return
        }
        change { $0.pan(mapped, image: pixels, screen: screenPixels) }
    }

    private func load() async {
        guard let service else { return }
        started = Date()
        failure = nil
        // 1920×1080 also on 4K screens: the render on the telescope PC is the bottleneck.
        let request = ImageRenderService.Request(index: index)
        do {
            let data = try await service.render(request)
            let maxPixel = request.size.map { max($0.width, $0.height) } ?? Self.maxFullPixel
            rendered = await Task.detached(priority: .userInitiated) { Self.downsample(data, maxPixel: maxPixel) }.value
            if rendered == nil { failure = "Unexpected response format" }
        } catch {
            if !Task.isCancelled { failure = Self.describe(error) }
        }
    }

    /// One full-resolution render per opened image; never polled (capability matrix §7).
    private func loadFull() async {
        guard let service, full == nil else { return }
        fullStarted = Date()
        fullFailure = nil
        let request = ImageRenderService.Request(index: index, size: nil, quality: 90)
        do {
            let data = try await service.render(request)
            full = await Task.detached(priority: .userInitiated) { Self.downsample(data, maxPixel: Self.maxFullPixel) }.value
            if full == nil { fullFailure = "Unexpected response format" }
        } catch {
            if !Task.isCancelled { fullFailure = Self.describe(error) }
        }
    }

    private static func describe(_ error: NINAClientError) -> String {
        switch error {
        case .transport(let message): message
        case .httpStatus(let code): "HTTP \(code)"
        case .responseTooLarge: "Response too large"
        case .decoding: "Unexpected response format"
        case .api(.server(_, let message)): message.isEmpty ? "Server error" : message
        case .api, .request: "Server error"
        }
    }

    /// Decodes at most `maxPixel` on the long side so a large JPEG never sits in memory at full size.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// The whole frame, small, with the visible part outlined.
private struct ZoomMap: View {
    let image: UIImage
    let visible: CGRect

    var body: some View {
        let width: CGFloat = 280
        let height = width * image.size.height / max(image.size.width, 1)
        Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Theme.text, lineWidth: 3)
                    .frame(width: max(visible.width * width, 6), height: max(visible.height * height, 6))
                    .offset(x: visible.minX * width, y: visible.minY * height)
            }
            .clipShape(.rect(cornerRadius: 8))
            .padding(10)
            .background(.ultraThinMaterial.opacity(0.8), in: .rect(cornerRadius: 16))
    }
}
