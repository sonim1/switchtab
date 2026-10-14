import Combine

struct SwitcherOverlayAccessibilityFocusRequest: Equatable {
    let itemID: String
    let generation: UInt64
}

@MainActor
public final class SwitcherOverlayPresentationModel: ObservableObject {
    @Published public private(set) var state: SwitcherOverlayState
    /// Pointer hovering only steers the highlight after the pointer has moved,
    /// because the overlay usually opens underneath a resting cursor.
    @Published public private(set) var isHoverSelectionEnabled: Bool
    /// Bumped only by keyboard-driven selection changes, so hovering never
    /// scrolls the grid out from under the pointer.
    @Published public private(set) var scrollToken: Int
    @Published private(set) var accessibilityFocusRequest: SwitcherOverlayAccessibilityFocusRequest?
    private var accessibilityFocusGeneration: UInt64 = 0

    public init(
        state: SwitcherOverlayState = SwitcherOverlayState(),
        isHoverSelectionEnabled: Bool = false,
        scrollToken: Int = 0
    ) {
        self.state = state
        self.isHoverSelectionEnabled = isHoverSelectionEnabled
        self.scrollToken = scrollToken
    }

    public func update(_ state: SwitcherOverlayState) {
        self.state = state
    }

    public func setHoverSelectionEnabled(_ enabled: Bool) {
        guard isHoverSelectionEnabled != enabled else {
            return
        }

        isHoverSelectionEnabled = enabled
    }

    public func advanceScrollToken() {
        scrollToken += 1
    }

    func requestAccessibilityFocus(for itemID: String) {
        accessibilityFocusGeneration &+= 1
        accessibilityFocusRequest = SwitcherOverlayAccessibilityFocusRequest(
            itemID: itemID,
            generation: accessibilityFocusGeneration
        )
    }

    func clearAccessibilityFocusRequest() {
        accessibilityFocusRequest = nil
    }
}
