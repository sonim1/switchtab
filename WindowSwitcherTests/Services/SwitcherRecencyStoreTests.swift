import Foundation
import WindowSwitcher

enum SwitcherRecencyStoreTests {
    static func run() throws {
        try testOrderingFallsBackToIncomingOrderWithoutHistory()
        try testRecordingSelectionMovesItemToFront()
        try testLaterSelectionMovesAheadOfPreviousSelection()
        try testOrderingCachesPersistedHistory()
        try testRecordSelectionUpdatesMemoryAndPersistsOnFlush()
        try testOrderingWithoutHistoryDoesNotReadItemIDs()
        try testOrderingSingleItemDoesNotReadHistoryOrItemID()
        try testOrderingWithHistoryReadsEachItemIDOnce()
        try testOrderingWithSingleHistoryStopsReadingIDsAfterMatch()
        try testOrderingWithSingleHistoryTwoItemsMovesMatch()
        try testOrderingWithTwoHistoryReadsEachItemIDOnce()
        try testOrderingWithTwoHistoryStopsReadingIDsAfterBothMatch()
        try testOrderingWithThreeHistoryStopsReadingIDsAfterAllMatch()
        try testOrderingWithLongHistoryStopsReadingIDsWhenHistoryAlreadyLeadsItems()
        try testRecordingSecondItemInThreeItemHistoryKeepsThirdItem()
        try testRecordingTopSelectionDoesNotPersistOnFlush()
        try testZeroHistoryCapacitySkipsRecencyReadsAndWrites()
        try testForwardInitialSelectionSkipsMostRecentItem()
        try testReverseInitialSelectionStartsAtLastItem()
    }

    static func testOrderingFallsBackToIncomingOrderWithoutHistory() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        let items = ["finder", "safari", "notes"]

        let ordered = store.order(items) { $0 }

