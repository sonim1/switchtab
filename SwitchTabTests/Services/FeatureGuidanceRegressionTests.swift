import AppKit
import XCTest
@testable import SwitchTab

@MainActor
final class FeatureGuidanceRegressionTests: XCTestCase {
    func testCancellationCallbackDoesNotFireForConfirmation() {
        let controller = SwitcherOverlayController(
            thumbnailStore: WindowThumbnailStore(),
            eventTapBackend: PracticeTestEventTapBackend()
        )
        let item = SwitcherListItem(id: "42-7", title: "Fixture", subtitle: nil)
        var cancellations = 0
        var confirmations = 0
        controller.onCancel = { cancellations += 1 }
        controller.present(mode: .currentAppWindowSwitching, items: [item], onConfirm: { _, _ in confirmations += 1 })
        _ = controller.handle(.cancel)
        XCTAssertEqual(cancellations, 1)
        controller.present(mode: .currentAppWindowSwitching, items: [item], onConfirm: { _, _ in confirmations += 1 })
        _ = controller.handle(.confirm)
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(cancellations, 1)
        controller.present(mode: .currentAppWindowSwitching, items: [item])
        controller.dismiss()
        controller.dismiss()
        XCTAssertEqual(cancellations, 2)
    }

    func testMinimizedWindowKeepsRestoreStateInPresentationItem() {
        let window = makeWindow(7, minimized: true)
        XCTAssertTrue(window.canFocus)
        XCTAssertTrue(window.switcherListItem.isMinimized)
        XCTAssertFalse(makeWindow(8).switcherListItem.isMinimized)
    }

    func testPreviewPermissionAndLoadingAreDifferentStates() async {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let loader = WindowThumbnailLoader(store: store, capturer: PracticeTestThumbnailCapturer())
        loader.beginRefresh(permissionState: PermissionState(accessibility: .granted, screenRecording: .missing))
        XCTAssertEqual(store.previewState(for: window.id), .permissionBlocked)
        loader.beginRefresh(permissionState: granted)
        loader.requestThumbnail(for: window, priority: .selected)
        XCTAssertEqual(store.previewState(for: window.id), .loading)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(store.previewState(for: window.id), .available)
    }

    func testFailedPreviewStopsLoadingAndIsNotRetriedInGeneration() async {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = PracticeTestThumbnailCapturer(succeeds: false)
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(permissionState: granted)
        loader.requestThumbnail(for: window, priority: .selected)
        XCTAssertEqual(store.previewState(for: window.id), .loading)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(store.previewState(for: window.id), .unavailable)
        loader.requestThumbnail(for: window, priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.captureCount, 1)
    }

    func testPreviewLoadingMetadataIsBoundedAndClearedOnCancel() async {
        let store = WindowThumbnailStore()
        let loader = WindowThumbnailLoader(store: store, capturer: PracticeTestThumbnailCapturer())
        let windows = (1...200).map { makeWindow($0) }
        loader.beginRefresh(permissionState: granted)
        for window in windows { loader.requestThumbnail(for: window, priority: .visible) }
        XCTAssertEqual(windows.filter { store.previewState(for: $0.id) == .loading }.count, 64)
        loader.cancel(preservingCachedThumbnails: true)
        XCTAssertEqual(windows.filter { store.previewState(for: $0.id) == .loading }.count, 0)
        await loader.waitForCurrentRefresh()
    }

    func testLegacyShortcutCountsRemainCompatible() throws {
        let suiteName = "SwitchTabTests.UsageCompatibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let key = "SwitchTab.usage.2026-10-04.currentAppWindowSwitching"
        defaults.set(19, forKey: key)
        let store = UsageMetricsStore(userDefaults: defaults, calendar: calendar, now: { date })
        XCTAssertEqual(store.todayDashboard(windowShortcutLabel: "Option + Control + `").totalCount, 19)
        store.recordWindowShortcutUse()
        store.flush()
        XCTAssertEqual(defaults.integer(forKey: key), 20)
    }

    private var granted: PermissionState { PermissionState(accessibility: .granted, screenRecording: .granted) }

    private func makeWindow(_ identifier: Int, minimized: Bool = false) -> WindowItem {
        WindowItem(windowIdentifier: identifier, ownerProcessIdentifier: 42, ownerName: "Fixture", title: "Window \(identifier)", screenCaptureIdentifier: UInt32(identifier), isMinimized: minimized, availability: minimized ? .minimized : .available)
    }
}

@MainActor
private final class PracticeTestEventTapBackend: SwitcherOverlayEventTapBackend {
    func install(handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool) -> (any SwitcherOverlayEventTapConnection)? { nil }
}

@MainActor
private final class PracticeTestThumbnailCapturer: WindowThumbnailCapturing {
    let succeeds: Bool
    private(set) var captureCount = 0
    init(succeeds: Bool = true) { self.succeeds = succeeds }
    func prepareForRefresh(windowIdentifiers: [CGWindowID]) async {}
    func prepareForRefresh(windowIdentifier: CGWindowID) async {}
    func captureThumbnail(for window: WindowItem, viewportPixelSize: CGSize) async -> WindowThumbnail? {
        captureCount += 1
        guard succeeds else { return nil }
        return WindowThumbnail(pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/az4h6cAAAAASUVORK5CYII=")!, pixelWidth: 1, pixelHeight: 1)
    }
}
