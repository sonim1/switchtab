import CoreGraphics
import Foundation
import SwitchTab

enum SwitcherOverlayPresentationTests {
    static func run() throws {
        try testWindowSessionCanUseIconStripPresentation()
        try testOverlayChromeUsesNativeBlurBackground()
        try testWindowModeUsesThumbnailRendering()
        try testIconGridUsesOneRowForFewItems()
        try testWindowModeUsesIconGridLayout()
        try testPresentationLayoutCarriesGridColumnCount()
        try testIconGridWrapsToTwoRowsWhenWidthWouldOverflow()
        try testIconGridCapsAtThreeVisibleRows()
        try testSelectionScrollingOnlyRequiredForOverflowingGrid()
        try testMaximumScaleWindowGridFitsVisibleScreenHeight()
        try testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum()
        try testTwoItemLayoutFitsTwoColumns()
        try testOverlaySizeScaleScalesLayout()
        try testOverlaySizeScaleScalesMultiRowLayout()
        try testOverlaySizeScaleClampsOutOfRangeValues()
        try testPanelPaddingBudgetsGridPaddingAcrossModesAndScales()
        try testDefaultPanelPaddingPreservesWindowInset()
        try testSelectionScrollingPolicyCoversModesAndScales()
        try testLegacyOverlaySizePreferenceMapsOntoScale()
        try testDefaultThumbnailIsLargerThanRetiredLargePreset()
        try testMinimumScaleTileContentFitsWithinTile()
        try testApplicationModeUsesCompactLayoutMetrics()
        try testApplicationCaptionKeepsPanelHeightStable()
        try testApplicationTileSeparatesSelectionContainerFromCaption()
        try testApplicationModeFitsMoreColumnsThanWindowMode()
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
        try expectEqual(layout.size.width, expectedWidth(columnCount: 5))
        try expectEqual(layout.size.height, expectedHeight(rowCount: 1))
    }

    static func testWindowModeUsesIconGridLayout() throws {
        let size = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 4,
            screenSize: CGSize(width: 1440, height: 900)
        ).size

