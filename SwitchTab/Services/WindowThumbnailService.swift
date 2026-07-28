import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public struct WindowThumbnail: Equatable, Sendable {
    public let pngData: Data

    public init(pngData: Data) {
        self.pngData = pngData
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

    public init() {}

    public func image(for key: String) -> NSImage? {
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
    }

    public func clear() {
        guard !thumbnails.isEmpty || !decodedImages.isEmpty else {
            return
        }

        objectWillChange.send()
        thumbnails.removeAll(keepingCapacity: true)
        decodedImages.removeAll(keepingCapacity: true)
    }
}

@MainActor
public final class WindowThumbnailLoader {
    private let store: WindowThumbnailStore
    private let capturer: any WindowThumbnailCapturing
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

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
        cancel()

        guard !permissionState.blocksWindowPreviews else {
            store.clear()
            return
        }

        guard let firstCapturableWindow = Self.firstCapturableWindow(in: windows) else {
            store.clear()
            return
        }

        guard let secondCapturableWindow = Self.nextCapturableWindow(in: windows, after: firstCapturableWindow.index) else {
            refreshSingleCapturableWindow(
                windows[firstCapturableWindow.index],
                screenCaptureIdentifier: firstCapturableWindow.screenCaptureIdentifier,
                viewportPixelSize: viewportPixelSize
            )
            return
        }

        let capturer = capturer
        let store = store
        let refreshGeneration = nextRefreshGeneration()
        refreshTask = Task.detached { [weak self, windows, capturer, store, viewportPixelSize, refreshGeneration] in
            guard !Task.isCancelled else {
                return
            }

            var screenCaptureIdentifiers: [CGWindowID] = []
            screenCaptureIdentifiers.reserveCapacity(windows.count - firstCapturableWindow.index)
            screenCaptureIdentifiers.append(firstCapturableWindow.screenCaptureIdentifier)
            screenCaptureIdentifiers.append(secondCapturableWindow.screenCaptureIdentifier)

            let nextWindowIndex = windows.index(after: secondCapturableWindow.index)
            for index in nextWindowIndex..<windows.count {
                guard !Task.isCancelled else {
                    return
                }

                if let screenCaptureIdentifier = Self.screenCaptureIdentifier(for: windows[index]) {
                    screenCaptureIdentifiers.append(screenCaptureIdentifier)
                }
            }

            guard !Task.isCancelled else {
                return
            }

            await capturer.prepareForRefresh(windowIdentifiers: screenCaptureIdentifiers)
            var thumbnailsByKey: [String: WindowThumbnail] = [:]
            thumbnailsByKey.reserveCapacity(screenCaptureIdentifiers.count)

            let firstWindowIndex = firstCapturableWindow.index
            for index in firstWindowIndex..<windows.count {
                guard !Task.isCancelled else {
                    return
                }

                let window = windows[index]
                guard Self.screenCaptureIdentifier(for: window) != nil else {
                    continue
                }

                guard let thumbnail = await capturer.captureThumbnail(for: window, viewportPixelSize: viewportPixelSize) else {
                    continue
                }

                guard !Task.isCancelled else {
                    return
                }

                thumbnailsByKey[window.id] = thumbnail
            }

            guard !Task.isCancelled else {
                return
            }

            let completedThumbnails = thumbnailsByKey
            await MainActor.run { [weak self, completedThumbnails, store, refreshGeneration] in
                guard !Task.isCancelled else {
                    return
                }

                store.setThumbnails(completedThumbnails)
                self?.clearRefreshTask(ifCurrent: refreshGeneration)
            }
        }
    }

    private func refreshSingleCapturableWindow(
        _ window: WindowItem,
        screenCaptureIdentifier: CGWindowID,
        viewportPixelSize: CGSize
    ) {
        let capturer = capturer
        let store = store
        let refreshGeneration = nextRefreshGeneration()
        refreshTask = Task.detached { [weak self, capturer, store, viewportPixelSize, window, screenCaptureIdentifier, refreshGeneration] in
            guard !Task.isCancelled else {
                return
            }

            await capturer.prepareForRefresh(windowIdentifier: screenCaptureIdentifier)
            guard !Task.isCancelled else {
                return
            }

            guard let thumbnail = await capturer.captureThumbnail(for: window, viewportPixelSize: viewportPixelSize) else {
                await MainActor.run { [weak self, store, refreshGeneration] in
                    guard !Task.isCancelled else {
                        return
                    }

                    store.clear()
                    self?.clearRefreshTask(ifCurrent: refreshGeneration)
                }
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self, store, window, thumbnail, refreshGeneration] in
                guard !Task.isCancelled else {
                    return
                }

                store.setThumbnails([window.id: thumbnail])
                self?.clearRefreshTask(ifCurrent: refreshGeneration)
            }
        }
    }

    public func waitForCurrentRefresh() async {
        await refreshTask?.value
    }

    public func cancel() {
        guard let refreshTask else {
            return
        }

        refreshTask.cancel()
        self.refreshTask = nil
        refreshGeneration += 1
    }

    private func nextRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func clearRefreshTask(ifCurrent refreshGeneration: Int) {
        guard self.refreshGeneration == refreshGeneration else {
            return
        }

        refreshTask = nil
    }

    nonisolated private static func firstCapturableWindow(
        in windows: [WindowItem]
    ) -> (index: Int, screenCaptureIdentifier: CGWindowID)? {
        for index in windows.indices {
            if let screenCaptureIdentifier = screenCaptureIdentifier(for: windows[index]) {
                return (index, screenCaptureIdentifier)
            }
        }

        return nil
    }

    nonisolated private static func nextCapturableWindow(
        in windows: [WindowItem],
        after index: Int
    ) -> (index: Int, screenCaptureIdentifier: CGWindowID)? {
        let nextIndex = windows.index(after: index)
        guard nextIndex < windows.endIndex else {
            return nil
        }

        for index in nextIndex..<windows.count {
            if let screenCaptureIdentifier = screenCaptureIdentifier(for: windows[index]) {
                return (index, screenCaptureIdentifier)
            }
        }

        return nil
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

            return WindowThumbnail(pngData: pngData)
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
