import ImageIO
import PanGalacticCore
import PanGalacticServices
import SwiftUI
import UIKit

/// Full-screen view of one history image, rendered by N.I.N.A. on request.
/// Shows the thumbnail immediately and swaps in the full render when it arrives.
struct ImageViewer: View {
    let index: Int
    let image: NINAImageSaveStatistics?
    let thumbnail: Data?
    let service: ImageRenderService?

    @State private var rendered: UIImage?
    @State private var failure: String?
    @State private var started = Date()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let shown = rendered ?? thumbnail.flatMap(UIImage.init(data:)) {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    if let image {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: image.targetName ?? "—").font(.title3.bold())
                            Text(verbatim: [image.filter, image.exposureTime.map(LatestImageCard.seconds), image.imageType]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.callout)
                        }
                    }
                    Spacer()
                    status
                }
                .padding(28)
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
                .padding(40)
            }
        }
        .task(id: index) { await load() }
    }

    @ViewBuilder private var status: some View {
        if let failure {
            Label("Full image unavailable: \(String(localized: String.LocalizationValue(failure)))",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if rendered == nil {
            TimelineView(.periodic(from: started, by: 1)) { context in
                HStack(spacing: 16) {
                    ProgressView()
                    Text("N.I.N.A. is rendering the full image… \(Int(context.date.timeIntervalSince(started))) s")
                        .font(.callout)
                }
            }
        }
    }

    private func load() async {
        guard let service else { return }
        started = Date()
        failure = nil
        // 1920×1080 also on 4K screens: the render on the telescope PC is the bottleneck.
        let request = ImageRenderService.Request(index: index)
        do {
            let data = try await service.render(request)
            let maxPixel = max(request.size.width, request.size.height)
            rendered = await Task.detached(priority: .userInitiated) { Self.downsample(data, maxPixel: maxPixel) }.value
            if rendered == nil { failure = "Unexpected response format" }
        } catch {
            if !Task.isCancelled { failure = Self.describe(error) }
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