        try expectEqual(size.width, expectedWidth(columnCount: 4))
        try expectEqual(size.height, expectedHeight(rowCount: 1))
    }

    static func testPresentationLayoutCarriesGridColumnCount() throws {
        let presentationLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(presentationLayout.gridColumnCount, 3)
        try expectEqual(presentationLayout.size.width, expectedWidth(columnCount: 3))
        try expectEqual(presentationLayout.size.height, expectedHeight(rowCount: 3))
    }

    static func testIconGridWrapsToTwoRowsWhenWidthWouldOverflow() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 6,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(layout.gridColumnCount, 3)
        try expectEqual(layout.size.height, expectedHeight(rowCount: 2))
    }

    static func testIconGridCapsAtThreeVisibleRows() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 25,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectEqual(layout.size.height, expectedHeight(rowCount: 3))
    }

    static func testSelectionScrollingOnlyRequiredForOverflowingGrid() throws {
        let oneRowLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 5,
            screenSize: CGSize(width: 1440, height: 900)
        )
        let twoRowLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 6,
            screenSize: CGSize(width: 1000, height: 700)
        )
        let threeRowLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700)
        )
        let overflowingLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 25,
            screenSize: CGSize(width: 1000, height: 700)
        )

        try expectFalse(oneRowLayout.requiresSelectionScrolling)
        try expectFalse(twoRowLayout.requiresSelectionScrolling)
        try expectFalse(threeRowLayout.requiresSelectionScrolling)
        try expectTrue(overflowingLayout.requiresSelectionScrolling)
    }

    static func testMaximumScaleWindowGridFitsVisibleScreenHeight() throws {
        let screenSize = CGSize(width: 1000, height: 700)
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: screenSize,
            mode: .currentAppWindowSwitching,
            scale: OverlaySizeScale(OverlaySizeScale.maximum)
        )

        try expectTrue(layout.size.height <= screenSize.height)
        try expectTrue(layout.requiresSelectionScrolling)
    }

    static func testSingleItemLayoutFitsContentInsteadOfUsingWideMinimum() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            scale: .default
        )
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: .default)

        try expectEqual(layout.gridColumnCount, 1)
        try expectEqual(layout.size.width, metrics.tileSize.width + metrics.gridPadding)
        try expectEqual(layout.size.height, metrics.tileSize.height + metrics.gridPadding)
    }

    static func testTwoItemLayoutFitsTwoColumns() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 2,
            screenSize: CGSize(width: 1440, height: 900),
            scale: .default
        )
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: .default)

        try expectEqual(layout.gridColumnCount, 2)
        try expectEqual(
            layout.size.width,
            metrics.tileSize.width * 2 + metrics.gridSpacing + metrics.gridPadding
        )
        try expectEqual(layout.size.height, metrics.tileSize.height + metrics.gridPadding)
    }

    static func testOverlaySizeScaleScalesLayout() throws {
        let small = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            scale: OverlaySizeScale(OverlaySizeScale.minimum)
        )
        let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            scale: .default
        )
        let large = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 1,
            screenSize: CGSize(width: 1440, height: 900),
            scale: OverlaySizeScale(OverlaySizeScale.maximum)
        )

        try expectTrue(small.size.width < standard.size.width)
        try expectTrue(standard.size.width < large.size.width)
        try expectTrue(small.size.height < standard.size.height)
        try expectTrue(standard.size.height < large.size.height)
    }

    static func testOverlaySizeScaleScalesMultiRowLayout() throws {
        let small = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            scale: OverlaySizeScale(OverlaySizeScale.minimum)
        )
        let standard = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            scale: .default
        )
        let large = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 9,
            screenSize: CGSize(width: 1000, height: 700),
            scale: OverlaySizeScale(OverlaySizeScale.maximum)
        )

        // A bigger scale fits fewer columns in the same screen width; total
        // overlay width is not monotonic because the column count changes.
        try expectTrue(small.gridColumnCount > standard.gridColumnCount)
        try expectTrue(standard.gridColumnCount >= large.gridColumnCount)
        try expectEqual(standard.gridColumnCount, 3)

        let smallMetrics = SwitcherOverlayLayoutMetrics.metrics(for: OverlaySizeScale(OverlaySizeScale.minimum))
        let standardMetrics = SwitcherOverlayLayoutMetrics.metrics(for: .default)
        let largeMetrics = SwitcherOverlayLayoutMetrics.metrics(for: OverlaySizeScale(OverlaySizeScale.maximum))

        try expectTrue(smallMetrics.thumbnailSize.width < standardMetrics.thumbnailSize.width)
        try expectTrue(standardMetrics.thumbnailSize.width < largeMetrics.thumbnailSize.width)
    }

    static func testOverlaySizeScaleClampsOutOfRangeValues() throws {
        try expectEqual(OverlaySizeScale(0).value, OverlaySizeScale.minimum)
        try expectEqual(OverlaySizeScale(99).value, OverlaySizeScale.maximum)
        try expectEqual(OverlaySizeScale(.nan).value, 1)
        try expectEqual(OverlaySizeScale.default.value, 1)
        try expectEqual(OverlaySizeScale(1.2).percentageText, "120%")
    }

    static func testPanelPaddingBudgetsGridPaddingAcrossModesAndScales() throws {
        let scales = [
            OverlaySizeScale(OverlaySizeScale.minimum),
            OverlaySizeScale.default,
            OverlaySizeScale(OverlaySizeScale.maximum)
        ]
        let modes: [SwitcherMode] = [
            .currentAppWindowSwitching,
            .applicationSwitching
        ]

        for mode in modes {
            for scale in scales {
                let metrics = SwitcherOverlayLayoutMetrics.metrics(for: scale, mode: mode)
                try expectTrue(metrics.panelPadding * 2 <= metrics.gridPadding)
            }
        }
    }

    static func testDefaultPanelPaddingPreservesWindowInset() throws {
        let windowMetrics = SwitcherOverlayLayoutMetrics.metrics(
            for: .default,
            mode: .currentAppWindowSwitching
        )
        let applicationMetrics = SwitcherOverlayLayoutMetrics.metrics(
            for: .default,
            mode: .applicationSwitching
        )

        try expectEqual(windowMetrics.panelPadding, 12)
        try expectEqual(applicationMetrics.panelPadding * 2, applicationMetrics.gridPadding)
    }

    static func testSelectionScrollingPolicyCoversModesAndScales() throws {
        let scales = [
            OverlaySizeScale(OverlaySizeScale.minimum),
            OverlaySizeScale.default,
            OverlaySizeScale(OverlaySizeScale.maximum)
        ]
        let modes: [SwitcherMode] = [
            .currentAppWindowSwitching,
            .applicationSwitching
        ]

        for mode in modes {
            for scale in scales {
                let boundedLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
                    itemCount: 9,
                    screenSize: CGSize(width: 1000, height: 700),
                    mode: mode,
                    scale: scale
                )
                let overflowingLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
                    itemCount: 40,
                    screenSize: CGSize(width: 1000, height: 700),
                    mode: mode,
                    scale: scale
                )

                let heightLimitedWindowLayout = mode == .currentAppWindowSwitching
                    && scale.value == OverlaySizeScale.maximum
                try expectEqual(
                    boundedLayout.requiresSelectionScrolling,
                    heightLimitedWindowLayout
                )
                try expectTrue(overflowingLayout.requiresSelectionScrolling)
            }
        }
    }

    static func testLegacyOverlaySizePreferenceMapsOntoScale() throws {
        try expectTrue(OverlaySizePreference.compact.scale.value < OverlaySizePreference.standard.scale.value)
        try expectTrue(OverlaySizePreference.standard.scale.value < OverlaySizePreference.large.scale.value)
        try expectEqual(OverlaySizePreference.standard.scale, .default)
    }

    static func testDefaultThumbnailIsLargerThanRetiredLargePreset() throws {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: .default)

        // The retired `.large` preset used a 144x100 thumbnail; the new default
        // must be roomier than that, per the bigger-by-default requirement.
        try expectTrue(metrics.thumbnailSize.width > 144)
        try expectTrue(metrics.thumbnailSize.height > 100)
        try expectEqual(metrics.tileSize.width, metrics.thumbnailSize.width + 8)
        try expectTrue(metrics.fallbackIconSize.height <= metrics.thumbnailSize.height)
        try expectTrue(metrics.titleFontSize > 0)
        try expectTrue(metrics.symbolFontSize > 0)
    }

    static func testMinimumScaleTileContentFitsWithinTile() throws {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(
            for: OverlaySizeScale(OverlaySizeScale.minimum)
        )
        let contentWidth = metrics.thumbnailSize.width + (metrics.tileContentPadding * 2)

        try expectTrue(
            metrics.tileSize.width >= contentWidth,
            "Minimum-scale tile width must contain the thumbnail and its content padding."
        )
    }

    static func testApplicationModeUsesCompactLayoutMetrics() throws {
        let windowMetrics = SwitcherOverlayLayoutMetrics.metrics(
            for: .default,
            mode: .currentAppWindowSwitching
        )
        let applicationMetrics = SwitcherOverlayLayoutMetrics.metrics(
            for: .default,
            mode: .applicationSwitching
        )

        try expectEqual(windowMetrics.tileSize, CGSize(width: 168, height: 158))
        try expectEqual(windowMetrics.tileContentSpacing, 6)
        try expectEqual(windowMetrics.gridSpacing, 14)
        try expectEqual(windowMetrics.gridPadding, 28)
        try expectEqual(applicationMetrics.tileSize, CGSize(width: 104, height: 119))
        try expectEqual(applicationMetrics.thumbnailSize, CGSize(width: 96, height: 96))
        try expectEqual(applicationMetrics.fallbackIconSize, CGSize(width: 96, height: 96))
        try expectEqual(applicationMetrics.selectionContainerSize, CGSize(width: 104, height: 104))
        try expectEqual(applicationMetrics.selectionCornerRadius, 26)
        try expectEqual(applicationMetrics.captionHeight, 14)
        try expectEqual(applicationMetrics.captionMaxWidth, 240)
        try expectEqual(applicationMetrics.tileContentSpacing, 1)
        try expectEqual(applicationMetrics.gridSpacing, 4)
        try expectEqual(applicationMetrics.gridPadding, 16)
        try expectTrue(applicationMetrics.tileSize.width < windowMetrics.tileSize.width)
        try expectEqual(
            SwitcherOverlayLayoutMetrics.metrics(
                for: OverlaySizeScale(OverlaySizeScale.maximum),
                mode: .currentAppWindowSwitching
            ).tileContentSpacing,
            6
        )
    }

    static func testApplicationCaptionKeepsPanelHeightStable() throws {
        let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 8,
            screenSize: CGSize(width: 1440, height: 900),
            mode: .applicationSwitching
        )

        try expectEqual(layout.metrics.tileSize.height, 119)
        try expectEqual(
            layout.metrics.selectionContainerSize.height
                + layout.metrics.tileContentSpacing
                + layout.metrics.captionHeight,
            layout.metrics.tileSize.height
        )
    }

    static func testApplicationTileSeparatesSelectionContainerFromCaption() throws {
        let sourceURL = projectRoot
            .appendingPathComponent("SwitchTab/UI/Overlay/SwitcherIconStripView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try expectTrue(source.contains("applicationIconSelection(for: item)"))
        try expectTrue(source.contains("ApplicationSwitcherMetadataPolicy.presentation("))
        try expectTrue(source.contains(".frame(height: layoutMetrics.captionHeight)"))
        try expectTrue(source.contains("cornerRadius: layoutMetrics.selectionCornerRadius"))
    }

    static func testApplicationModeFitsMoreColumnsThanWindowMode() throws {
        let windowLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 16,
            screenSize: CGSize(width: 1440, height: 900),
            mode: .currentAppWindowSwitching
        )
        let applicationLayout = SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: 16,
            screenSize: CGSize(width: 1440, height: 900),
            mode: .applicationSwitching
        )

        try expectTrue(applicationLayout.gridColumnCount > windowLayout.gridColumnCount)
    }

    private static func expectedWidth(
        columnCount: Int,
        scale: OverlaySizeScale = .default
    ) -> CGFloat {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: scale)
        return CGFloat(columnCount) * metrics.tileSize.width
            + CGFloat(columnCount - 1) * metrics.gridSpacing
            + metrics.gridPadding
    }

    private static func expectedHeight(
        rowCount: Int,
        scale: OverlaySizeScale = .default
    ) -> CGFloat {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: scale)
        return CGFloat(rowCount) * metrics.tileSize.height
            + CGFloat(rowCount - 1) * metrics.gridSpacing
            + metrics.gridPadding
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
