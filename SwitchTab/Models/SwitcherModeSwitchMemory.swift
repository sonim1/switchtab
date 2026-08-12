/// Remembers where each mode's highlight sat while the trigger modifier stays
/// held, so toggling between application and window switching resumes instead
/// of restarting. The memory belongs to one overlay session and is cleared when
/// that session ends.
public struct SwitcherModeSwitchMemory: Equatable, Sendable {
    public private(set) var applicationID: String?
    public private(set) var windowIDByOwnerProcessIdentifier: [Int: String]

    public init(
        applicationID: String? = nil,
        windowIDByOwnerProcessIdentifier: [Int: String] = [:]
    ) {
        self.applicationID = applicationID
        self.windowIDByOwnerProcessIdentifier = windowIDByOwnerProcessIdentifier
    }

    public var isEmpty: Bool {
        applicationID == nil && windowIDByOwnerProcessIdentifier.isEmpty
    }

    public mutating func rememberApplication(id: String) {
        applicationID = id
    }

    public mutating func rememberWindow(id: String, ownerProcessIdentifier: Int) {
        windowIDByOwnerProcessIdentifier[ownerProcessIdentifier] = id
    }

    public func windowID(ownerProcessIdentifier: Int) -> String? {
        windowIDByOwnerProcessIdentifier[ownerProcessIdentifier]
    }

    /// Drops windows of an application that is gone so a recycled process
    /// identifier cannot resume a stale selection.
    public mutating func forgetWindows(ownerProcessIdentifier: Int) {
        windowIDByOwnerProcessIdentifier.removeValue(forKey: ownerProcessIdentifier)
    }

    public mutating func reset() {
        applicationID = nil
        windowIDByOwnerProcessIdentifier.removeAll(keepingCapacity: false)
    }

    /// Resolves the highlight a mode arrives on. A remembered position advances
    /// by `advance` steps with wrap-around; without one the caller's fallback
    /// wins, which keeps a first visit identical to a fresh invocation.
    public static func resumedIndex(
        itemCount: Int,
        rememberedIndex: Int?,
        advance: Int,
        fallback: Int
    ) -> Int {
        guard itemCount > 0 else {
            return 0
        }

        guard let rememberedIndex, rememberedIndex >= 0, rememberedIndex < itemCount else {
            return min(max(fallback, 0), itemCount - 1)
        }

        let wrappedIndex = (rememberedIndex + advance) % itemCount
        return wrappedIndex < 0 ? wrappedIndex + itemCount : wrappedIndex
    }
}
