import Combine
@testable import SwitchTab
import XCTest

enum SwitcherOverlayPresentationModelTests {
    @MainActor
    static func run() throws {
        try testSelectionUpdatesArePublished()
        try testHoverGateAndScrollTokenArePublished()
        try testAccessibilityFocusRequestPublishesDistinctGenerationsAndClears()
        try testAccessibilityFocusRequestFollowsPresentationSelectionAndDismissal()
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

    @MainActor
    static func testAccessibilityFocusRequestPublishesDistinctGenerationsAndClears() throws {
        let model = SwitcherOverlayPresentationModel()
        var observedRequests: [SwitcherOverlayAccessibilityFocusRequest?] = []
        let cancellable = model.$accessibilityFocusRequest.dropFirst().sink { request in
            observedRequests.append(request)
        }

        model.requestAccessibilityFocus(for: "finder")
        let firstRequest = try XCTUnwrap(model.accessibilityFocusRequest)
        model.requestAccessibilityFocus(for: "finder")
        let secondRequest = try XCTUnwrap(model.accessibilityFocusRequest)
        model.clearAccessibilityFocusRequest()

        withExtendedLifetime(cancellable) {}
        try expectEqual(firstRequest.itemID, "finder")
        try expectEqual(secondRequest.itemID, "finder")
        try expectTrue(secondRequest.generation > firstRequest.generation)
        try expectEqual(observedRequests, [firstRequest, secondRequest, nil])
        try expectEqual(model.accessibilityFocusRequest, nil)
    }

    @MainActor
    static func testAccessibilityFocusRequestFollowsPresentationSelectionAndDismissal() throws {
        let controller = SwitcherOverlayController(
            thumbnailStore: WindowThumbnailStore(),
            eventTapBackend: UnavailableSwitcherOverlayEventTapBackend()
        )
        defer { controller.dismiss() }
        let initialItems = [
            SwitcherListItem(
                id: "finder",
                title: "Finder",
                subtitle: "2 windows",
                appIconProcessIdentifier: 1
            ),
            SwitcherListItem(
                id: "safari",
                title: "Safari",
                subtitle: "3 windows",
                appIconProcessIdentifier: 2
            )
        ]

        let presentationID = try XCTUnwrap(controller.present(
            mode: .applicationSwitching,
            items: initialItems
        ))
        let initialRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)

        _ = controller.handle(.moveDown)
        let selectionRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)
        controller.updateApplicationItems(
            [
                SwitcherListItem(
                    id: "finder",
                    title: "Finder",
                    subtitle: "2 windows",
                    appIconProcessIdentifier: 1
                ),
                SwitcherListItem(
                    id: "safari",
                    title: "Safari",
                    subtitle: "4 windows",
                    appIconProcessIdentifier: 2
                )
            ],
            presentationID: presentationID
        )
        let metadataRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)
        controller.confirmApplicationTerminated(id: "safari", processIdentifier: 2)
        let selectedRemovalRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)

        _ = controller.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "safari-window", title: "Safari", subtitle: nil)],
            retainingSession: true
        )
        let modeSwitchRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)
        controller.dismiss()
        let repeatedPresentationID = try XCTUnwrap(controller.present(
            mode: .applicationSwitching,
            items: initialItems
        ))
        let repeatedPresentationRequest = try XCTUnwrap(controller.presentationAccessibilityFocusRequest)
        controller.dismiss()

        try expectEqual(initialRequest.itemID, "finder")
        try expectEqual(selectionRequest.itemID, "safari")
        try expectTrue(selectionRequest.generation > initialRequest.generation)
        try expectEqual(metadataRequest, selectionRequest)
        try expectEqual(selectedRemovalRequest.itemID, "finder")
        try expectTrue(selectedRemovalRequest.generation > selectionRequest.generation)
        try expectEqual(modeSwitchRequest.itemID, "safari-window")
        try expectTrue(modeSwitchRequest.generation > selectedRemovalRequest.generation)
        try expectEqual(repeatedPresentationID, presentationID + 2)
        try expectEqual(repeatedPresentationRequest.itemID, "finder")
        try expectTrue(repeatedPresentationRequest.generation > modeSwitchRequest.generation)
        try expectEqual(controller.presentationAccessibilityFocusRequest, nil)
    }
}

@MainActor
private final class UnavailableSwitcherOverlayEventTapBackend: SwitcherOverlayEventTapBackend {
    func install(
        handler _: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)? {
        nil
    }
}
