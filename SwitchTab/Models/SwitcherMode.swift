public enum SwitcherMode: String, CaseIterable, Codable, Equatable, Sendable {
    case currentAppWindowSwitching
    case applicationSwitching

    public var displayName: String {
        switch self {
        case .currentAppWindowSwitching:
            return "Current App Windows"
        case .applicationSwitching:
            return "Applications"
        }
    }
}
