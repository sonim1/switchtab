import AppKit
@testable import SwitchTab
import XCTest

@MainActor
final class WindowThumbnailEvictionTests: XCTestCase {
    func testSelectedDemandRecapturesEvictedSuccessfulThumbnail() async throws {
        let windows = (1...17).map(makeWindow)
        let store = WindowThumbnailStore()
        let capturer = EvictionTestCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.refresh(windows: windows, permissionState: grantedPermissions)
        await loader.waitForCurrentRefresh()

        XCTAssertEqual(capturer.capturedWindowIDs.count, 17)
        XCTAssertEqual(store.cachedEntryCount, 16)
        XCTAssertNil(store.image(for: windows[0].id))
        XCTAssertNotNil(store.image(for: windows[16].id))

        loader.requestThumbnail(for: windows[0], priority: .visible)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 17)

        loader.requestThumbnail(for: windows[0], priority: .selected)
        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 18)
        XCTAssertEqual(capturer.capturedWindowIDs.last, windows[0].id)
        XCTAssertNotNil(store.image(for: windows[0].id))
        XCTAssertEqual(store.cachedEntryCount, 16)

        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 18)
    }

    func testSelectedDemandRecapturesThumbnailRemovedByWarningTrim() async throws {
        let windows = (1...9).map(makeWindow)
        let store = WindowThumbnailStore()
        let capturer = EvictionTestCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.refresh(windows: windows, permissionState: grantedPermissions)
        await loader.waitForCurrentRefresh()

        store.trimForMemoryPressure()
        XCTAssertEqual(store.cachedEntryCount, 8)
        XCTAssertNil(store.image(for: windows[0].id))

        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 10)
        XCTAssertNotNil(store.image(for: windows[0].id))
    }

    func testFailedRecaptureRemainsSuppressedForCurrentGeneration() async throws {
        let windows = (1...2).map(makeWindow)
        let store = WindowThumbnailStore(maximumEntryCount: 1)
        let capturer = EvictionTestCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.refresh(windows: windows, permissionState: grantedPermissions)
        await loader.waitForCurrentRefresh()

        capturer.failedWindowIDs.insert(windows[0].id)
        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 3)
        XCTAssertNil(store.image(for: windows[0].id))

        capturer.failedWindowIDs.removeAll()
        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 3)
        XCTAssertNil(store.image(for: windows[0].id))

        loader.beginRefresh(permissionState: grantedPermissions, preservingCachedThumbnails: true)
        loader.requestThumbnail(for: windows[0], priority: .selected)
        await loader.waitForCurrentRefresh()
        XCTAssertEqual(capturer.capturedWindowIDs.count, 4)
        XCTAssertNotNil(store.image(for: windows[0].id))
    }

    private var grantedPermissions: PermissionState {
        PermissionState(accessibility: .granted, screenRecording: .granted)
    }

    private func makeWindow(_ identifier: Int) -> WindowItem {
        WindowItem(
            windowIdentifier: identifier,
            ownerProcessIdentifier: 42,
            ownerName: "Fixture",
            title: "Window \(identifier)",
            screenCaptureIdentifier: UInt32(identifier),
            isMinimized: false,
            availability: .available
        )
    }
}

@MainActor
private final class EvictionTestCapturer: WindowThumbnailCapturing {
    private(set) var capturedWindowIDs: [String] = []
    var failedWindowIDs: Set<String> = []

    func prepareForRefresh(windowIdentifiers: [CGWindowID]) async {}
    func prepareForRefresh(windowIdentifier: CGWindowID) async {}

    func captureThumbnail(for window: WindowItem, viewportPixelSize: CGSize) async -> WindowThumbnail? {
        capturedWindowIDs.append(window.id)
        guard !failedWindowIDs.contains(window.id) else { return nil }
        return WindowThumbnail(
            pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/az4h6cAAAAASUVORK5CYII=")!,
            pixelWidth: 1,
            pixelHeight: 1
        )
    }
}
