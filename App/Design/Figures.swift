import SwiftUI

/// The one large number of a module. `nil` renders as a dash in `text3`.
struct KeyFigure: View {
    let value: String?
    let unit: String?
    let label: LocalizedStringKey

    init(_ value: String?, unit: String? = nil, label: LocalizedStringKey) {
        self.value = value
        self.unit = unit
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value ?? "—").font(.pgKeyFigure)
                    .foregroundStyle(value == nil ? Theme.text3 : Theme.text)
                if let unit, value != nil {
                    Text(verbatim: unit).font(.pgKeyUnit).foregroundStyle(Theme.text2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(1)
        }
    }
}

/// Label/value rows, values right-aligned on one edge, hairlines between rows.
struct SideValues: View {
    let rows: [(LocalizedStringKey, String?)]

    init(_ rows: [(LocalizedStringKey, String?)]) { self.rows = rows }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                if offset > 0 { Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1) }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.pgLabel).foregroundStyle(Theme.text2)
                    Spacer(minLength: 16)
                    Text(verbatim: row.1 ?? "—").font(.pgValue)
                        .foregroundStyle(row.1 == nil ? Theme.text3 : Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(height: 44)
            }
        }
        .frame(width: 300)
    }
}

/// Compact value for the three small tiles (mount, guiding, filter).
struct TileValue: View {
    let value: String?
    let detail: String?

    init(_ value: String?, detail: String?) {
        self.value = value
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value ?? "—").font(.pgTileValue)
                .foregroundStyle(value == nil ? Theme.text3 : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let detail {
                Text(verbatim: detail).font(.pgLabel).foregroundStyle(Theme.text2).lineLimit(2)
            }
        }
    }
}
