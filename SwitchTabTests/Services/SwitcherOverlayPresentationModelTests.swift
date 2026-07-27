import Combine
import SwitchTab

enum SwitcherOverlayPresentationModelTests {
    @MainActor
    static func run() throws {
        var state = SwitcherOverlayState()
        state.present(
            mode: .currentAppWindowSwitching,
            items: [
                SwitcherListItem(id: "finder", title: "Finder", subtitle: nil),
                SwitcherListItem(id: "safari", title: "Safari", subtitle: nil)
            ]
        )
        let model = SwitcherOverlayPresentationModel(state: state)
        var observedIndices: [Int] = []
        let cancellable = model.$state.dropFirst().sink { publishedState in
            if let selectedIndex = publishedState.session?.selectedIndex {
                observedIndices.append(selectedIndex)
            }
        }

        _ = state.handle(.moveDown)
        model.update(state)

        withExtendedLifetime(cancellable) {}
        try expectEqual(model.state.session?.selectedIndex, 1)
        try expectEqual(observedIndices, [1])
    }
}
