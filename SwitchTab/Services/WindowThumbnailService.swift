import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public struct WindowThumbnail: Equatable, Sendable {
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(pngData: Data, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.pngData = pngData
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
    }

    var estimatedCost: Int {
        pngData.count + (pixelWidth * pixelHeight * 4)
    }
}

internal struct WindowThumbnailPixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

internal enum WindowThumbnailCaptureSizing {
    static let qualityScale: CGFloat = 1.5
    static let maximumLongEdge: CGFloat = 480

    static func viewportPixelSize(for thumbnailPointSize: CGSize) -> CGSize {
        CGSize(
            width: max(1, (thumbnailPointSize.width * qualityScale).rounded(.up)),
            height: max(1, (thumbnailPointSize.height * qualityScale).rounded(.up))
        )
    }

    static func targetPixelSize(
        for sourceFrame: CGRect,
        viewportPixelSize: CGSize
    ) -> WindowThumbnailPixelSize {
        let sourceSize = CGSize(
            width: max(sourceFrame.width, 1),
            height: max(sourceFrame.height, 1)
        )
        let viewportSize = CGSize(
            width: max(viewportPixelSize.width, 1),
            height: max(viewportPixelSize.height, 1)
        )
        let aspectFillScale = max(
            viewportSize.width / sourceSize.width,
            viewportSize.height / sourceSize.height
        )
        let scale = min(
            aspectFillScale,
            1,
            maximumLongEdge / max(sourceSize.width, sourceSize.height)
        )
        let maximumPixelEdge = Int(maximumLongEdge)

        return WindowThumbnailPixelSize(
            width: min(maximumPixelEdge, max(1, Int((sourceSize.width * scale).rounded(.up)))),
            height: min(maximumPixelEdge, max(1, Int((sourceSize.height * scale).rounded(.up))))
        )
    }
}

public protocol WindowThumbnailCapturing: Sendable {
    func prepareForRefresh(windowIdentifiers: [CGWindowID]) async
    func prepareForRefresh(windowIdentifier: CGWindowID) async
    func captureThumbnail(for window: WindowItem, viewportPixelSize: CGSize) async -> WindowThumbnail?
}

@MainActor
public final class WindowThumbnailStore: ObservableObject {
    private enum CachedThumbnailImage {
        case decoded(NSImage)
        case undecodable
    }

    private var thumbnails: [String: WindowThumbnail] = [:]
    private var decodedImages: [String: CachedThumbnailImage] = [:]
    private var accessOrder: [String] = []
    private let maximumEntryCount: Int
    private let maximumEstimatedCost: Int
    private let memoryPressureEntryCount: Int
    private let memoryPressureEstimatedCost: Int

    public init(
        maximumEntryCount: Int = 16,
        maximumEstimatedCost: Int = 24 * 1_024 * 1_024,
        memoryPressureEntryCount: Int = 8,
        memoryPressureEstimatedCost: Int = 12 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.maximumEstimatedCost = max(1, maximumEstimatedCost)
        self.memoryPressureEntryCount = max(0, min(memoryPressureEntryCount, maximumEntryCount))
        self.memoryPressureEstimatedCost = max(0, min(memoryPressureEstimatedCost, maximumEstimatedCost))
    }

    var cachedKeys: [String] {
        thumbnails.keys.sorted()
    }

    var cachedEntryCount: Int {
        thumbnails.count
    }

    var estimatedCost: Int {
        thumbnails.values.reduce(0) { $0 + $1.estimatedCost }
    }

    func containsThumbnail(for key: String) -> Bool {
        thumbnails[key] != nil
    }

    func thumbnail(for key: String) -> WindowThumbnail? {
        thumbnails[key]
    }

    public func image(for key: String) -> NSImage? {
        touch(key)
        if let cachedImage = decodedImages[key] {
            switch cachedImage {
            case .decoded(let image):
                return image
            case .undecodable:
                return nil
            }
        }

        guard let pngData = thumbnails[key]?.pngData else {
            return nil
        }

        guard let image = NSImage(data: pngData) else {
            decodedImages[key] = .undecodable
            return nil
        }

        decodedImages[key] = .decoded(image)
        return image
    }

