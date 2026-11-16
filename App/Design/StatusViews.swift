import PanGalacticCore
import SwiftUI

/// Filled dot for known states, hollow ring for unknown/unavailable.
struct StatusLED: View {
    let light: StatusLight

    init(_ light: StatusLight) { self.light = light }

    var body: some View {
        Group {
            if light == .unknown {
                Circle().strokeBorder(Theme.text3, lineWidth: 2)
            } else {
                Circle().fill(Theme.color(for: light))
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(Text(label))
    }

    private var label: LocalizedStringKey {
        switch light {
        case .normal: "Normal"
        case .warning: "Warning"
        case .fault: "Fault"
        case .unknown: "Unknown"
        }
    }
}

/// Header pill: "Key · value" in one font and size on one baseline, like "LIVE · 17:21";
/// the key in `text2`, the value in `text`. `reserve` is a template string whose width the
/// value never falls below, so a ticking countdown does not shift the header.
struct StatusPill: View {
    let key: LocalizedStringKey?
    let value: String
    let light: StatusLight?
    let reserve: String?

    init(_ key: LocalizedStringKey?, value: String, light: StatusLight? = nil, reserve: String? = nil) {
        self.key = key
        self.value = value
        self.light = light
        self.reserve = reserve
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let light { StatusLED(light).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 } }
            if let key {
                Text(key).foregroundStyle(Theme.text2)
                Text(verbatim: "·").foregroundStyle(Theme.text3)
            }
            ZStack(alignment: .leading) {
                if let reserve { Text(verbatim: reserve).hidden() }
                Text(verbatim: value).foregroundStyle(Theme.text)
            }
        }
        .font(.pgValue)
        .lineLimit(1)
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Theme.surface, in: .capsule)
    }
}
