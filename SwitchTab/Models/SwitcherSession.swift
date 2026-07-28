public struct SwitcherListItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbolName: String?
    public let thumbnailKey: String?
    public let appIconProcessIdentifier: Int?

    public init(
        id: String,
        title: String,
        subtitle: String?,
        symbolName: String? = nil,
        thumbnailKey: String? = nil,
        appIconProcessIdentifier: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.thumbnailKey = thumbnailKey
        self.appIconProcessIdentifier = appIconProcessIdentifier
    }
}

public struct SwitcherSession: Equatable, Sendable {
    public let mode: SwitcherMode
    public private(set) var items: [SwitcherListItem]
    public private(set) var selectedIndex: Int

    public init(
        mode: SwitcherMode,
        items: [SwitcherListItem],
        selectedIndex: Int = 0
    ) {
        self.mode = mode
        self.items = items
        self.selectedIndex = SwitcherSession.clamped(selectedIndex, itemCount: items.count)
    }

    public var selectedItem: SwitcherListItem? {
        guard !items.isEmpty else {
            return nil
        }

        return items[selectedIndex]
    }

    @discardableResult
    public mutating func moveSelection(by delta: Int) -> Bool {
        guard delta != 0 else {
            return false
        }

        let itemCount = items.count
        guard itemCount > 1 else {
            return false
        }

        let wrappedIndex = selectedIndex + (delta % itemCount)
        let nextIndex: Int
        if wrappedIndex < 0 {
            nextIndex = wrappedIndex + itemCount
        } else if wrappedIndex >= itemCount {
            nextIndex = wrappedIndex - itemCount
        } else {
            nextIndex = wrappedIndex
        }
        guard nextIndex != selectedIndex else {
            return false
        }

        selectedIndex = nextIndex
        return true
    }

    /// Drops a window that is no longer switchable (it was just closed) while
    /// keeping the highlight on a sensible neighbour.
    @discardableResult
    public mutating func removeItem(at index: Int) -> Bool {
        guard index >= 0, index < items.count else {
            return false
        }

        items.remove(at: index)
        if index < selectedIndex {
            selectedIndex -= 1
        }
        selectedIndex = SwitcherSession.clamped(selectedIndex, itemCount: items.count)
        return true
    }

    @discardableResult
    public mutating func selectItem(at index: Int) -> Bool {
        guard index >= 0, index < items.count, index != selectedIndex else {
            return false
        }

        selectedIndex = index
        return true
    }

    private static func clamped(_ index: Int, itemCount: Int) -> Int {
        guard itemCount > 0 else {
            return 0
        }

        return min(max(index, 0), itemCount - 1)
    }
}
