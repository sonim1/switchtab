import AppKit
import Combine
import Foundation
@testable import SwitchTab

enum WindowThumbnailTests {
    static func run() async throws {
        try testCaptureViewportTracksOverlayScale()
        try testAspectFillCaptureSizingIsBounded()
        try await testThumbnailStoreReplacesCachedImage()
        try await testThumbnailStoreCachesDecodedImage()
        try await testThumbnailStoreDoesNotInvalidateUnchangedBatch()
        try await testThumbnailStoreInvalidatesDecodedImageWhenThumbnailChanges()
        try await testThumbnailStorePublishesOnceForBatchUpdate()
        try await testThumbnailStoreDoesNotPublishUnchangedBatch()
        try await testThumbnailStoreRemovesStaleThumbnailsOnBatchUpdate()
        try await testThumbnailStoreRemovesStaleDecodedImagesOnBatchUpdate()
        try await testThumbnailLoaderRefreshesOnlyWhenScreenRecordingIsGranted()
        try await testThumbnailLoaderPreparesOnlyCapturableScreenCaptureIdentifiers()
        try await testThumbnailLoaderClearsStaleThumbnailsWhenScreenRecordingIsBlocked()
        try await testThumbnailLoaderSkipsPreparationWhenNoWindowsAreCapturable()
        try await testThumbnailStoreInvalidatesUndecodableMarkerWhenThumbnailChanges()
        try await testThumbnailStoreDoesNotCacheMissingThumbnailAsUndecodable()
    }

    static func testCaptureViewportTracksOverlayScale() throws {
        let cases: [(OverlaySizeScale, CGSize)] = [
            (OverlaySizeScale(0.7), CGSize(width: 168, height: 116)),
            (.default, CGSize(width: 240, height: 165)),
            (OverlaySizeScale(1.5), CGSize(width: 360, height: 248))
        ]

        for (scale, expected) in cases {
            let thumbnailSize = SwitcherOverlayLayoutMetrics.metrics(for: scale).thumbnailSize
            let actual = WindowThumbnailCaptureSizing.viewportPixelSize(for: thumbnailSize)
            try expectEqual(actual, expected)
        }
    }

    static func testAspectFillCaptureSizingIsBounded() throws {
        let cases: [(CGRect, CGSize, WindowThumbnailPixelSize)] = [
            (
                CGRect(x: 0, y: 0, width: 1_600, height: 900),
                CGSize(width: 240, height: 165),
                WindowThumbnailPixelSize(width: 294, height: 165)
            ),
            (
                CGRect(x: 0, y: 0, width: 900, height: 1_600),
                CGSize(width: 240, height: 165),
                WindowThumbnailPixelSize(width: 240, height: 427)
            ),
            (
                CGRect(x: 0, y: 0, width: 5_000, height: 500),
                CGSize(width: 240, height: 165),
                WindowThumbnailPixelSize(width: 480, height: 48)
            ),
            (
                CGRect(x: 0, y: 0, width: 100, height: 60),
                CGSize(width: 240, height: 165),
                WindowThumbnailPixelSize(width: 100, height: 60)
            )
        ]

        for (sourceFrame, viewportPixelSize, expected) in cases {
            let actual = WindowThumbnailCaptureSizing.targetPixelSize(
                for: sourceFrame,
                viewportPixelSize: viewportPixelSize
            )
            try expectEqual(actual, expected)
        }
    }

    @MainActor
    static func testThumbnailStoreReplacesCachedImage() throws {
        let store = WindowThumbnailStore()

        store.setThumbnails(["42-7": WindowThumbnail(pngData: onePixelPNG(red: 1, green: 0, blue: 0))])
        guard let firstImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected decoded thumbnail image")
        }

        store.setThumbnails(["42-7": WindowThumbnail(pngData: onePixelPNG(red: 0, green: 0, blue: 1))])

