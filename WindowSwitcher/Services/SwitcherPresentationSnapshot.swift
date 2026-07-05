public struct SwitcherPresentationSnapshot<Element> {
    public let listItems: [SwitcherListItem]
    public let selectedIndex: Int
    private let elements: [Element]

    public init(
        elements: [Element],
        reverse: Bool,
        listItem: (Element) -> SwitcherListItem
    ) {
        self.elements = elements
        self.listItems = elements.map(listItem)
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
}
