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

/// Header pill: small uppercase key, value, optional LED and progress underline.
struct StatusPill: View {
    let key: LocalizedStringKey?
    let value: String
    let light: StatusLight?
    let progress: Double?

    init(_ key: LocalizedStringKey?, value: String, light: StatusLight? = nil, progress: Double? = nil) {
        self.key = key
        self.value = value
        self.light = light
        self.progress = progress
    }

    var body: some View {
        HStack(spacing: 12) {
            if let light { StatusLED(light) }
            if let key {
                Text(key).font(.pgRubric).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.text2)
            }
            Text(verbatim: value).font(.pgValue).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Theme.surface, in: .capsule)
        .overlay(alignment: .bottom) {
            if let progress {
                GeometryReader { geo in
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
    }
}
