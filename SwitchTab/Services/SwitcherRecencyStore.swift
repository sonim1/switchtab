import Foundation

public final class SwitcherRecencyStore {
    private static let emptyRankedIDs: [String] = []

    private let userDefaults: UserDefaults
    private let maxHistoryCount: Int
    private let mode: SwitcherMode
    private let recencyStorageKey: String
    private var cachedRankedIDs: [String]?
    private var isHistoryDirty = false

    public init(
        userDefaults: UserDefaults = .standard,
        maxHistoryCount: Int = 100,
        mode: SwitcherMode = .currentAppWindowSwitching
    ) {
        self.userDefaults = userDefaults
        self.maxHistoryCount = maxHistoryCount
        self.mode = mode
        self.recencyStorageKey = "SwitchTab.recency.\(mode.rawValue)"
    }

    public static func initialSelectedIndex(itemCount: Int, reverse: Bool) -> Int {
        guard itemCount > 1 else {
            return 0
        }

        return reverse ? itemCount - 1 : 1
    }

    public func recordSelection(id: String) {
        guard maxHistoryCount > 0 else {
            return
        }

        let currentIDs = rankedIDs()
        guard currentIDs.first != id else {
            return
        }

        // Move `id` to the front, keep the rest in order, dedupe, cap at maxHistoryCount.
        var ids: [String] = []
        ids.reserveCapacity(min(maxHistoryCount, currentIDs.count + 1))
        ids.append(id)
        for currentID in currentIDs {
            guard ids.count < maxHistoryCount else {
                break
            }
            guard currentID != id else {
                continue
            }

            ids.append(currentID)
        }
        cachedRankedIDs = ids
        isHistoryDirty = true
    }

    public func flush() {
        guard isHistoryDirty else {
            return
        }

        if isHistoryDirty, let rankedIDs = cachedRankedIDs {
            userDefaults.set(rankedIDs, forKey: recencyStorageKey)
            isHistoryDirty = false
        }
    }

    public func order<Item>(
        _ items: [Item],
        id: (Item) -> String
    ) -> [Item] {
        guard items.count > 1 else {
            return items
        }

        let rankedIDs = rankedIDs()
        guard !rankedIDs.isEmpty else {
            return items
        }

        var rankByID: [String: Int] = [:]
        rankByID.reserveCapacity(rankedIDs.count)
        for index in rankedIDs.indices where rankByID[rankedIDs[index]] == nil {
            rankByID[rankedIDs[index]] = index
        }

        // Single pass over items, reading each id once. Stop as soon as every
        // ranked id has been located — ranked lists are short, so this keeps the
        // common "history already leads" case from scanning the whole list.
        var matched: [(rank: Int, index: Int)] = []
        var isMatched = [Bool](repeating: false, count: items.count)
        for index in items.indices {
            guard let rank = rankByID[id(items[index])] else {
                continue
            }

            matched.append((rank, index))
            isMatched[index] = true
            if matched.count == rankByID.count {
                break
            }
        }

        guard !matched.isEmpty else {
            return items
        }

        matched.sort { $0.rank < $1.rank }

        // If the matched items already lead the list in ranked order, nothing moves.
        var alreadyLeads = true
        for offset in matched.indices where matched[offset].index != offset {
            alreadyLeads = false
            break
        }
        if alreadyLeads {
            return items
        }

        var orderedItems: [Item] = []
        orderedItems.reserveCapacity(items.count)
        for entry in matched {
            orderedItems.append(items[entry.index])
        }
        for index in items.indices where !isMatched[index] {
            orderedItems.append(items[index])
        }
        return orderedItems
    }

    private func rankedIDs() -> [String] {
        guard maxHistoryCount > 0 else {
            return []
        }

        if let cachedRankedIDs {
            return cachedRankedIDs
        }

        guard let rankedIDs = userDefaults.stringArray(forKey: recencyStorageKey) else {
            cachedRankedIDs = Self.emptyRankedIDs
            return Self.emptyRankedIDs
        }

        guard !rankedIDs.isEmpty else {
            cachedRankedIDs = Self.emptyRankedIDs
            return Self.emptyRankedIDs
        }

        let normalizedRankedIDs = normalizedRankedIDs(from: rankedIDs)
        cachedRankedIDs = normalizedRankedIDs
        return normalizedRankedIDs
    }

    private func normalizedRankedIDs(from rankedIDs: [String]) -> [String] {
        var normalizedIDs: [String] = []
        normalizedIDs.reserveCapacity(min(maxHistoryCount, rankedIDs.count))

        for rankedID in rankedIDs {
            guard normalizedIDs.count < maxHistoryCount else {
                break
            }
            guard !normalizedIDs.contains(rankedID) else {
                continue
            }

            normalizedIDs.append(rankedID)
        }
        return normalizedIDs
    }
}
