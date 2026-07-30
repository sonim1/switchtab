public struct ApplicationItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let processIdentifier: Int
    public let bundleIdentifier: String?
    public let isActive: Bool
    public let switcherListItem: SwitcherListItem

    public init(
        id: String,
        processIdentifier: Int,
        bundleIdentifier: String?,
        isActive: Bool,
        switcherListItem: SwitcherListItem
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.isActive = isActive
        self.switcherListItem = switcherListItem
    }
}
