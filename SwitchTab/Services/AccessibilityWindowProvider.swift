import AppKit
import ApplicationServices
import Foundation

public struct ActiveApplicationSnapshot: Equatable, Sendable {
    public let processIdentifier: Int
    public let localizedName: String?

    public init(processIdentifier: Int, localizedName: String? = nil) {
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
    }
}

public struct AccessibilityWindowSnapshot: Equatable, Sendable {
    public let windowIdentifier: Int
    public let ownerProcessIdentifier: Int
    public let ownerName: String
    public let title: String
    public let screenCaptureIdentifier: UInt32?
    public let isMinimized: Bool
    public let availability: WindowAvailability
    public let isFocused: Bool

    public init(
        windowIdentifier: Int,
        ownerProcessIdentifier: Int,
        ownerName: String,
        title: String,
        screenCaptureIdentifier: UInt32? = nil,
        isMinimized: Bool,
        availability: WindowAvailability,
        isFocused: Bool = false
    ) {
        self.windowIdentifier = windowIdentifier
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.ownerName = ownerName
        self.title = title
        self.screenCaptureIdentifier = screenCaptureIdentifier
        self.isMinimized = isMinimized
        self.availability = availability
        self.isFocused = isFocused
    }
}

public protocol ActiveApplicationProviding {
    func frontmostApplication() -> ActiveApplicationSnapshot?
}

public protocol AccessibilityWindowSnapshotProviding {
    func windowCount(ownerProcessIdentifier: Int) -> Int?

    func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool,
        registerWindowElements: Bool
    ) -> [AccessibilityWindowSnapshot]?
}

public struct AccessibilityWindowInclusionCandidate: Equatable {
    public let originalIndex: Int
    public let role: String?
    public let subrole: String?
    public let windowNumber: UInt32?

    public init(originalIndex: Int, role: String?, subrole: String?, windowNumber: UInt32? = nil) {
        self.originalIndex = originalIndex
        self.role = role
        self.subrole = subrole
        self.windowNumber = windowNumber
    }
}

public struct AccessibilityWindowInclusionMapping: Equatable {
    public let originalIndex: Int
    public let windowIdentifier: Int
    public let screenCaptureIdentifier: UInt32?

    public init(originalIndex: Int, windowIdentifier: Int, screenCaptureIdentifier: UInt32? = nil) {
        self.originalIndex = originalIndex
        self.windowIdentifier = windowIdentifier
        self.screenCaptureIdentifier = screenCaptureIdentifier
    }
}

public enum AccessibilityWindowInclusionPolicy {
    public static func shouldInclude(role: String?, subrole: String?) -> Bool {
        role == (kAXWindowRole as String)
            && subrole == (kAXStandardWindowSubrole as String)
    }

    public static func acceptedWindowMappings(
        ownerProcessIdentifier: Int,
        candidates: [AccessibilityWindowInclusionCandidate]
    ) -> [AccessibilityWindowInclusionMapping] {
        var mappings: [AccessibilityWindowInclusionMapping] = []
        mappings.reserveCapacity(candidates.count)

        for candidate in candidates where shouldInclude(role: candidate.role, subrole: candidate.subrole) {
            // A resolved CGWindowID is stable across window closes/reorders and
            // process restarts of the switcher; the positional scheme is only a
            // fallback for elements the resolver cannot identify.
            if let windowNumber = candidate.windowNumber {
                mappings.append(AccessibilityWindowInclusionMapping(
                    originalIndex: candidate.originalIndex,
                    windowIdentifier: Int(windowNumber),
                    screenCaptureIdentifier: windowNumber
                ))
            } else {
                mappings.append(AccessibilityWindowInclusionMapping(
                    originalIndex: candidate.originalIndex,
                    windowIdentifier: ownerProcessIdentifier * 10_000 + mappings.count,
                    screenCaptureIdentifier: nil
                ))
            }
        }

        return mappings
    }
}

public struct AccessibilityWindowProvider {
    private let activeApplicationProvider: any ActiveApplicationProviding
    private let windowSnapshotProvider: any AccessibilityWindowSnapshotProviding

    public init(
        activeApplicationProvider: any ActiveApplicationProviding = NSWorkspaceActiveApplicationProvider(),
        windowSnapshotProvider: any AccessibilityWindowSnapshotProviding = AXWindowSnapshotProvider()
    ) {
        self.activeApplicationProvider = activeApplicationProvider
        self.windowSnapshotProvider = windowSnapshotProvider
    }

    public func currentApplicationWindows(includeScreenCaptureIdentifiers: Bool = true) -> [WindowItem] {
        guard let activeApplication = activeApplicationProvider.frontmostApplication() else {
            return []
        }

        return windows(
            ownerProcessIdentifier: activeApplication.processIdentifier,
            ownerName: activeApplication.localizedName,
            includeScreenCaptureIdentifiers: includeScreenCaptureIdentifiers,
            registerWindowElements: true
        ) ?? []
    }

