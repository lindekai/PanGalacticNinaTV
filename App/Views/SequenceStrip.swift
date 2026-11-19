import PanGalacticCore
import SwiftUI

/// Last, current and next step of the running sequence, under both overview columns.
/// N.I.N.A.'s step names are shown as sent.
struct SequenceStrip: View {
    /// `nil` while the tree is unknown.
    let steps: SequenceSteps?
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 28) {
            Text("SEQUENCE").font(.pgRubric).tracking(3).foregroundStyle(Theme.text2)
            content
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder private var content: some View {
        if let steps, let current = steps.current {
            if let last = steps.last {
                HStack(spacing: 10) {
                    Image(systemName: last.status == .failed ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(last.status == .failed ? Theme.fault : Theme.text2)
                    Text(verbatim: last.name).foregroundStyle(Theme.text2)
                }
                .font(.pgLabel)
                chevron
            }
            HStack(spacing: 12) {
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                if !current.container.isEmpty {
                    Text(verbatim: current.container).font(.pgValue).foregroundStyle(Theme.text)
                    Text(verbatim: "·").font(.pgLabel).foregroundStyle(Theme.text2)
                }
                Text(verbatim: current.name).font(.pgLabel).foregroundStyle(Theme.text)
            }
            .layoutPriority(1)
            chevron
            HStack(spacing: 6) {
                Text("Next:").foregroundStyle(Theme.text3)
                if let next = steps.next {
                    if !next.container.isEmpty {
                        Text(verbatim: "\(next.container) · ").foregroundStyle(Theme.text2)
                    }
                    Text(verbatim: next.name).foregroundStyle(Theme.text2)
                } else {
                    Text(verbatim: "—").foregroundStyle(Theme.text2)
                }
            }
            .font(.pgLabel)
        } else if steps != nil {
            Text("Not running").font(.pgLabel).foregroundStyle(Theme.text2)
        } else {
            Text(verbatim: "—").font(.pgLabel).foregroundStyle(Theme.text2)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.pgLabel).foregroundStyle(Theme.text3)
    }
}
