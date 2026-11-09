import PanGalacticCore
import SwiftUI
import UIKit

/// The newest frame from N.I.N.A.'s image history with its key statistics.
struct LatestImageCard: View {
    let image: NINAImageSaveStatistics?
    let thumbnail: Data?
    /// Shown when the data is not live, so an old frame is never mistaken for a new one.
    let asOf: Date?
    let now: Date
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 20) {
                preview
                if let image {
                    metadata(image)
                } else {
                    Text("No image in this N.I.N.A. session yet")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.card)
        .disabled(image == nil)
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            Rectangle().fill(.black)
            if let thumbnail, let uiImage = UIImage(data: thumbnail) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else if image != nil {
                ProgressView("Loading preview…")
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if let asOf {
                Label("As of \(asOf.formatted(date: .omitted, time: .shortened))", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.yellow.opacity(0.85), in: .capsule)
                    .foregroundStyle(.black)
                    .padding(16)
            }
        }
    }

    private func metadata(_ image: NINAImageSaveStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: image.targetName ?? "—").font(.title2.bold()).lineLimit(1)
                if let type = image.imageType {
                    Text(verbatim: type)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary, in: .capsule)
                }
                Spacer()
                if let date = image.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 40) {
                Stat("Filter", image.filter)
                Stat("Exposure", image.exposureTime.map { Self.seconds($0) })
                Stat("HFR", image.hfr.map { $0.formatted(.number.precision(.fractionLength(2))) })
                Stat("Stars", image.stars.map { $0.formatted() })
            }
        }
    }

    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }
}

/// Compact label/value pair; `nil` renders as a dash, never as zero.
struct Stat: View {
    let label: LocalizedStringKey
    let value: String?

    init(_ label: LocalizedStringKey, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value ?? "—")
                .font(.title3.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