    public func applicationWindows(
        ownerProcessIdentifier: Int,
        ownerName: String?
    ) -> [WindowItem]? {
        windows(
            ownerProcessIdentifier: ownerProcessIdentifier,
            ownerName: ownerName,
            includeScreenCaptureIdentifiers: false,
            registerWindowElements: true
        )
    }

    public func applicationWindowCount(
        ownerProcessIdentifier: Int,
        ownerName: String?
    ) -> Int? {
        windowSnapshotProvider.windowCount(ownerProcessIdentifier: ownerProcessIdentifier)
    }

    private func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool,
        registerWindowElements: Bool
    ) -> [WindowItem]? {
        guard let snapshots = windowSnapshotProvider.windows(
            ownerProcessIdentifier: ownerProcessIdentifier,
            ownerName: ownerName,
            includeScreenCaptureIdentifiers: includeScreenCaptureIdentifiers,
            registerWindowElements: registerWindowElements
        ) else {
            return nil
        }
        guard !snapshots.isEmpty else {
            return []
        }

        var windows: [WindowItem] = []
        windows.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            guard let window = windowItem(
                for: snapshot,
                ownerProcessIdentifier: ownerProcessIdentifier
            ) else {
                continue
            }

            windows.append(window)
        }

        return windows
    }

    private func windowItem(
        for snapshot: AccessibilityWindowSnapshot,
        ownerProcessIdentifier: Int
    ) -> WindowItem? {
        guard snapshot.ownerProcessIdentifier == ownerProcessIdentifier,
              snapshot.availability != .closed else {
            return nil
        }

        return WindowItem(
            windowIdentifier: snapshot.windowIdentifier,
            ownerProcessIdentifier: snapshot.ownerProcessIdentifier,
            ownerName: snapshot.ownerName,
            title: snapshot.title,
            screenCaptureIdentifier: snapshot.screenCaptureIdentifier,
            isMinimized: snapshot.isMinimized,
            availability: snapshot.availability,
            isFocused: snapshot.isFocused
        )
    }
}

public final class NSWorkspaceActiveApplicationProvider: ActiveApplicationProviding {
    public init() {}

    public func frontmostApplication() -> ActiveApplicationSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return ActiveApplicationSnapshot(
            processIdentifier: Int(application.processIdentifier),
            localizedName: application.localizedName
        )
    }
}

public protocol AXWindowNumberResolving {
    func windowNumber(for element: AXUIElement) -> UInt32?
}

/// Resolves the CGWindowID backing an accessibility window element via the
/// private `_AXUIElementGetWindow` symbol. Not App Store safe; this app relies
/// on unsandboxed AX control and ships via direct distribution. Returns nil
/// when the symbol is unavailable so callers fall back to positional identity.
public final class PrivateAXWindowNumberResolver: AXWindowNumberResolving {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindowFunction: GetWindowFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            return nil
        }

        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    public init() {}

    public func windowNumber(for element: AXUIElement) -> UInt32? {
        guard let getWindowFunction = Self.getWindowFunction else {
            return nil
        }

        var windowNumber: CGWindowID = 0
        guard getWindowFunction(element, &windowNumber) == .success,
              windowNumber != 0 else {
            return nil
        }

        return windowNumber
    }
}

protocol AXWindowAttributeReading: AnyObject {
    func windowElements(of applicationElement: AXUIElement) -> [AXUIElement]?
    func focusedWindowElement(of applicationElement: AXUIElement) -> AXUIElement?
    func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String?
    func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool
}

private final class SystemAXWindowAttributeReader: AXWindowAttributeReading {
    func windowElements(of applicationElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    func focusedWindowElement(of applicationElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success,
            let focusedValue = value,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(focusedValue as AnyObject, to: AXUIElement.self)
    }

    func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }
}

public final class AXWindowSnapshotProvider: AccessibilityWindowSnapshotProviding {
    private let windowNumberResolver: any AXWindowNumberResolving
    private let attributeReader: any AXWindowAttributeReading

    public init(windowNumberResolver: any AXWindowNumberResolving = PrivateAXWindowNumberResolver()) {
        self.windowNumberResolver = windowNumberResolver
        self.attributeReader = SystemAXWindowAttributeReader()
    }

    init(
        windowNumberResolver: any AXWindowNumberResolving,
        attributeReader: any AXWindowAttributeReading
    ) {
        self.windowNumberResolver = windowNumberResolver
        self.attributeReader = attributeReader
    }

