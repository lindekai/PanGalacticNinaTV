import PanGalacticCore
import SwiftUI
import UIKit

/// The newest frame: focusable image with crosshair and a caption below it.
/// Old frames are labelled "As of …" so they are never mistaken for new ones.
struct LatestImageCard: View {
    let image: NINAImageSaveStatistics?
    let thumbnail: Data?
    let hfrSeries: [Double]
    let asOf: Date?
    let now: Date
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                preview
                caption
            }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(image == nil)
    }

    private var preview: some View {
        ZStack {
            Rectangle().fill(Color.black)
            if let thumbnail, let uiImage = UIImage(data: thumbnail) {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else if image != nil {
                ProgressView()
            } else {
                Text("No image in this N.I.N.A. session yet").font(.pgLabel).foregroundStyle(Theme.text3)
            }
            Crosshair().stroke(Theme.text.opacity(0.28), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let asOf {
                Text("As of \(asOf.formatted(date: .omitted, time: .shortened))")
                    .font(.pgLabel).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Theme.warn, in: .capsule)
                    .padding(20)
            }
        }
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: image?.targetName ?? "—").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.text).lineLimit(1)
                Text(verbatim: metadata).font(.pgLabel).monospacedDigit().foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 16)
            if hfrSeries.count >= 2 {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("HFR · last \(hfrSeries.count) frames").font(.pgRubric).tracking(2)
                        .textCase(.uppercase).foregroundStyle(Theme.text2)
                    Sparkline(hfrSeries).frame(width: 220, height: 44)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// "Light · L · 300 s · HFR 2.14 · 1 834 stars · 12 s ago"; unknown parts are left out.
    private var metadata: String {
        guard let image else { return "" }
        var parts: [String] = []
        if let type = image.imageType { parts.append(type.capitalized) }
        if let filter = image.filter { parts.append(filter) }
        if let exposure = image.exposureTime { parts.append(Format.seconds(exposure)) }
        if let hfr = image.hfr { parts.append("HFR " + Format.hfr(hfr)) }
        if let stars = image.stars { parts.append(String(localized: "\(stars) stars")) }
        if let date = image.date { parts.append(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) }
        return parts.joined(separator: " · ")
    }
}

/// 1 px crosshair with a gap in the centre so the object is never covered.
private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        let gap: CGFloat = 22
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - gap))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY + gap)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.midX - gap, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX + gap, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