    public func setThumbnail(_ thumbnail: WindowThumbnail, for key: String) {
        if thumbnails[key] == thumbnail {
            touch(key)
            return
        }

        objectWillChange.send()
        thumbnails[key] = thumbnail
        decodedImages.removeValue(forKey: key)
        touch(key)
        evictIfNeeded(
            maximumEntryCount: maximumEntryCount,
            maximumEstimatedCost: maximumEstimatedCost
        )
    }

    public func setThumbnails(_ thumbnailsByKey: [String: WindowThumbnail]) {
        guard !thumbnailsByKey.isEmpty else {
            clear()
            return
        }

        guard thumbnailsByKey != thumbnails else {
            return
        }

        objectWillChange.send()
        if !decodedImages.isEmpty {
            // Keep decoded images only for keys whose thumbnail is unchanged.
            decodedImages = decodedImages.filter { key, _ in
                thumbnailsByKey[key] == thumbnails[key]
            }
        }
        thumbnails = thumbnailsByKey
        accessOrder = accessOrder.filter { thumbnailsByKey[$0] != nil }
        for key in thumbnailsByKey.keys.sorted() where !accessOrder.contains(key) {
            accessOrder.append(key)
        }
        evictIfNeeded(
            maximumEntryCount: maximumEntryCount,
            maximumEstimatedCost: maximumEstimatedCost
        )
    }

    public func trimForMemoryPressure() {
        guard thumbnails.count > memoryPressureEntryCount
                || estimatedCost > memoryPressureEstimatedCost else {
            return
        }

        objectWillChange.send()
        evictIfNeeded(
            maximumEntryCount: memoryPressureEntryCount,
            maximumEstimatedCost: memoryPressureEstimatedCost
        )
    }

    public func removeThumbnail(for key: String) {
        guard thumbnails[key] != nil
                || decodedImages[key] != nil
                || accessOrder.contains(key) else {
            return
        }

        objectWillChange.send()
        thumbnails.removeValue(forKey: key)
        decodedImages.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    public func removeThumbnails(ownerProcessIdentifier: Int) {
        let processPrefix = "\(ownerProcessIdentifier)-"
        let keys = Set(
            thumbnails.keys.filter { $0.hasPrefix(processPrefix) }
                + decodedImages.keys.filter { $0.hasPrefix(processPrefix) }
                + accessOrder.filter { $0.hasPrefix(processPrefix) }
        )
        guard !keys.isEmpty else {
            return
        }

        objectWillChange.send()
        for key in keys {
            thumbnails.removeValue(forKey: key)
            decodedImages.removeValue(forKey: key)
        }
        accessOrder.removeAll { keys.contains($0) }
    }

    public func clear() {
        guard !thumbnails.isEmpty || !decodedImages.isEmpty else {
            return
        }

        objectWillChange.send()
        thumbnails.removeAll(keepingCapacity: true)
        decodedImages.removeAll(keepingCapacity: true)
        accessOrder.removeAll(keepingCapacity: true)
    }

    private func touch(_ key: String) {
        guard thumbnails[key] != nil else {
            return
        }

        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded(maximumEntryCount: Int, maximumEstimatedCost: Int) {
        while thumbnails.count > maximumEntryCount || estimatedCost > maximumEstimatedCost {
            guard let key = accessOrder.first else {
                thumbnails.removeAll(keepingCapacity: true)
                decodedImages.removeAll(keepingCapacity: true)
                return
            }

            accessOrder.removeFirst()
            thumbnails.removeValue(forKey: key)
            decodedImages.removeValue(forKey: key)
        }
    }
}

enum WindowThumbnailRequestPriority: Equatable, Sendable {
    case visible
    case selected
}

struct WindowThumbnailRequestQueue: Sendable {
    private let maximumCount: Int
    private let batchSize: Int
    private var selected: [WindowItem] = []
    private var visible: [WindowItem] = []

    init(maximumCount: Int = 64, batchSize: Int = 8) {
        self.maximumCount = max(1, maximumCount)
        self.batchSize = max(1, min(batchSize, maximumCount))
    }

    var count: Int {
        selected.count + visible.count
    }

    mutating func enqueue(_ window: WindowItem, priority: WindowThumbnailRequestPriority) {
        let wasSelected = remove(windowID: window.id, from: &selected)
        let wasVisible = remove(windowID: window.id, from: &visible)

        switch priority {
        case .selected:
            if count >= maximumCount {
                if !visible.isEmpty {
                    visible.removeFirst()
                } else if !selected.isEmpty {
                    selected.removeLast()
                }
            }
            selected.insert(window, at: 0)
        case .visible:
            if wasSelected {
                selected.insert(window, at: 0)
                return
            }
            guard wasVisible || count < maximumCount else {
                return
            }
            visible.append(window)
        }
    }

    mutating func dequeueBatch() -> [WindowItem] {
        var batch: [WindowItem] = []
        batch.reserveCapacity(min(batchSize, count))

        while batch.count < batchSize, !selected.isEmpty {
            batch.append(selected.removeFirst())
        }
        while batch.count < batchSize, !visible.isEmpty {
            batch.append(visible.removeFirst())
        }
        return batch
    }

    mutating func clear() {
        selected.removeAll(keepingCapacity: true)
        visible.removeAll(keepingCapacity: true)
    }

    private func remove(windowID: String, from windows: inout [WindowItem]) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else {
            return false
        }
        windows.remove(at: index)
        return true
    }
}

@MainActor
public final class WindowThumbnailLoader {
    private let store: WindowThumbnailStore
    private let capturer: any WindowThumbnailCapturing
    private var requestQueue = WindowThumbnailRequestQueue()
    private var activeWindowIDs: Set<String> = []
    private var completedWindowIDs: Set<String> = []
    private var previewsAllowed = false
    private var viewportPixelSize = CGSize(width: 240, height: 165)
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var didEmitFirstThumbnailForGeneration = false

