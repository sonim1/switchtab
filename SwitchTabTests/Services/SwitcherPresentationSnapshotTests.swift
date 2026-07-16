import SwitchTab

enum SwitcherPresentationSnapshotTests {
    static func run() throws {
        try testBuildsListItemsAndInitialSelectionInOnePass()
        try testDuplicateItemIDsResolveBySelectedIndex()
    }

    static func testBuildsListItemsAndInitialSelectionInOnePass() throws {
        let elements = [
            IndexedElement(id: "finder", title: "Finder"),
            IndexedElement(id: "safari", title: "Safari"),
            IndexedElement(id: "notes", title: "Notes")
        ]
        var listItemBuildCount = 0

        let snapshot = SwitcherPresentationSnapshot(
            elements: elements,
            reverse: true
        ) { element in
            listItemBuildCount += 1
            return SwitcherListItem(id: element.id, title: element.title, subtitle: nil)
        }

        try expectEqual(listItemBuildCount, 3)
        try expectEqual(snapshot.listItems.map(\.id), ["finder", "safari", "notes"])
        try expectEqual(snapshot.selectedIndex, 2)
        try expectEqual(snapshot.element(at: 1), IndexedElement(id: "safari", title: "Safari"))
        try expectEqual(listItemBuildCount, 3)
    }

    static func testDuplicateItemIDsResolveBySelectedIndex() throws {
        let elements = [
            IndexedElement(id: "duplicate", title: "First"),
            IndexedElement(id: "duplicate", title: "Second")
        ]

        let snapshot = SwitcherPresentationSnapshot(
            elements: elements,
            reverse: false
        ) { element in
            SwitcherListItem(id: element.id, title: element.title, subtitle: nil)
        }

        try expectEqual(snapshot.element(at: 1), IndexedElement(id: "duplicate", title: "Second"))
    }
}

private struct IndexedElement: Equatable {
    let id: String
    let title: String
}
