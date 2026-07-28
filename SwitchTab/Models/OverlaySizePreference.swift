/// Legacy three-step overlay size. Kept only so previously stored preferences
/// migrate onto the continuous `OverlaySizeScale`.
public enum OverlaySizePreference: String, Sendable {
    case compact
    case standard
    case large

    public var scale: OverlaySizeScale {
        switch self {
        case .compact:
            return OverlaySizeScale(0.8)
        case .standard:
            return OverlaySizeScale(1)
        case .large:
            return OverlaySizeScale(1.2)
        }
    }
}
