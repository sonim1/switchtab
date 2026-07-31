import AppKit
import Foundation

enum MenuBarIconAssetTests {
    static func run() throws {
        try testMenuBarIconUsesTemplateRendering()
        try testMenuBarIconUsesMenuBarScaleAssets()
        try testMenuBarIconKeepsVectorSource()
        try testMenuBarIconUsesUprightThreeWindowStack()
        try testMenuBarIconKeepsDetailOnFrontWindowOnly()
        try testMenuBarIconUsesWideAndNarrowFrontPanes()
        try testMenuBarIconFillsMenuBarHeightAtRetinaScale()
        try testMenuBarIconKeepsRetinaEdgesCrisp()
    }

    static func testMenuBarIconUsesTemplateRendering() throws {
        let contentsURL = assetRoot
            .appendingPathComponent("MenuBarIcon.imageset/Contents.json")
        let contents = try String(contentsOf: contentsURL, encoding: .utf8)

        try expectTrue(contents.contains("\"template-rendering-intent\" : \"template\""))
    }

    static func testMenuBarIconUsesMenuBarScaleAssets() throws {
        let oneX = try menuBarBitmap(named: "MenuBarIcon.png")
        let twoX = try menuBarBitmap(named: "MenuBarIcon@2x.png")
        let threeX = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectEqual(oneX.pixelsWide, 18)
        try expectEqual(oneX.pixelsHigh, 18)
        try expectEqual(twoX.pixelsWide, 36)
        try expectEqual(twoX.pixelsHigh, 36)
        try expectEqual(threeX.pixelsWide, 54)
        try expectEqual(threeX.pixelsHigh, 54)
    }

    static func testMenuBarIconKeepsVectorSource() throws {
        let sourceURL = resourceRoot.appendingPathComponent("MenuBarIcon.svg")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains("viewBox=\"0 0 36 36\""))
        try expectTrue(source.contains("SwitchTab stacked windows menu bar icon"))
    }

    static func testMenuBarIconUsesUprightThreeWindowStack() throws {
        let source = try vectorSource()

        try expectEqual(occurrenceCount(of: "data-role=\"window-outline\"", in: source), 3)
        try expectFalse(source.contains("rotate("))
    }

    static func testMenuBarIconKeepsDetailOnFrontWindowOnly() throws {
        let source = try vectorSource()

        try expectEqual(occurrenceCount(of: "data-role=\"front-status-dot\"", in: source), 1)
        try expectFalse(source.contains("back-status-dot"))
        try expectFalse(source.contains("middle-status-dot"))
    }

    static func testMenuBarIconUsesWideAndNarrowFrontPanes() throws {
        let source = try vectorSource()
        let rep = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectEqual(occurrenceCount(of: "data-role=\"front-pane\"", in: source), 2)
        try expectTrue(source.contains("id=\"wide-pane\""))
        try expectTrue(source.contains("id=\"narrow-pane\""))
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 23...34, y: 32...38), bitmap: rep) >= 60,
            "Expected one wide filled pane in the front window"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 40...43, y: 32...38), bitmap: rep) >= 20,
            "Expected one narrow filled pane in the front window"
        )
    }

    static func testMenuBarIconFillsMenuBarHeightAtRetinaScale() throws {
        let rep = try menuBarBitmap(named: "MenuBarIcon@2x.png")

        try expectTrue(
            contentHeight(in: rep) >= 30,
            "Expected the icon to use at least 30 of 36 vertical pixels"
        )
    }

    static func testMenuBarIconKeepsRetinaEdgesCrisp() throws {
        let rep = try menuBarBitmap(named: "MenuBarIcon@2x.png")
        let counts = alphaCounts(in: rep)

        try expectTrue(
            counts.partial * 4 <= counts.solid * 3,
            "Expected partial-alpha pixels to stay below 75% of solid pixels"
        )
    }

    private struct PixelRegion {
        let x: ClosedRange<Int>
        let y: ClosedRange<Int>
    }

    private static var assetRoot: URL {
        resourceRoot.appendingPathComponent("Assets.xcassets")
    }

    private static var resourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SwitchTab/Resources")
    }

    private static func vectorSource() throws -> String {
        let sourceURL = resourceRoot.appendingPathComponent("MenuBarIcon.svg")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func occurrenceCount(of value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private static func menuBarBitmap(named filename: String) throws -> NSBitmapImageRep {
        let imageURL = assetRoot.appendingPathComponent("MenuBarIcon.imageset/\(filename)")
        let data = try Data(contentsOf: imageURL)
        guard let rep = NSBitmapImageRep(data: data) else {
            throw TestFailure.failed("Expected readable menu bar icon bitmap")
        }
        return rep
    }

    private static func opaquePixelCount(
        in region: PixelRegion,
        bitmap: NSBitmapImageRep
    ) -> Int {
        var count = 0
        for y in region.y {
            for x in region.x where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.65 {
                count += 1
            }
        }
        return count
    }

    private static func contentHeight(in bitmap: NSBitmapImageRep) -> Int {
        var minimumY = bitmap.pixelsHigh
        var maximumY = -1

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
            }
        }

        return maximumY >= minimumY ? maximumY - minimumY + 1 : 0
    }

    private static func alphaCounts(in bitmap: NSBitmapImageRep) -> (solid: Int, partial: Int) {
        var solid = 0
        var partial = 0

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if alpha >= 0.99 {
                    solid += 1
                } else if alpha > 0.01 {
                    partial += 1
                }
            }
        }

        return (solid, partial)
    }

}
