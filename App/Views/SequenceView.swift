import PanGalacticCore
import PanGalacticServices
import SwiftUI

/// The whole Advanced Sequence as a tree, from the same `/sequence/json` poll as the
/// strip. Only the running branch is expanded at first; a click on a container
/// expands or collapses it. Read-only: nothing here acts on the sequence.
struct SequenceView: View {
    let connection: InstanceConnection

    @State private var expanded: Set<[Int]> = []
    @State private var seeded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sequence").font(.pgDisplay).foregroundStyle(Theme.text)
                    Text(verbatim: subtitle).font(.pgLabel).foregroundStyle(Theme.text2)
                }
                if let tree = connection.sequenceTree {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(rows(tree)) { row in
                                    SequenceRow(node: row.node, depth: row.depth,
                                                expanded: expanded.contains(row.node.id)) {
                                        toggle(row.node.id)
                                    }
                                    .id(row.node.id)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        .onAppear { seed(tree, proxy: proxy) }
                        .onChange(of: tree) { prune(tree) }
                    }
                } else {
                    Text("No sequence loaded").font(.pgValue).foregroundStyle(Theme.text2)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, Theme.marginVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            .ignoresSafeArea()
            .opacity(connection.phase == .live ? 1 : 0.55)
            .onChange(of: context.date) { connection.refreshPhase() }
        }
    }

    private var subtitle: String {
        guard connection.phase != .live, let since = connection.lastSuccess else { return connection.instance.displayName }
        return "\(connection.instance.displayName) · " + String(localized: "As of \(since.formatted(date: .omitted, time: .shortened))")
    }

    private struct Row: Identifiable {
        let node: SequenceTree.Node
        let depth: Int
        var id: [Int] { node.id }
    }

    private func rows(_ tree: SequenceTree) -> [Row] {
        var rows: [Row] = []
        func add(_ nodes: [SequenceTree.Node], depth: Int) {
            for node in nodes {
                rows.append(Row(node: node, depth: depth))
                if let children = node.children, expanded.contains(node.id) { add(children, depth: depth + 1) }
            }
        }
        add(tree.roots, depth: 0)
        return rows
    }

    private func toggle(_ id: [Int]) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Once per visit: expand the running chain and scroll to the current step.
    private func seed(_ tree: SequenceTree, proxy: ScrollViewProxy) {
        guard !seeded else { return }
        seeded = true
        expanded = SequenceSteps.runningContainers(in: tree)
        if let current = SequenceSteps(tree: tree).current?.id {
            DispatchQueue.main.async { proxy.scrollTo(current, anchor: .center) }
        }
    }

    /// After a reload, forget ids that no longer exist.
    private func prune(_ tree: SequenceTree) {
        expanded = expanded.filter { tree.node(at: $0)?.isContainer == true }
    }
}

private struct SequenceRow: View {
    let node: SequenceTree.Node
    let depth: Int
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: { if node.isContainer { toggle() } }) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                symbol.frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: node.name.isEmpty ? "—" : node.name)
                        .font(node.isContainer ? .pgValue : .pgLabel)
                        .foregroundStyle(node.status == .disabled || node.status == .skipped ? Theme.text3 : Theme.text)
                        .strikethrough(node.status == .disabled)
                    if !details.isEmpty {
                        Text(verbatim: details).font(.pgLabel).foregroundStyle(Theme.text2)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 16)
                if node.isContainer {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(Theme.text3)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .padding(.leading, CGFloat(depth) * 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(LiftButtonStyle(scale: 1.01))
    }

    @ViewBuilder private var symbol: some View {
        switch node.status {
        case .finished: Image(systemName: "checkmark").foregroundStyle(Theme.text2)
        case .running: Circle().fill(Theme.accent).frame(width: 16, height: 16)
        case .created: Image(systemName: "circle").foregroundStyle(Theme.text3)
        case .failed: Image(systemName: "xmark").foregroundStyle(Theme.fault)
        case .skipped: Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.text3)
        case .disabled: Image(systemName: "minus").foregroundStyle(Theme.text3)
        case .unknown: Text(verbatim: "?").foregroundStyle(Theme.text3)
        }
    }

    private var details: String {
        node.details.map(Self.text).joined(separator: " · ")
    }

    static func text(_ detail: SequenceTree.Detail) -> String {
        switch detail {
        case .untilTime(let date):
            String(localized: "until \(date.formatted(date: .omitted, time: .shortened))")
        case .iterations(let completed, let total):
            String(localized: "\(completed) of \(total)")
        case .ditherEvery(let done, let target):
            String(localized: "Dither every \(target) (\(done)/\(target))")
        case .exposure(let seconds, let type, let gain):
            ([seconds.formatted(.number.precision(.fractionLength(0...2))) + " s", type]
                + [gain.map { String(localized: "Gain \($0)") }]).compactMap { $0 }.joined(separator: " · ")
        case .temperature(let celsius):
            celsius.formatted(.number.precision(.fractionLength(0...1))) + " °C"
        case .filter(let name), .trigger(let name), .condition(let name):
            name
        }
    }
}
