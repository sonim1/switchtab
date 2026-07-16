import AppKit
import SwitchTab

enum SwitcherOverlayPresentationPolicyTests {
    static func run() throws {
        try testSwitcherOverlayDoesNotActivateApplication()
        try testSwitcherOverlayCanBecomeKeyWithoutBecomingMain()
        try testSwitcherOverlayCentersPanelInScreen()
        try testLocalEventMonitorSkipsKeyUpEvents()
        try testOverlayControllerBuildsApplicationIconStoreInsideMainActorInitializer()
        try testActiveScreenFramePrefersScreenContainingPointer()
        try testActiveScreenFrameFallsBackWhenPointerOutsideAllScreens()
    }

    static func testSwitcherOverlayDoesNotActivateApplication() throws {
        try expectTrue(SwitcherOverlayPresentationPolicy.styleMask.contains(.nonactivatingPanel))
    }

    static func testSwitcherOverlayCanBecomeKeyWithoutBecomingMain() throws {
        try expectTrue(SwitcherOverlayPresentationPolicy.canBecomeKey)
        try expectFalse(SwitcherOverlayPresentationPolicy.canBecomeMain)
    }

    static func testSwitcherOverlayCentersPanelInScreen() throws {
        let origin = SwitcherOverlayPresentationPolicy.panelOrigin(
            panelSize: CGSize(width: 400, height: 200),
            screenFrame: CGRect(x: 100, y: 50, width: 1200, height: 800)
        )

        try expectEqual(origin.x, 500)
        try expectEqual(origin.y, 350)
    }

    static func testLocalEventMonitorSkipsKeyUpEvents() throws {
        try expectTrue(SwitcherOverlayEventMonitorPolicy.localMask.contains(.keyDown))
        try expectTrue(SwitcherOverlayEventMonitorPolicy.localMask.contains(.flagsChanged))
        try expectFalse(SwitcherOverlayEventMonitorPolicy.localMask.contains(.keyUp))
    }

    static func testOverlayControllerBuildsApplicationIconStoreInsideMainActorInitializer() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("SwitchTab/UI/Overlay/SwitcherOverlayController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains("applicationIconStore: ApplicationIconStore? = nil"))
        try expectTrue(source.contains("self.applicationIconStore = applicationIconStore ?? ApplicationIconStore()"))
        try expectFalse(source.contains("applicationIconStore: ApplicationIconStore = ApplicationIconStore()"))
    }

    static func testActiveScreenFramePrefersScreenContainingPointer() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)

        let frame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: CGPoint(x: 2000, y: 400),
            screenFrames: [primary, secondary],
            fallback: primary
        )

        try expectEqual(frame, secondary)
    }

    static func testActiveScreenFrameFallsBackWhenPointerOutsideAllScreens() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let frame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: CGPoint(x: -50, y: -50),
            screenFrames: [primary],
            fallback: primary
        )

        try expectEqual(frame, primary)
    }
}
