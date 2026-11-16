import ImageIO
import PanGalacticCore
import PanGalacticServices
import SwiftUI
import UIKit

/// Full-screen view of one history image, rendered by N.I.N.A. on request.
/// Shows the thumbnail immediately and swaps in the 1920 px render when it arrives.
/// A click zooms (fit → closer → 1:1), a swipe pans, Menu steps back out. The full
/// resolution is rendered once, on the first zoom.
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

    var body: some View {
        // The whole cover ignores the safe area so the frame is centred on the screen,
        // not on the asymmetric safe-area rectangle; the caption uses the grid margins.
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black
                picture(screen: geo.size)
                caption
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onTapGesture { change { $0.cycle() } }
        .onMoveCommand { direction in pan(direction) }
        .onExitCommand {
            if zoom.level == .fit { dismiss() } else { change { $0.reset() } }
        }
        .task(id: index) { await load() }
        #if DEBUG
        // Simulator gate tests have no remote: `-debug.zoom N` clicks N times on open.
        .onAppear {
            for _ in 0..<UserDefaults.standard.integer(forKey: "debug.zoom") { zoom.cycle() }
        }
        #endif
        .task(id: zoom.needsFullResolution) { if zoom.needsFullResolution { await loadFull() } }
    }

    @ViewBuilder private func picture(screen: CGSize) -> some View {
        let base = rendered ?? full ?? thumbnail.flatMap(UIImage.init(data:))
        if zoom.level != .fit, let full {
            // Points per image pixel = (screen pixels per image pixel) / screen scale.
            let pixels = CGSize(width: full.size.width * full.scale, height: full.size.height * full.scale)
            let screenPixels = CGSize(width: screen.width * displayScale, height: screen.height * displayScale)
            let points = zoom.scale(image: pixels, screen: screenPixels) / displayScale
            let width = pixels.width * points, height = pixels.height * points
            Image(uiImage: full)
                .resizable()
                .interpolation(zoom.level == .full ? .none : .high)
                .frame(width: width, height: height)
                .offset(x: (0.5 - zoom.centerX) * width, y: (0.5 - zoom.centerY) * height)
                .frame(width: screen.width, height: screen.height)
                .clipped()
                .animation(.easeInOut(duration: 0.25), value: zoom)
                .onAppear { screenPoints = screen }
        } else if let base {
            Image(uiImage: base)
                .resizable()
                .scaledToFit()
                .frame(width: screen.width, height: screen.height)
                .onAppear { screenPoints = screen }
        }
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
        switch zoom.level {
        case .fit: "Click to zoom"
        case .closer: "Zoomed · swipe to move · Menu: back"
        case .full: "1:1 · swipe to move · Menu: back"
        }
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
    }

    private func pan(_ direction: MoveCommandDirection) {
        guard let full else { return }
        let pixels = CGSize(width: full.size.width * full.scale, height: full.size.height * full.scale)
        let screen = CGSize(width: screenPoints.width * displayScale, height: screenPoints.height * displayScale)
        let mapped: ImageZoom.Direction
        switch direction {
        case .left: mapped = .left
        case .right: mapped = .right
        case .up: mapped = .up
        case .down: mapped = .down
        @unknown default: return
        }
        change { $0.pan(mapped, image: pixels, screen: screen) }
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
