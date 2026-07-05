public enum WindowAvailability: Equatable, Sendable {
    case available
    case minimized
    case hiddenApplication
    case fullScreen
    case otherSpace
    case otherDisplay
    case closed
    case unavailable
}

public struct WindowItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let windowIdentifier: Int
    public let ownerProcessIdentifier: Int
    public let screenCaptureIdentifier: UInt32?
    public let isMinimized: Bool
    public let canFocus: Bool
    public let switcherListItem: SwitcherListItem

    public init(
        windowIdentifier: Int,
        ownerProcessIdentifier: Int,
        ownerName: String,
        title: String,
        screenCaptureIdentifier: UInt32? = nil,
        isMinimized: Bool,
        availability: WindowAvailability
    ) {
        let id = "\(ownerProcessIdentifier)-\(windowIdentifier)"
        let readableTitle = title.switcherReadableText(fallback: "Untitled Window")
        self.id = id
        self.windowIdentifier = windowIdentifier
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.screenCaptureIdentifier = screenCaptureIdentifier
        self.isMinimized = isMinimized
        // Minimized windows stay focusable: focusing restores them first.
        self.canFocus = availability == .available || availability == .minimized
        self.switcherListItem = SwitcherListItem(
            id: id,
            title: readableTitle,
            subtitle: ownerName,
            symbolName: "app",
            thumbnailKey: id,
            appIconProcessIdentifier: ownerProcessIdentifier
        )
    }
}
