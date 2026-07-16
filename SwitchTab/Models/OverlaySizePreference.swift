public enum OverlaySizePreference: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .standard:
            return "Default"
        case .large:
            return "Large"
        }
    }
}
