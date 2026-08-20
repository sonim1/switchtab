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
        try await testThumbnailStoreEvictsLeastRecentlyUsedEntryAtCountLimit()
        try await testThumbnailStoreEvictsEntriesAtByteLimit()
        try await testThumbnailStoreTrimsForMemoryPressureAndAllowsReinsertion()
        try await testThumbnailStoreDoesNotPublishForUnchangedIncrementalThumbnail()
        try await testThumbnailStoreDoesNotPublishWhenMemoryPressureNeedsNoTrim()
        try testThumbnailRequestQueueIsBoundedAndBatched()
        try testThumbnailRequestQueueCoalescesAndPrioritizesSelection()
        try await testThumbnailLoaderCapturesOnlyRequestedWindowsInBoundedBatches()
        try await testThumbnailLoaderCoalescesDuplicateDemand()
        try await testThumbnailLoaderSkipsAlreadyCachedDemand()
        try await testThumbnailLoaderLeavesPlaceholderWhenCaptureReturnsNil()
        try await testThumbnailLoaderCancelDiscardsInFlightCapture()
        try await testThumbnailLoaderDiscardsStaleCaptureBeforeStartingNextGeneration()
        try await testThumbnailLoaderPreservesCacheAcrossRetainedRefresh()
        try await testThumbnailLoaderPreservingCancelDropsInFlightWorkButKeepsCompletedCache()
        try await testThumbnailLoaderClearsPreservedCacheWhenPreviewPermissionIsBlocked()
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
    static func testThumbnailStoreEvictsLeastRecentlyUsedEntryAtCountLimit() throws {
        let store = WindowThumbnailStore(maximumEntryCount: 2, maximumEstimatedCost: 1_000)
        store.setThumbnail(WindowThumbnail(pngData: Data("a".utf8)), for: "a")
        store.setThumbnail(WindowThumbnail(pngData: Data("b".utf8)), for: "b")
        _ = store.image(for: "a")

        store.setThumbnail(WindowThumbnail(pngData: Data("c".utf8)), for: "c")

        try expectEqual(store.cachedKeys, ["a", "c"])
        try expectEqual(store.cachedEntryCount, 2)
    }

    @MainActor
    static func testThumbnailStoreEvictsEntriesAtByteLimit() throws {
        let store = WindowThumbnailStore(maximumEntryCount: 10, maximumEstimatedCost: 33)
        let first = WindowThumbnail(pngData: Data([0]), pixelWidth: 2, pixelHeight: 2)
        let second = WindowThumbnail(pngData: Data([1]), pixelWidth: 2, pixelHeight: 2)

        store.setThumbnail(first, for: "first")
        store.setThumbnail(second, for: "second")

        try expectEqual(store.cachedKeys, ["second"])
        try expectEqual(store.estimatedCost, 17)
    }

    @MainActor
    static func testThumbnailStoreTrimsForMemoryPressureAndAllowsReinsertion() throws {
        let store = WindowThumbnailStore(
            maximumEntryCount: 4,
            maximumEstimatedCost: 1_000,
            memoryPressureEntryCount: 2,
            memoryPressureEstimatedCost: 500
        )
        for key in ["a", "b", "c", "d"] {
            store.setThumbnail(WindowThumbnail(pngData: Data(key.utf8)), for: key)
        }

        store.trimForMemoryPressure()
        try expectEqual(store.cachedKeys, ["c", "d"])

        store.setThumbnail(WindowThumbnail(pngData: Data("a2".utf8)), for: "a")
        try expectEqual(store.cachedKeys, ["a", "c", "d"])
    }

    @MainActor
    static func testThumbnailStoreDoesNotPublishForUnchangedIncrementalThumbnail() throws {
        let store = WindowThumbnailStore()
        let thumbnail = WindowThumbnail(pngData: Data("preview".utf8))
        store.setThumbnail(thumbnail, for: "window")
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        store.setThumbnail(thumbnail, for: "window")

        try expectEqual(publishCount, 0)
    }

    @MainActor
    static func testThumbnailStoreDoesNotPublishWhenMemoryPressureNeedsNoTrim() throws {
        let store = WindowThumbnailStore(
            maximumEntryCount: 4,
            maximumEstimatedCost: 1_000,
            memoryPressureEntryCount: 2,
            memoryPressureEstimatedCost: 500
        )
        store.setThumbnail(WindowThumbnail(pngData: Data("a".utf8)), for: "a")
        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        store.trimForMemoryPressure()

        try expectEqual(publishCount, 0)
        try expectEqual(store.cachedKeys, ["a"])
    }

    static func testThumbnailRequestQueueIsBoundedAndBatched() throws {
        var queue = WindowThumbnailRequestQueue(maximumCount: 64, batchSize: 8)
        for identifier in 0..<100 {
            queue.enqueue(makeWindow(identifier), priority: .visible)
        }

        try expectEqual(queue.count, 64)
        try expectEqual(queue.dequeueBatch().count, 8)
        try expectEqual(queue.count, 56)
    }

    static func testThumbnailRequestQueueCoalescesAndPrioritizesSelection() throws {
        var queue = WindowThumbnailRequestQueue(maximumCount: 3, batchSize: 3)
        queue.enqueue(makeWindow(1), priority: .visible)
        queue.enqueue(makeWindow(2), priority: .visible)
        queue.enqueue(makeWindow(1), priority: .selected)
        queue.enqueue(makeWindow(3), priority: .visible)
        queue.enqueue(makeWindow(4), priority: .selected)

        let batch = queue.dequeueBatch()
        try expectEqual(batch.map(\.windowIdentifier), [4, 1, 3])
    }

    @MainActor
    static func testThumbnailLoaderCapturesOnlyRequestedWindowsInBoundedBatches() async throws {
        let windows = (0..<10).map(makeWindow)
        let thumbnails = Dictionary(uniqueKeysWithValues: windows.map {
            ($0.windowIdentifier, WindowThumbnail(pngData: Data("\($0.windowIdentifier)".utf8)))
        })
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: thumbnails)
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        for window in windows {
            loader.requestThumbnail(for: window, priority: .visible)
        }
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.preparedWindowIdentifiers, [
            windows.prefix(8).compactMap(\.screenCaptureIdentifier),
            windows.suffix(2).compactMap(\.screenCaptureIdentifier)
        ])
        try expectEqual(capturer.maximumConcurrentCaptureCount, 1)
        try expectEqual(store.cachedEntryCount, 10)
    }

    @MainActor
    static func testThumbnailLoaderCoalescesDuplicateDemand() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            window.windowIdentifier: WindowThumbnail(pngData: Data("preview".utf8))
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        loader.requestThumbnail(for: window, priority: .visible)
        loader.requestThumbnail(for: window, priority: .selected)
        loader.requestThumbnail(for: window, priority: .visible)
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [7])
    }

    @MainActor
    static func testThumbnailLoaderSkipsAlreadyCachedDemand() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            window.windowIdentifier: WindowThumbnail(pngData: Data("preview".utf8))
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        loader.requestThumbnail(for: window, priority: .visible)
        await loader.waitForCurrentRefresh()
        loader.requestThumbnail(for: window, priority: .selected)
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [7])
    }

    @MainActor
    static func testThumbnailLoaderLeavesPlaceholderWhenCaptureReturnsNil() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [:])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )

        loader.requestThumbnail(for: window, priority: .visible)
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [7])
        try expectEqual(store.cachedEntryCount, 0)
    }

    @MainActor
    static func testThumbnailLoaderCancelDiscardsInFlightCapture() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = PausingWindowThumbnailCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .granted)
        )
        loader.requestThumbnail(for: window, priority: .visible)
        await capturer.waitUntilCaptureCount(1)

        loader.cancel()
        capturer.resumeFirstCapture(with: WindowThumbnail(pngData: Data("stale".utf8)))
        await loader.waitForCurrentRefresh()

        try expectEqual(store.cachedEntryCount, 0)
    }

    @MainActor
    static func testThumbnailLoaderDiscardsStaleCaptureBeforeStartingNextGeneration() async throws {
        let firstWindow = makeWindow(1)
        let secondWindow = makeWindow(2)
        let store = WindowThumbnailStore()
        let capturer = PausingWindowThumbnailCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let permissionState = PermissionState(accessibility: .granted, screenRecording: .granted)

        loader.beginRefresh(permissionState: permissionState)
        loader.requestThumbnail(for: firstWindow, priority: .visible)
        await capturer.waitUntilCaptureCount(1)

        loader.beginRefresh(permissionState: permissionState)
        loader.requestThumbnail(for: secondWindow, priority: .selected)
        capturer.resumeFirstCapture(with: WindowThumbnail(pngData: Data("stale".utf8)))
        await capturer.waitUntilCaptureCount(2)
        capturer.resumeFirstCapture(with: WindowThumbnail(pngData: Data("current".utf8)))
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [1, 2])
        try expectEqual(capturer.maximumConcurrentCaptureCount, 1)
        try expectEqual(store.cachedKeys, [secondWindow.id])
    }

    @MainActor
    static func testThumbnailLoaderPreservesCacheAcrossRetainedRefresh() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            window.windowIdentifier: WindowThumbnail(pngData: Data("preview".utf8))
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let permissionState = PermissionState(accessibility: .granted, screenRecording: .granted)

        loader.beginRefresh(permissionState: permissionState)
        loader.requestThumbnail(for: window, priority: .selected)
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [7])
        try expectEqual(store.cachedKeys, [window.id])

        loader.beginRefresh(
            permissionState: permissionState,
            preservingCachedThumbnails: true
        )
        loader.requestThumbnail(for: window, priority: .selected)
        await loader.waitForCurrentRefresh()

        try expectEqual(capturer.requestedWindowIdentifiers, [7])
        try expectEqual(store.cachedKeys, [window.id])
    }

    @MainActor
    static func testThumbnailLoaderPreservingCancelDropsInFlightWorkButKeepsCompletedCache() async throws {
        let cachedWindow = makeWindow(7)
        let inFlightWindow = makeWindow(8)
        let store = WindowThumbnailStore()
        store.setThumbnail(WindowThumbnail(pngData: Data("cached".utf8)), for: cachedWindow.id)
        let capturer = PausingWindowThumbnailCapturer()
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)
        let permissionState = PermissionState(accessibility: .granted, screenRecording: .granted)

        loader.beginRefresh(
            permissionState: permissionState,
            preservingCachedThumbnails: true
        )
        loader.requestThumbnail(for: inFlightWindow, priority: .selected)
        await capturer.waitUntilCaptureCount(1)

        loader.cancel(preservingCachedThumbnails: true)
        capturer.resumeFirstCapture(with: WindowThumbnail(pngData: Data("stale".utf8)))
        await loader.waitForCurrentRefresh()

        try expectEqual(store.cachedKeys, [cachedWindow.id])
    }

    @MainActor
    static func testThumbnailLoaderClearsPreservedCacheWhenPreviewPermissionIsBlocked() async throws {
        let window = makeWindow(7)
        let store = WindowThumbnailStore()
        store.setThumbnail(WindowThumbnail(pngData: Data("cached".utf8)), for: window.id)
        let capturer = FakeWindowThumbnailCapturer(thumbnails: [
            window.windowIdentifier: WindowThumbnail(pngData: Data("preview".utf8))
        ])
        let loader = WindowThumbnailLoader(store: store, capturer: capturer)

        loader.beginRefresh(
            permissionState: PermissionState(accessibility: .granted, screenRecording: .missing),
            preservingCachedThumbnails: true
        )
        loader.requestThumbnail(for: window, priority: .selected)
        await loader.waitForCurrentRefresh()

        try expectEqual(store.cachedKeys, [])
        try expectEqual(capturer.requestedWindowIdentifiers, [])
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

    private static func makeWindow(_ identifier: Int) -> WindowItem {
        WindowItem(
            windowIdentifier: identifier,
            ownerProcessIdentifier: 42,
            ownerName: "Notes",
            title: "Window \(identifier)",
            screenCaptureIdentifier: UInt32(identifier + 1_000),
            isMinimized: false,
            availability: .available
        )
    }

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
    private(set) var activeCaptureCount = 0
    private(set) var maximumConcurrentCaptureCount = 0

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
        activeCaptureCount += 1
        maximumConcurrentCaptureCount = max(maximumConcurrentCaptureCount, activeCaptureCount)
        defer {
            activeCaptureCount -= 1
        }
        requestedWindowIdentifiers.append(window.windowIdentifier)
        requestedViewportPixelSizes.append(viewportPixelSize)
        await Task.yield()
        return thumbnails[window.windowIdentifier]
    }
}

@MainActor
final class PausingWindowThumbnailCapturer: WindowThumbnailCapturing {
    private var continuations: [CheckedContinuation<WindowThumbnail?, Never>] = []
    private(set) var requestedWindowIdentifiers: [Int] = []
    private(set) var activeCaptureCount = 0
    private(set) var maximumConcurrentCaptureCount = 0

    func prepareForRefresh(windowIdentifiers _: [UInt32]) async {}

    func prepareForRefresh(windowIdentifier _: UInt32) async {}

    func captureThumbnail(for window: WindowItem, viewportPixelSize _: CGSize) async -> WindowThumbnail? {
        requestedWindowIdentifiers.append(window.windowIdentifier)
        activeCaptureCount += 1
        maximumConcurrentCaptureCount = max(maximumConcurrentCaptureCount, activeCaptureCount)
        defer {
            activeCaptureCount -= 1
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilCaptureCount(_ count: Int) async {
        while requestedWindowIdentifiers.count < count {
            await Task.yield()
        }
    }

    func resumeFirstCapture(with thumbnail: WindowThumbnail?) {
        continuations.removeFirst().resume(returning: thumbnail)
    }
}
