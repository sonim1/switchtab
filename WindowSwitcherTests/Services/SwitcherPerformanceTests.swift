import Foundation
import WindowSwitcher

enum SwitcherPerformanceTests {
    static func run() throws {
        try testIconStripSessionCreationStaysFast()
    }

    static func testIconStripSessionCreationStaysFast() throws {
        let items = (0..<20).map { index in
            SwitcherListItem(id: "app-\(index)", title: "Application \(index)", subtitle: nil)
        }

        let start = DispatchTime.now()
        let session = SwitcherSession(
            mode: .currentAppWindowSwitching,
            items: items
        )
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

        try expectEqual(session.items.count, 20)
        try expectTrue(elapsedNanoseconds < 100_000_000)
    }
}
