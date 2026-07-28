public struct SwitcherPresentationSnapshot<Element> {
    public let listItems: [SwitcherListItem]
    public let selectedIndex: Int
    private let elements: [Element]
    private let elementIndicesByListItemID: [String: Int]

    public init(
        elements: [Element],
        reverse: Bool,
        listItem: (Element) -> SwitcherListItem
    ) {
        let listItems = elements.map(listItem)
        var elementIndicesByListItemID: [String: Int] = [:]
        elementIndicesByListItemID.reserveCapacity(listItems.count)
        for index in listItems.indices where elementIndicesByListItemID[listItems[index].id] == nil {
            elementIndicesByListItemID[listItems[index].id] = index
        }

        self.elements = elements
        self.listItems = listItems
        self.elementIndicesByListItemID = elementIndicesByListItemID
        self.selectedIndex = SwitcherRecencyStore.initialSelectedIndex(
            itemCount: elements.count,
            reverse: reverse
        )
    }

    public func element(at index: Int) -> Element? {
        guard index >= 0 && index < elements.count else {
            return nil
        }

        return elements[index]
    }

    /// Resolves by identity rather than position: closing a window shifts the
    /// live overlay's indices away from this snapshot's ordering.
    public func element(withID id: String) -> Element? {
        guard let index = elementIndicesByListItemID[id] else {
            return nil
        }

        return elements[index]
    }
}
