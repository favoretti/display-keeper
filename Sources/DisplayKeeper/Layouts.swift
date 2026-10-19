import AppKit
import Combine
import DisplayKeeperCore

/// Saved profiles as the UI shows them, with the one for the connected monitors marked.
@MainActor
final class LayoutsModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let profile: Profile
        let isCurrent: Bool
    }

    @Published private(set) var items: [Item] = []
    private let keeper: Keeper
    private var observers: [NSObjectProtocol] = []

    init(keeper: Keeper) {
        self.keeper = keeper
        reload()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } })
    }

    var current: Item? { items.first(where: \.isCurrent) }

    func reload() {
        let currentID = Profile.id(for: SystemDisplays.online().map(\.placement.key))
        let next = keeper.store.all().map { Item(id: $0.key, profile: $0.value, isCurrent: $0.key == currentID) }
            .sorted { a, b in a.isCurrent != b.isCurrent ? a.isCurrent : a.profile.savedAt > b.profile.savedAt }
        if next != items { items = next }
    }

    @discardableResult
    func saveCurrent() throws -> Profile {
        defer { reload() }
        return try keeper.saveCurrent()
    }

    func delete(id: String) throws {
        defer { reload() }
        try keeper.store.remove(id: id)
    }

    func forgetCurrent() throws {
        try delete(id: Profile.id(for: SystemDisplays.online().map(\.placement.key)))
    }
}

extension Profile {
    /// "2 × DELL U2723QE + Built-in Retina Display", left to right.
    var monitorSummary: String {
        var counts: [(String, Int)] = []
        for p in placementsLeftToRight {
            let name = p.baseName
            if let i = counts.firstIndex(where: { $0.0 == name }) { counts[i].1 += 1 } else { counts.append((name, 1)) }
        }
        return counts.map { $0.1 > 1 ? "\($0.1) × \($0.0)" : $0.0 }.joined(separator: " + ")
    }

    /// Display names by key; identical monitors are numbered left to right.
    var displayLabels: [String: String] {
        var labels: [String: String] = [:]
        for (name, group) in Dictionary(grouping: placements, by: \.name) {
            let ordered = group.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            for (i, p) in ordered.enumerated() { labels[p.key] = ordered.count > 1 ? "\(name) (\(i + 1))" : name }
        }
        return labels
    }

    var placementsLeftToRight: [Placement] { placements.sorted { ($0.x, $0.y) < ($1.x, $1.y) } }
}

extension Placement {
    /// macOS numbers identical monitors itself ("U28H75x (2)"); drop that for grouping.
    var baseName: String {
        name.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
    }
}
