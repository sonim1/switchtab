import Combine

@MainActor
public final class SwitcherOverlayPresentationModel: ObservableObject {
    @Published public private(set) var state: SwitcherOverlayState

    public init(state: SwitcherOverlayState = SwitcherOverlayState()) {
        self.state = state
    }

    public func update(_ state: SwitcherOverlayState) {
        self.state = state
    }
}
