import Foundation
import SwitchTab

enum SwitcherPerformanceTests {
    static func run() throws {
        try testIconStripSessionCreationStaysFast()
        try testPerformanceTraceDefinesStablePointsOfInterest()
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

    static func testPerformanceTraceDefinesStablePointsOfInterest() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("SwitchTab/Services/SwitcherPerformanceTrace.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for name in [
            "Switcher Invocation",
            "Accessibility Discovery",
            "Application Window Counts",
            "First Thumbnail"
        ] {
            try expectTrue(source.contains("\"\(name)\""))
        }
        try expectFalse(source.contains("localizedName"))
        try expectFalse(source.contains("window.title"))
    }
}