    public func windowCount(ownerProcessIdentifier: Int) -> Int? {
        let appElement = AXUIElementCreateApplication(pid_t(ownerProcessIdentifier))
        guard let windowElements = attributeReader.windowElements(of: appElement) else {
            return nil
        }

        var count = 0
        for windowElement in windowElements {
            let role = attributeReader.stringAttribute(
                windowElement,
                kAXRoleAttribute as CFString
            )
            let subrole = attributeReader.stringAttribute(
                windowElement,
                kAXSubroleAttribute as CFString
            )
            if AccessibilityWindowInclusionPolicy.shouldInclude(role: role, subrole: subrole) {
                count += 1
            }
        }
        return count
    }

    public func windows(
        ownerProcessIdentifier: Int,
        ownerName: String?,
        includeScreenCaptureIdentifiers: Bool,
        registerWindowElements: Bool
    ) -> [AccessibilityWindowSnapshot]? {
        let appElement = AXUIElementCreateApplication(pid_t(ownerProcessIdentifier))
        guard let windowElements = attributeReader.windowElements(of: appElement) else {
            if registerWindowElements {
                AXWindowElementRegistry.shared.removeAll(ownerProcessIdentifier: ownerProcessIdentifier)
            }
            return nil
        }

        guard !windowElements.isEmpty else {
            if registerWindowElements {
                AXWindowElementRegistry.shared.removeAll(ownerProcessIdentifier: ownerProcessIdentifier)
            }
            return []
        }

        let resolvedOwnerName = ownerName
            ?? NSRunningApplication(processIdentifier: pid_t(ownerProcessIdentifier))?.localizedName
            ?? "Application \(ownerProcessIdentifier)"

        var snapshots: [AccessibilityWindowSnapshot] = []
        var activeWindowElements: [Int: AXUIElement] = [:]
        snapshots.reserveCapacity(windowElements.count)
        activeWindowElements.reserveCapacity(windowElements.count)

        let candidates = windowElements.indices.map { index in
            AccessibilityWindowInclusionCandidate(
                originalIndex: index,
                role: attributeReader.stringAttribute(windowElements[index], kAXRoleAttribute as CFString),
                subrole: attributeReader.stringAttribute(windowElements[index], kAXSubroleAttribute as CFString),
                windowNumber: windowNumberResolver.windowNumber(for: windowElements[index])
            )
        }
        let mappings = AccessibilityWindowInclusionPolicy.acceptedWindowMappings(
            ownerProcessIdentifier: ownerProcessIdentifier,
            candidates: candidates
        )
        let focusedWindowElement = attributeReader.focusedWindowElement(of: appElement)

        // Title-matching heuristic remains only for windows whose CGWindowID
        // the resolver could not produce.
        var screenCaptureWindowIndex: ScreenCaptureWindowIndex?
        if includeScreenCaptureIdentifiers,
           mappings.contains(where: { $0.screenCaptureIdentifier == nil }) {
            let screenCaptureWindows = CGWindowInfoProvider.visibleWindows(ownerProcessIdentifier: ownerProcessIdentifier)
            if !screenCaptureWindows.isEmpty {
                screenCaptureWindowIndex = ScreenCaptureWindowIndex(screenCaptureWindows)
            }
        }

        for mapping in mappings {
            let windowElement = windowElements[mapping.originalIndex]
            let windowIdentifier = mapping.windowIdentifier
            if registerWindowElements {
                activeWindowElements[windowIdentifier] = windowElement
            }
            snapshots.append(
                windowSnapshot(
                    windowElement,
                    windowIdentifier: windowIdentifier,
                    ownerProcessIdentifier: ownerProcessIdentifier,
                    ownerName: resolvedOwnerName,
                    resolvedScreenCaptureIdentifier: includeScreenCaptureIdentifiers ? mapping.screenCaptureIdentifier : nil,
                    isFocused: focusedWindowElement.map { CFEqual($0, windowElement) } ?? false,
                    screenCaptureWindowIndex: &screenCaptureWindowIndex
                )
            )
        }

        if registerWindowElements {
            AXWindowElementRegistry.shared.replace(
                ownerProcessIdentifier: ownerProcessIdentifier,
                with: activeWindowElements
            )
        }
        return snapshots
    }

    private func windowSnapshot(
        _ windowElement: AXUIElement,
        windowIdentifier: Int,
        ownerProcessIdentifier: Int,
        ownerName: String,
        resolvedScreenCaptureIdentifier: UInt32?,
        isFocused: Bool,
        screenCaptureWindowIndex: inout ScreenCaptureWindowIndex?
    ) -> AccessibilityWindowSnapshot {
        let isMinimized = attributeReader.boolAttribute(windowElement, kAXMinimizedAttribute as CFString)
        let title = attributeReader.stringAttribute(windowElement, kAXTitleAttribute as CFString) ?? ""
        return AccessibilityWindowSnapshot(
            windowIdentifier: windowIdentifier,
            ownerProcessIdentifier: ownerProcessIdentifier,
            ownerName: ownerName,
            title: title,
            screenCaptureIdentifier: resolvedScreenCaptureIdentifier
                ?? screenCaptureWindowIndex?.nextIdentifier(titled: title),
            isMinimized: isMinimized,
            availability: isMinimized ? .minimized : .available,
            isFocused: isFocused
        )
    }

}

