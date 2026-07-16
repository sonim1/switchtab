import AppKit
import SwitchTab

enum ApplicationIconStoreTests {
    @MainActor
    static func run() throws {
        try testCachesResolvedApplicationIcon()
        try testCachesMissingApplicationIcon()
        try testPrunesIconsOutsidePresentedItems()
    }

    @MainActor
    static func testCachesResolvedApplicationIcon() throws {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        var resolverCallCount = 0
        let store = ApplicationIconStore { processIdentifier in
            resolverCallCount += 1
            return processIdentifier == 42 ? image : nil
        }

        let firstImage = store.icon(for: 42)
        let secondImage = store.icon(for: 42)

        try expectTrue(firstImage === image)
        try expectTrue(secondImage === image)
        try expectEqual(resolverCallCount, 1)
    }

    @MainActor
    static func testCachesMissingApplicationIcon() throws {
        var resolverCallCount = 0
        let store = ApplicationIconStore { _ in
            resolverCallCount += 1
            return nil
        }

        try expectEqual(store.icon(for: 404), nil)
        try expectEqual(store.icon(for: 404), nil)
        try expectEqual(resolverCallCount, 1)
    }

    @MainActor
    static func testPrunesIconsOutsidePresentedItems() throws {
        let retainedImage = NSImage(size: NSSize(width: 1, height: 1))
        let staleImage = NSImage(size: NSSize(width: 1, height: 1))
        var resolverCallCounts: [Int: Int] = [:]
        let store = ApplicationIconStore { processIdentifier in
            resolverCallCounts[processIdentifier, default: 0] += 1
            switch processIdentifier {
            case 42:
                return retainedImage
            case 7:
                return staleImage
            default:
                return nil
            }
        }

        _ = store.icon(for: 42)
        _ = store.icon(for: 7)
        store.retainOnlyCachedIcons(
            for: [
                SwitcherListItem(
                    id: "finder",
                    title: "Finder",
                    subtitle: nil,
                    appIconProcessIdentifier: 42
                )
            ]
        )
        _ = store.icon(for: 42)
        _ = store.icon(for: 7)

        try expectEqual(resolverCallCounts[42], 1)
        try expectEqual(resolverCallCounts[7], 2)
    }
}