        try expectEqual(ordered, items)
    }

    static func testRecordingSelectionMovesItemToFront() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        let items = ["finder", "safari", "notes"]

        store.recordSelection(id: "notes")
        let ordered = store.order(items) { $0 }

        try expectEqual(ordered, ["notes", "finder", "safari"])
    }

    static func testLaterSelectionMovesAheadOfPreviousSelection() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        let items = ["finder", "safari", "notes"]

        store.recordSelection(id: "notes")
        store.recordSelection(id: "safari")
        let ordered = store.order(items) { $0 }

        try expectEqual(ordered, ["safari", "notes", "finder"])
    }

    static func testOrderingCachesPersistedHistory() throws {
        let defaults = CountingRecencyDefaults(history: ["notes"])
        let store = SwitcherRecencyStore(userDefaults: defaults)
        let items = ["finder", "safari", "notes"]

        _ = store.order(items) { $0 }
        _ = store.order(items) { $0 }

        try expectEqual(defaults.stringArrayReadCount, 1)
    }

    static func testRecordSelectionUpdatesMemoryAndPersistsOnFlush() throws {
        let defaults = CountingRecencyDefaults(history: [])
        let store = SwitcherRecencyStore(userDefaults: defaults)
        let items = ["finder", "safari", "notes"]

        store.recordSelection(id: "notes")

        try expectEqual(store.order(items) { $0 }, ["notes", "finder", "safari"])
        try expectEqual(defaults.writeCount, 0)

        store.flush()

        try expectEqual(defaults.writeCount, 1)
        try expectEqual(defaults.lastStoredIDs, ["notes"])
    }

    static func testOrderingWithoutHistoryDoesNotReadItemIDs() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        var idReadCount = 0

        let ordered = store.order(["finder", "safari", "notes"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["finder", "safari", "notes"])
        try expectEqual(idReadCount, 0)
    }

    static func testOrderingSingleItemDoesNotReadHistoryOrItemID() throws {
        let defaults = CountingRecencyDefaults(history: ["safari"])
        let store = SwitcherRecencyStore(userDefaults: defaults)
        var idReadCount = 0

        let ordered = store.order(["finder"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["finder"])
        try expectEqual(defaults.stringArrayReadCount, 0)
        try expectEqual(idReadCount, 0)
    }

    static func testOrderingWithHistoryReadsEachItemIDOnce() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "notes")
        var idReadCount = 0

        let ordered = store.order(["finder", "safari", "notes"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["notes", "finder", "safari"])
        try expectEqual(idReadCount, 3)
    }

    static func testOrderingWithSingleHistoryStopsReadingIDsAfterMatch() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "finder")
        var idReadCount = 0

        let ordered = store.order(["finder", "safari", "notes"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["finder", "safari", "notes"])
        try expectEqual(idReadCount, 1)
    }

    static func testOrderingWithSingleHistoryTwoItemsMovesMatch() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "safari")
        var idReadCount = 0

        let ordered = store.order(["finder", "safari"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["safari", "finder"])
        try expectEqual(idReadCount, 2)
    }

    static func testOrderingWithTwoHistoryReadsEachItemIDOnce() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "notes")
        store.recordSelection(id: "safari")
        var idReadCount = 0

        let ordered = store.order(["finder", "safari", "notes"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["safari", "notes", "finder"])
        try expectEqual(idReadCount, 3)
    }

    static func testOrderingWithTwoHistoryStopsReadingIDsAfterBothMatch() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "notes")
        store.recordSelection(id: "safari")
        var idReadCount = 0

        let ordered = store.order(["safari", "notes", "finder"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["safari", "notes", "finder"])
        try expectEqual(idReadCount, 2)
    }

    static func testOrderingWithThreeHistoryStopsReadingIDsAfterAllMatch() throws {
        let store = SwitcherRecencyStore(userDefaults: makeDefaults())
        store.recordSelection(id: "notes")
        store.recordSelection(id: "safari")
        store.recordSelection(id: "finder")
        var idReadCount = 0

        let ordered = store.order(["finder", "safari", "notes", "mail"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["finder", "safari", "notes", "mail"])
        try expectEqual(idReadCount, 3)
    }

    static func testOrderingWithLongHistoryStopsReadingIDsWhenHistoryAlreadyLeadsItems() throws {
        let defaults = CountingRecencyDefaults(history: ["mail", "finder", "safari", "notes"])
        let store = SwitcherRecencyStore(userDefaults: defaults)
        var idReadCount = 0

        let ordered = store.order(["mail", "finder", "safari", "notes", "calendar"]) { item in
            idReadCount += 1
            return item
        }

        try expectEqual(ordered, ["mail", "finder", "safari", "notes", "calendar"])
        try expectEqual(idReadCount, 4)
    }

    static func testRecordingSecondItemInThreeItemHistoryKeepsThirdItem() throws {
        let defaults = CountingRecencyDefaults(history: ["finder", "safari", "notes"])
        let store = SwitcherRecencyStore(userDefaults: defaults, maxHistoryCount: 3)

        store.recordSelection(id: "safari")
        store.flush()

        try expectEqual(defaults.lastStoredIDs, ["safari", "finder", "notes"])
    }

    static func testRecordingTopSelectionDoesNotPersistOnFlush() throws {
        let defaults = CountingRecencyDefaults(history: ["notes", "safari"])
        let store = SwitcherRecencyStore(userDefaults: defaults)

        store.recordSelection(id: "notes")
        store.flush()

        try expectEqual(defaults.writeCount, 0)
    }

    static func testZeroHistoryCapacitySkipsRecencyReadsAndWrites() throws {
        let defaults = CountingRecencyDefaults(history: ["notes"])
        let store = SwitcherRecencyStore(userDefaults: defaults, maxHistoryCount: 0)
        let items = ["finder", "safari", "notes"]
        var idReadCount = 0

        store.recordSelection(id: "notes")
        let ordered = store.order(items) { item in
            idReadCount += 1
            return item
        }
        store.flush()

        try expectEqual(ordered, items)
        try expectEqual(idReadCount, 0)
        try expectEqual(defaults.stringArrayReadCount, 0)
        try expectEqual(defaults.writeCount, 0)
    }

    static func testForwardInitialSelectionSkipsMostRecentItem() throws {
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 0, reverse: false), 0)
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 1, reverse: false), 0)
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 3, reverse: false), 1)
    }

    static func testReverseInitialSelectionStartsAtLastItem() throws {
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 0, reverse: true), 0)
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 1, reverse: true), 0)
        try expectEqual(SwitcherRecencyStore.initialSelectedIndex(itemCount: 3, reverse: true), 2)
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "WindowSwitcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class CountingRecencyDefaults: UserDefaults {
    private let history: [String]
    private(set) var stringArrayReadCount = 0
    private(set) var writeCount = 0
    private(set) var lastStoredIDs: [String] = []

    init(history: [String]) {
        self.history = history
        super.init(suiteName: "WindowSwitcherTests.\(UUID().uuidString)")!
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        stringArrayReadCount += 1
        return history
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        lastStoredIDs = value as? [String] ?? []
    }
}