        guard let secondImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected updated decoded thumbnail image")
        }
        try expectTrue(firstImage !== secondImage, "Expected changed thumbnail to replace decoded image")
    }

    @MainActor
    static func testThumbnailStoreCachesDecodedImage() throws {
        let store = WindowThumbnailStore()
        let pngData = Data(base64Encoded: onePixelPNGBase64)!

        store.setThumbnails(["42-7": WindowThumbnail(pngData: pngData)])

        guard let firstImage = store.image(for: "42-7"),
              let secondImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected decoded thumbnail image")
        }
        try expectTrue(firstImage === secondImage, "Expected decoded image to be cached")
    }

    @MainActor
    static func testThumbnailStoreDoesNotInvalidateUnchangedBatch() throws {
        let store = WindowThumbnailStore()
        let thumbnail = WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)

        store.setThumbnails(["42-7": thumbnail])
        guard let firstImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected decoded thumbnail image")
        }

        store.setThumbnails(["42-7": thumbnail])

        guard let secondImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected decoded thumbnail image")
        }
        try expectTrue(firstImage === secondImage, "Expected unchanged thumbnail to keep decoded image cache")
    }

    @MainActor
    static func testThumbnailStoreInvalidatesDecodedImageWhenThumbnailChanges() throws {
        let store = WindowThumbnailStore()

        store.setThumbnails(["42-7": WindowThumbnail(pngData: onePixelPNG(red: 1, green: 0, blue: 0))])
        guard let firstImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected decoded thumbnail image")
        }

        store.setThumbnails(["42-7": WindowThumbnail(pngData: onePixelPNG(red: 0, green: 0, blue: 1))])

        guard let secondImage = store.image(for: "42-7") else {
            throw TestFailure.failed("Expected updated decoded thumbnail image")
        }
        try expectTrue(firstImage !== secondImage, "Expected changed thumbnail to refresh decoded image cache")
    }

    @MainActor
    static func testThumbnailStorePublishesOnceForBatchUpdate() throws {
        let store = WindowThumbnailStore()
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
        }

        store.setThumbnails([
            "42-7": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!),
            "42-8": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])

        try expectEqual(publishCount, 1)
        try expectTrue(store.image(for: "42-7") != nil)
        try expectTrue(store.image(for: "42-8") != nil)
    }

    @MainActor
    static func testThumbnailStoreDoesNotPublishUnchangedBatch() throws {
        let store = WindowThumbnailStore()
        let thumbnails = [
            "42-7": WindowThumbnail(pngData: Data("first".utf8)),
            "42-8": WindowThumbnail(pngData: Data("second".utf8))
        ]
        store.setThumbnails(thumbnails)
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer {
            cancellable.cancel()
        }

        store.setThumbnails(thumbnails)

        try expectEqual(publishCount, 0)
    }

    @MainActor
    static func testThumbnailStoreRemovesStaleThumbnailsOnBatchUpdate() throws {
        let store = WindowThumbnailStore()
        store.setThumbnails(["42-7": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)])

        store.setThumbnails([
            "42-8": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])

        try expectEqual(store.image(for: "42-7"), nil)
        try expectTrue(store.image(for: "42-8") != nil)
    }

    @MainActor
    static func testThumbnailStoreRemovesStaleDecodedImagesOnBatchUpdate() throws {
        let store = WindowThumbnailStore()
        store.setThumbnails([
            "42-7": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])
        try expectTrue(store.image(for: "42-7") != nil)

        store.setThumbnails([
            "42-8": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])

        try expectEqual(store.image(for: "42-7"), nil)
    }

    @MainActor
    static func testThumbnailLoaderRefreshesOnlyWhenScreenRecordingIsGranted() async throws {
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            7: WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let window = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            screenCaptureIdentifier: 100,
            isMinimized: false,
            availability: .available
        )

        loader.refresh(
            windows: [window],
            permissionState: PermissionState(accessibility: .granted, screenRecording: .missing)
        )
        await loader.waitForCurrentRefresh()

        try expectEqual(store.image(for: window.id), nil)
        try expectEqual(capturer.requestedWindowIdentifiers, [])

        loader.refresh(
            windows: [window],
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted),
            viewportPixelSize: CGSize(width: 360, height: 248)
        )
        await loader.waitForCurrentRefresh()

        try expectTrue(store.image(for: window.id) != nil)
        try expectEqual(capturer.prepareCount, 1)
        try expectEqual(capturer.preparedWindowIdentifiers, [])
        try expectEqual(capturer.singlePreparedWindowIdentifiers, [100])
        try expectEqual(capturer.requestedWindowIdentifiers, [7])
        try expectEqual(capturer.requestedViewportPixelSizes, [CGSize(width: 360, height: 248)])
    }

    @MainActor
    static func testThumbnailLoaderPreparesOnlyCapturableScreenCaptureIdentifiers() async throws {
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            7: WindowThumbnail(pngData: Data("first".utf8)),
            9: WindowThumbnail(pngData: Data("second".utf8))
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let missingCaptureID = WindowItem(
            windowIdentifier: 6,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "No Capture ID",
            screenCaptureIdentifier: nil,
            isMinimized: false,
            availability: .available
        )
        let firstCapturable = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            screenCaptureIdentifier: 100,
            isMinimized: false,
            availability: .available
        )
        let minimized = WindowItem(
            windowIdentifier: 8,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Minimized",
            screenCaptureIdentifier: 200,
            isMinimized: true,
            availability: .minimized
        )
        let secondCapturable = WindowItem(
            windowIdentifier: 9,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Ideas",
            screenCaptureIdentifier: 300,
            isMinimized: false,
            availability: .available
        )

        loader.refresh(
            windows: [missingCaptureID, firstCapturable, minimized, secondCapturable],
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.preparedWindowIdentifiers, [[100, 300]])
        try expectEqual(capturer.requestedWindowIdentifiers, [7, 9])
    }

    @MainActor
    static func testThumbnailLoaderClearsStaleThumbnailsWhenScreenRecordingIsBlocked() async throws {
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [:])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let window = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            screenCaptureIdentifier: 100,
            isMinimized: false,
            availability: .available
        )
        store.setThumbnails([window.id: WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)])

        loader.refresh(
            windows: [window],
            permissionState: PermissionState(accessibility: .granted, screenRecording: .missing)
        )
        await loader.waitForCurrentRefresh()

        try expectEqual(store.image(for: window.id), nil)
        try expectEqual(capturer.prepareCount, 0)
        try expectEqual(capturer.requestedWindowIdentifiers, [])
    }

    @MainActor
    static func testThumbnailLoaderSkipsPreparationWhenNoWindowsAreCapturable() async throws {
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [:])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let uncapturableWindow = WindowItem(
            windowIdentifier: 7,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Project",
            screenCaptureIdentifier: nil,
            isMinimized: false,
            availability: .available
        )
        let minimizedWindow = WindowItem(
            windowIdentifier: 8,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Minimized",
            screenCaptureIdentifier: 200,
            isMinimized: true,
            availability: .minimized
        )

        loader.refresh(
            windows: [uncapturableWindow, minimizedWindow],
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.prepareCount, 0)
        try expectEqual(capturer.requestedWindowIdentifiers, [])
    }

    @MainActor
    static func testThumbnailStoreInvalidatesUndecodableMarkerWhenThumbnailChanges() throws {
        let store = WindowThumbnailStore()
        store.setThumbnails(["42-7": WindowThumbnail(pngData: Data("not png".utf8))])

        try expectEqual(store.image(for: "42-7"), nil)

        store.setThumbnails([
            "42-7": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])

        try expectTrue(store.image(for: "42-7") != nil)
    }

    @MainActor
    static func testThumbnailStoreDoesNotCacheMissingThumbnailAsUndecodable() throws {
        let store = WindowThumbnailStore()

        try expectEqual(store.image(for: "42-7"), nil)

        store.setThumbnails([
            "42-7": WindowThumbnail(pngData: Data(base64Encoded: onePixelPNGBase64)!)
        ])

        try expectTrue(store.image(for: "42-7") != nil)
    }

    private static let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/az4h6cAAAAASUVORK5CYII="

    private static func onePixelPNG(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.setColor(
            NSColor(deviceRed: red, green: green, blue: blue, alpha: 1),
            atX: 0,
            y: 0
        )
        return bitmap.representation(using: .png, properties: [:])!
    }
}

@MainActor
final class FakeWindowThumbnailCapturer: WindowThumbnailCapturing {
    let thumbnails: [Int: WindowThumbnail]
    private(set) var prepareCount = 0
    private(set) var preparedWindowIdentifiers: [[UInt32]] = []
    private(set) var singlePreparedWindowIdentifiers: [UInt32] = []
    private(set) var requestedWindowIdentifiers: [Int] = []
    private(set) var requestedViewportPixelSizes: [CGSize] = []

    init(thumbnails: [Int: WindowThumbnail]) {
        self.thumbnails = thumbnails
    }

    func prepareForRefresh(windowIdentifiers: [UInt32]) async {
        prepareCount += 1
        preparedWindowIdentifiers.append(windowIdentifiers)
    }

    func prepareForRefresh(windowIdentifier: UInt32) async {
        prepareCount += 1
        singlePreparedWindowIdentifiers.append(windowIdentifier)
    }

    func captureThumbnail(for window: WindowItem, viewportPixelSize: CGSize) async -> WindowThumbnail? {
        requestedWindowIdentifiers.append(window.windowIdentifier)
        requestedViewportPixelSizes.append(viewportPixelSize)
        return thumbnails[window.windowIdentifier]
    }
}
