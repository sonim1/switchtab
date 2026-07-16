import CoreGraphics
import Foundation
import SwitchTab

enum SwitcherOverlayPresentationTests {
    static func run() throws {
        try testWindowSessionCanUseIconStripPresentation()
        try testOverlayChromeUsesReducedPadding()
        try testOverlayChromeUsesNativeBlurBackground()
        try testWindowModeUsesThumbnailRendering()
        try testIconGridUsesOneRowForFewItems()
        try testWindowModeUsesIconGridLayout()
        try testPresentationLayoutCarriesGridColumnCount()
        try testIconGridWrapsToTwoRowsWhenWidthWouldOverflow()
        try testIconGridCapsAtThreeVisibleRows()
        try testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum()
        try testTwoItemLayoutFitsTwoColumns()
        try testOverlaySizePreferenceScalesLayout()
        try testOverlaySizePreferenceScalesMultiRowLayout()
        try testWindowTileButtonsExposeExplicitAccessibilityText()
    }

    static func testWindowSessionCanUseIconStripPresentation() throws {
        var state = SwitcherOverlayState()

        state.present(
            mode: .currentAppWindowSwitching,
            items: [SwitcherListItem(id: "finder", title: "Finder", subtitle: nil)]
        )

        try expectEqual(state.session?.mode, .currentAppWindowSwitching)
        try expectEqual(state.session?.items.first?.id, "finder")
    }

    static func testOverlayChromeUsesReducedPadding() throws {
        try expectEqual(SwitcherOverlayChromePolicy.panelPadding, 12)
    }

    static func testOverlayChromeUsesNativeBlurBackground() throws {
        try expectTrue(SwitcherOverlayChromePolicy.usesNativeBlurBackground)
    }

    static func testWindowModeUsesThumbnailRendering() throws {
        try expectTrue(SwitcherOverlayThumbnailPolicy.showsThumbnails(for: .currentAppWindowSwitching))
    }

    static func testIconGridUsesOneRowForFewItems() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 5,
            screenSize: CGSize(width: 1440, height: 900)
        )

        try expectEqual(layout.gridColumnCount, 5)
        try expectEqual(layout.size.width, 712)
        try expectEqual(layout.size.height, 148)
    }

    static func testWindowModeUsesIconGridLayout() throws {
        let size = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 4,
            screenSize: CGSize(width: 1440, height: 900)
        ).size

        try expectEqual(size.width, 572)
        try expectEqual(size.height, 148)
    }

    static func testPresentationLayoutCarriesGridColumnCount() throws {
        let presentationLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(presentationLayout.size.width, 712)
        try expectEqual(presentationLayout.size.height, 284)
        try expectEqual(presentationLayout.gridColumnCount, 5)
    }

    static func testIconGridWrapsToTwoRowsWhenWidthWouldOverflow() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(layout.gridColumnCount, 5)
        try expectEqual(layout.size.width, 712)
        try expectEqual(layout.size.height, 284)
    }

    static func testIconGridCapsAtThreeVisibleRows() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 25,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(layout.gridColumnCount, 6)
        try expectEqual(layout.size.width, 852)
        try expectEqual(layout.size.height, 420)
    }

    static func testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            overlaySize: .standard
        )

        try expectEqual(layout.gridColumnCount, 1)
        try expectEqual(layout.size.width, 152)
        try expectEqual(layout.size.height, 148)
    }

    static func testTwoItemLayoutFitsTwoColumns() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 2,
            screenSize: CGSize(width: 1440, height: 900),
            overlaySize: .standard
        )

        try expectEqual(layout.gridColumnCount, 2)
        try expectEqual(layout.size.width, 292)
        try expectEqual(layout.size.height, 148)
    }

    static func testOverlaySizePreferenceScalesLayout() throws {
        let compact = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            overlaySize: .compact
        )
        let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            overlaySize: .standard
        )
        let large = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            overlaySize: .large
        )

        try expectEqual(compact.size.width, 132)
        try expectEqual(compact.size.height, 132)
        try expectEqual(standard.size.width, 152)
        try expectEqual(standard.size.height, 148)
        try expectEqual(large.size.width, 180)
        try expectEqual(large.size.height, 176)
    }

    static func testOverlaySizePreferenceScalesMultiRowLayout() throws {
        let compact = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            overlaySize: .compact
        )
        let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            overlaySize: .standard
        )
        let large = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            overlaySize: .large
        )

        try expectTrue(compact.size.width < standard.size.width)
        try expectTrue(standard.size.width < large.size.width)
        try expectTrue(compact.size.height < standard.size.height)
        try expectTrue(standard.size.height < large.size.height)
        try expectEqual(standard.gridColumnCount, 5)
    }

    static func testWindowTileButtonsExposeExplicitAccessibilityText() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("SwitchTab/UI/Overlay/SwitcherIconStripView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains(".accessibilityLabel(Text(item.title))"))
        try expectTrue(source.contains(".accessibilityHint(Text(\"Switch to this window.\"))"))
    }

}