    public init(
        store: WindowThumbnailStore,
        capturer: any WindowThumbnailCapturing
    ) {
        self.store = store
        self.capturer = capturer
    }

    public func refresh(
        windows: [WindowItem],
        permissionState: PermissionState,
        viewportPixelSize: CGSize = CGSize(width: 240, height: 165)
    ) {
        beginRefresh(permissionState: permissionState, viewportPixelSize: viewportPixelSize)
        for window in windows {
            requestThumbnail(for: window, priority: .visible)
        }
    }

    public func beginRefresh(
        permissionState: PermissionState,
        viewportPixelSize: CGSize = CGSize(width: 240, height: 165),
        preservingCachedThumbnails: Bool = false
    ) {
        refreshGeneration += 1
        didEmitFirstThumbnailForGeneration = false
        requestQueue.clear()
        activeWindowIDs.removeAll(keepingCapacity: true)
        completedWindowIDs.removeAll(keepingCapacity: true)
        previewsAllowed = !permissionState.blocksWindowPreviews
        self.viewportPixelSize = viewportPixelSize
        refreshTask?.cancel()
        if !preservingCachedThumbnails || !previewsAllowed {
            store.clear()
        }
    }

    func requestThumbnail(
        for window: WindowItem,
        priority: WindowThumbnailRequestPriority
    ) {
        guard previewsAllowed,
              Self.screenCaptureIdentifier(for: window) != nil,
              !completedWindowIDs.contains(window.id),
              !activeWindowIDs.contains(window.id) else {
            return
        }

        requestQueue.enqueue(window, priority: priority)
        startWorkerIfNeeded()
    }

    public func waitForCurrentRefresh() async {
        while let refreshTask {
            await refreshTask.value
        }
    }

    public func cancel(preservingCachedThumbnails: Bool = false) {
        refreshGeneration += 1
        didEmitFirstThumbnailForGeneration = false
        previewsAllowed = false
        requestQueue.clear()
        activeWindowIDs.removeAll(keepingCapacity: true)
        completedWindowIDs.removeAll(keepingCapacity: true)
        refreshTask?.cancel()
        if !preservingCachedThumbnails {
            store.clear()
        }
    }

    private func startWorkerIfNeeded() {
        guard refreshTask == nil, previewsAllowed, requestQueue.count > 0 else {
            return
        }

        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.drainRequests(generation: generation)
            self?.finishWorker()
        }
    }

