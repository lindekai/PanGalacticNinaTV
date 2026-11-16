import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// Everything N.I.N.A. reports about one device, grouped as `DeviceDetail` builds it,
/// from the same `/equipment/info` poll as the overview. Read-only: no row acts on the
/// device. Sections are focusable so the remote can scroll through long lists.
struct DeviceDetailView: View {
    let connection: InstanceConnection
    let kind: NINAEquipmentSummary.DeviceKind

    private let columns = [GridItem(.flexible(), spacing: Theme.moduleGap, alignment: .top),
                           GridItem(.flexible(), spacing: Theme.moduleGap, alignment: .top),
                           GridItem(.flexible(), spacing: Theme.moduleGap, alignment: .top)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let detail = DeviceDetail(kind: kind, object: connection.equipment?.objects[kind])
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if detail.sections.isEmpty {
                        placeholder(detail)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.moduleGap) {
                            ForEach(detail.sections, id: \.title) { SectionCard(section: $0) }
                        }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.marginVertical)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollClipDisabled()
            .background(Theme.bg)
            .ignoresSafeArea()
            .onChange(of: context.date) { connection.refreshPhase() }
        }
    }

    private var status: NINAEquipmentSummary.DeviceStatus {
        connection.equipment?.devices.first { $0.kind == kind } ?? .init(kind: kind, connected: nil, name: nil)
    }

    private var header: some View {
        HStack(spacing: 24) {
            kind.icon.resizable().scaledToFit().frame(width: 52, height: 52).foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.pgDisplay).foregroundStyle(Theme.text)
                Text(verbatim: [status.name, connection.instance.displayName].compactMap { $0 }.joined(separator: " · "))
                    .font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            DeviceStateLabel(state: DeviceConnectionState.of(status, phase: connection.phase))
        }
    }

    /// Not connected or unknown: the values of a default-constructed object mean nothing.
    private func placeholder(_ detail: DeviceDetail) -> some View {
        let text: LocalizedStringKey = switch detail.connected {
        case false: "N.I.N.A. reports this device as not connected, or no device of this type is chosen."
        case true: "N.I.N.A. reports no further values for this device."
        default: "No data from N.I.N.A. yet."
        }
        return Text(text)
            .font(.pgLabel).foregroundStyle(Theme.text2)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
            .focusable()
    }
}

private struct SectionCard: View {
    let section: DeviceDetail.Section
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(section.title)).font(.pgRubric).foregroundStyle(Theme.text2).textCase(.uppercase)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                DetailRow(row: row)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.focus, lineWidth: focused ? 3 : 0))
        .focusable()
        .focused($focused)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct DetailRow: View {
    let row: DeviceDetail.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            label.font(.pgLabel).fontWeight(row.highlighted ? .semibold : .regular)
                .foregroundStyle(row.highlighted ? Theme.text : Theme.text2).lineLimit(2)
            Spacer(minLength: 12)
            value
        }
    }

    private var label: Text {
        switch row.label {
        case .key(let key): Text(LocalizedStringKey(key))
        case .verbatim(let text): Text(verbatim: text)
        }
    }

    @ViewBuilder private var value: some View {
        switch row.value {
        case .level(let value, let min, let max):
            HStack(spacing: 12) {
                ProgressView(value: value - min, total: max - min).frame(width: 120).tint(Theme.text2)
                styled(Text(verbatim: "\(Int(value)) / \(Int(max))"))
            }
        default:
            styled(text)
        }
    }

    private func styled(_ text: Text) -> some View {
        text.font(.pgValue)
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
    }

    private var color: Color {
        if case .word("Unsafe") = row.value { return Theme.fault }
        if case .missing = row.value { return Theme.text3 }
        return Theme.text
    }

    private var text: Text {
        switch row.value {
        case .missing: Text(verbatim: "—")
        case .text(let text): Text(verbatim: text)
        case .word(let key): Text(LocalizedStringKey(key))
        case .yesNo(let flag): Text(flag ? "Yes" : "No")
        case .onOff(let flag): Text(flag ? "On" : "Off")
        case .number(let value, let digits, let unit): Text(verbatim: Self.format(value, digits: digits, unit: unit))
        case .time(let date): Text(verbatim: date.formatted(date: .omitted, time: .standard))
        case .level(let value, _, _): Text(verbatim: "\(Int(value))")
        case .guiderState(let wire): Text(verbatim: Format.guiderState(wire) ?? wire)
        }
    }

    /// Angles and arcseconds follow the number directly; other units after a space.
    static func format(_ value: Double, digits: Int, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        if unit.isEmpty { return number }
        return unit == "°" || unit.hasPrefix("″") ? number + unit : "\(number) \(unit)"
    }
}
