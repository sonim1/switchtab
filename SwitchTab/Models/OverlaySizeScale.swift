import Foundation

/// Continuous switcher size, chosen with a slider instead of fixed steps.
/// `1` is the shipped default; the range brackets it on both sides so the
/// overlay can be shrunk below or grown well past the old presets.
public struct OverlaySizeScale: Equatable, Sendable {
    public static let minimum: Double = 0.7
    public static let maximum: Double = 1.5
    /// Slider granularity: keeps persisted values tidy and stops a single drag
    /// from writing hundreds of defaults updates.
    public static let step: Double = 0.05
    public static let `default` = OverlaySizeScale(1)

    public let value: Double

    public init(_ value: Double) {
        self.value = Self.clamped(value)
    }

    /// Percentage label for the settings slider, e.g. `"120%"`.
    public var percentageText: String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else {
            return 1
        }

        return min(max(value, minimum), maximum)
    }
}