private struct CGWindowInfoSnapshot {
    let identifier: UInt32
    let title: String
}

private struct TitleMatchBucket {
    static let empty = TitleMatchBucket(indices: [])

    var indices: [Int]
    var nextIndex = 0
}

private struct ScreenCaptureWindowIndex {
    private let snapshots: [CGWindowInfoSnapshot]
    private var consumed: [Bool] = []
    private var bucketsByTitle: [String: TitleMatchBucket] = [:]
    private var nextFallbackIndex = 0

    init(_ snapshots: [CGWindowInfoSnapshot]) {
        self.snapshots = snapshots

        for index in snapshots.indices {
            let snapshot = snapshots[index]
            guard !snapshot.title.isEmpty else {
                continue
            }

            if bucketsByTitle.isEmpty {
                self.consumed = [Bool](repeating: false, count: snapshots.count)
                bucketsByTitle.reserveCapacity(snapshots.count)
            }
            bucketsByTitle[snapshot.title, default: .empty].indices.append(index)
        }
    }

    // Match a window title to its on-screen capture identifier. Titles are matched
    // first (deduping repeats), falling back to positional order for untitled or
    // unmatched windows. Each identifier is handed out at most once.
    mutating func nextIdentifier(titled title: String) -> UInt32? {
        if !title.isEmpty,
           let identifier = nextMatchingIdentifier(titled: title) {
            return identifier
        }

        guard !consumed.isEmpty else {
            guard nextFallbackIndex < snapshots.count else {
                return nil
            }

            let index = nextFallbackIndex
            nextFallbackIndex += 1
            return snapshots[index].identifier
        }

        while nextFallbackIndex < snapshots.count {
            let index = nextFallbackIndex
            nextFallbackIndex += 1

            guard !consumed[index] else {
                continue
            }

            consumed[index] = true
            return snapshots[index].identifier
        }

        return nil
    }

    private mutating func nextMatchingIdentifier(titled title: String) -> UInt32? {
        guard var bucket = bucketsByTitle[title] else {
            return nil
        }

        while bucket.nextIndex < bucket.indices.count {
            let snapshotIndex = bucket.indices[bucket.nextIndex]
            bucket.nextIndex += 1

            guard !consumed[snapshotIndex] else {
                continue
            }

            consumed[snapshotIndex] = true
            if bucket.nextIndex < bucket.indices.count {
                bucketsByTitle[title] = bucket
            } else {
                bucketsByTitle.removeValue(forKey: title)
            }
            return snapshots[snapshotIndex].identifier
        }

        bucketsByTitle.removeValue(forKey: title)
        return nil
    }
}

private enum CGWindowInfoProvider {
    static func visibleWindows(ownerProcessIdentifier: Int) -> [CGWindowInfoSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var snapshots: [CGWindowInfoSnapshot] = []
        snapshots.reserveCapacity(min(windowInfo.count, 16))

        for info in windowInfo {
            guard intValue(info[kCGWindowOwnerPID as String]) == ownerProcessIdentifier,
                  intValue(info[kCGWindowLayer as String]) == 0,
                  let identifier = intValue(info[kCGWindowNumber as String]) else {
                continue
            }

            snapshots.append(
                CGWindowInfoSnapshot(
                    identifier: UInt32(identifier),
                    title: info[kCGWindowName as String] as? String ?? ""
                )
            )
        }

        return snapshots
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        if let int = value as? Int {
            return int
        }

        return nil
    }
}

final class AXWindowElementRegistry: @unchecked Sendable {
    static let shared = AXWindowElementRegistry()

    private let lock = NSLock()
    private var elementsByOwnerProcessIdentifier: [Int: [Int: AXUIElement]] = [:]

    func replace(
        ownerProcessIdentifier: Int,
        with activeElements: [Int: AXUIElement]
    ) {
        lock.lock()
        defer { lock.unlock() }
        elementsByOwnerProcessIdentifier[ownerProcessIdentifier] = activeElements
    }

    func element(
        ownerProcessIdentifier: Int,
        windowIdentifier: Int
    ) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return elementsByOwnerProcessIdentifier[ownerProcessIdentifier]?[windowIdentifier]
    }

    func removeAll(ownerProcessIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        elementsByOwnerProcessIdentifier.removeValue(forKey: ownerProcessIdentifier)
    }
}
