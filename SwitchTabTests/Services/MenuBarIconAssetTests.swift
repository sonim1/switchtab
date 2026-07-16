import AppKit
import Foundation

enum MenuBarIconAssetTests {
    static func run() throws {
        try testMenuBarIconUsesTemplateRendering()
        try testMenuBarIconUsesMenuBarScaleAssets()
        try testMenuBarIconKeepsVectorSource()
        try testMenuBarIconMatchesProvidedHGridStructure()
        try testMenuBarIconKeepsActiveTileInteriorOpen()
        try testMenuBarIconLeavesGridGuttersOpen()
    }

    static func testMenuBarIconUsesTemplateRendering() throws {
        let contentsURL = assetRoot
            .appendingPathComponent("MenuBarIcon.imageset/Contents.json")
        let contents = try String(contentsOf: contentsURL, encoding: .utf8)

        try expectTrue(contents.contains("\"template-rendering-intent\" : \"template\""))
    }

    static func testMenuBarIconUsesMenuBarScaleAssets() throws {
        let oneX = try menuBarBitmap(named: "MenuBarIcon.png")
        let threeX = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectEqual(oneX.pixelsWide, 18)
        try expectEqual(oneX.pixelsHigh, 18)
        try expectEqual(threeX.pixelsWide, 54)
        try expectEqual(threeX.pixelsHigh, 54)
    }

    static func testMenuBarIconKeepsVectorSource() throws {
        let sourceURL = resourceRoot.appendingPathComponent("MenuBarIcon.svg")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains("viewBox=\"0 0 380 372\""))
        try expectTrue(source.contains("SwitchTab H icon vectorized from provided image"))
    }

    static func testMenuBarIconMatchesProvidedHGridStructure() throws {
        let rep = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 4...21, y: 6...24), bitmap: rep) >= 240,
            "Expected the top-left filled tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 26...44, y: 6...21), bitmap: rep) >= 210,
            "Expected the top-right filled tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 4...21, y: 27...45), bitmap: rep) >= 230,
            "Expected the bottom-left filled tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 25...49, y: 23...29), bitmap: rep) >= 54,
            "Expected the top edge of the active outline tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 25...49, y: 42...48), bitmap: rep) >= 48,
            "Expected the bottom edge of the active outline tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 24...31, y: 24...47), bitmap: rep) >= 54,
            "Expected the left edge of the active outline tile from the H reference"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 43...50, y: 24...47), bitmap: rep) >= 48,
            "Expected the right edge of the active outline tile from the H reference"
        )
    }

    static func testMenuBarIconKeepsActiveTileInteriorOpen() throws {
        let rep = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 30...43, y: 30...43), bitmap: rep) <= 30,
            "Expected the active tile interior to stay open"
        )
    }

    static func testMenuBarIconLeavesGridGuttersOpen() throws {
        let rep = try menuBarBitmap(named: "MenuBarIcon@3x.png")

        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 22...25, y: 6...45), bitmap: rep) <= 70,
            "Expected the vertical gutter between H reference columns to stay open"
        )
        try expectTrue(
            opaquePixelCount(in: PixelRegion(x: 4...50, y: 25...26), bitmap: rep) <= 42,
            "Expected the horizontal gutter between H reference rows to stay open"
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

}