    private func drainRequests(generation: Int) async {
        while !Task.isCancelled, generation == refreshGeneration {
            let batch = requestQueue.dequeueBatch()
            guard !batch.isEmpty else {
                return
            }

            for window in batch {
                activeWindowIDs.insert(window.id)
            }

            let identifiers = batch.compactMap(Self.screenCaptureIdentifier)
            if identifiers.count == 1, let identifier = identifiers.first {
                await capturer.prepareForRefresh(windowIdentifier: identifier)
            } else {
                await capturer.prepareForRefresh(windowIdentifiers: identifiers)
            }

            guard !Task.isCancelled, generation == refreshGeneration else {
                return
            }

            for window in batch {
                guard !Task.isCancelled, generation == refreshGeneration else {
                    return
                }

                let thumbnail = await capturer.captureThumbnail(
                    for: window,
                    viewportPixelSize: viewportPixelSize
                )
                guard !Task.isCancelled, generation == refreshGeneration else {
                    return
                }

                activeWindowIDs.remove(window.id)
                completedWindowIDs.insert(window.id)
                if let thumbnail {
                    store.setThumbnail(thumbnail, for: window.id)
                    if !didEmitFirstThumbnailForGeneration {
                        didEmitFirstThumbnailForGeneration = true
                        SwitcherPerformanceTrace.firstThumbnail()
                    }
                }
            }
        }
    }

    private func finishWorker() {
        refreshTask = nil
        startWorkerIfNeeded()
    }

    nonisolated private static func screenCaptureIdentifier(for window: WindowItem) -> CGWindowID? {
        guard let screenCaptureIdentifier = window.screenCaptureIdentifier,
              !window.isMinimized else {
            return nil
        }

        return screenCaptureIdentifier
    }
}

public actor ScreenCaptureKitWindowThumbnailCapturer: WindowThumbnailCapturing {
    private var windowsByIdentifier: [CGWindowID: SCWindow] = [:]

    public init() {}

    public func prepareForRefresh(windowIdentifiers: [CGWindowID]) async {
        guard !windowIdentifiers.isEmpty else {
            windowsByIdentifier.removeAll(keepingCapacity: true)
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard !content.windows.isEmpty else {
                self.windowsByIdentifier.removeAll(keepingCapacity: true)
                return
            }

            let requestedWindowIdentifiers = Set(windowIdentifiers)
            var windowsByIdentifier: [CGWindowID: SCWindow] = [:]
            windowsByIdentifier.reserveCapacity(min(content.windows.count, requestedWindowIdentifiers.count))
            for window in content.windows {
                guard requestedWindowIdentifiers.contains(window.windowID) else {
                    continue
                }

                windowsByIdentifier[window.windowID] = window
                guard windowsByIdentifier.count < requestedWindowIdentifiers.count else {
                    break
                }
            }
            self.windowsByIdentifier = windowsByIdentifier
        } catch {
            self.windowsByIdentifier.removeAll(keepingCapacity: true)
        }
    }

    public func prepareForRefresh(windowIdentifier: CGWindowID) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard !content.windows.isEmpty else {
                self.windowsByIdentifier.removeAll(keepingCapacity: true)
                return
            }

            cacheOnlyWindow(withIdentifier: windowIdentifier, in: content.windows)
        } catch {
            self.windowsByIdentifier.removeAll(keepingCapacity: true)
        }
    }

    private func cacheOnlyWindow(withIdentifier requestedWindowIdentifier: CGWindowID, in windows: [SCWindow]) {
        for window in windows {
            guard window.windowID == requestedWindowIdentifier else {
                continue
            }

            windowsByIdentifier.removeAll(keepingCapacity: true)
            windowsByIdentifier[window.windowID] = window
            return
        }

        windowsByIdentifier.removeAll(keepingCapacity: true)
    }

    public func captureThumbnail(for window: WindowItem, viewportPixelSize: CGSize) async -> WindowThumbnail? {
        guard let screenCaptureIdentifier = window.screenCaptureIdentifier else {
            return nil
        }

        do {
            guard let captureWindow = windowsByIdentifier[screenCaptureIdentifier] else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let targetSize = WindowThumbnailCaptureSizing.targetPixelSize(
                for: captureWindow.frame,
                viewportPixelSize: viewportPixelSize
            )
            configuration.width = targetSize.width
            configuration.height = targetSize.height
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.showsCursor = false

            let filter = SCContentFilter(desktopIndependentWindow: captureWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

            guard let pngData = Self.pngData(from: image) else {
                return nil
            }

            return WindowThumbnail(
                pngData: pngData,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
