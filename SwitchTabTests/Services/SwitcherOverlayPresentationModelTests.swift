import Combine
import SwitchTab

enum SwitcherOverlayPresentationModelTests {
    @MainActor
    static func run() throws {
        try testSelectionUpdatesArePublished()
        try testHoverGateAndScrollTokenArePublished()
    }

    @MainActor
    static func testSelectionUpdatesArePublished() throws {
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

    @MainActor
    static func testHoverGateAndScrollTokenArePublished() throws {
        let model = SwitcherOverlayPresentationModel()
        var observedHoverStates: [Bool] = []
        var observedTokens: [Int] = []
        let hoverCancellable = model.$isHoverSelectionEnabled.dropFirst().sink { enabled in
            observedHoverStates.append(enabled)
        }
        let tokenCancellable = model.$scrollToken.dropFirst().sink { token in
            observedTokens.append(token)
        }

        try expectFalse(model.isHoverSelectionEnabled)
        model.setHoverSelectionEnabled(false)
        model.setHoverSelectionEnabled(true)
        model.setHoverSelectionEnabled(true)
        model.advanceScrollToken()
        model.advanceScrollToken()

        withExtendedLifetime((hoverCancellable, tokenCancellable)) {}
        try expectTrue(model.isHoverSelectionEnabled)
        try expectEqual(observedHoverStates, [true])
        try expectEqual(observedTokens, [1, 2])
        try expectEqual(model.scrollToken, 2)
    }
}
