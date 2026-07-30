import CoreGraphics

private struct SwitcherIconGridLayout: Equatable {
    let columnCount: Int
    let visibleRowCount: Int
    let logicalRowCount: Int
}

public struct SwitcherOverlayPresentationLayout: Equatable {
    public let size: CGSize
    public let gridColumnCount: Int
    public let requiresSelectionScrolling: Bool
    public let metrics: SwitcherOverlayLayoutMetrics
}

public struct SwitcherOverlayLayoutMetrics: Equatable {
    public let tileSize: CGSize
    public let tileContentPadding: CGFloat
    public let tileContentSpacing: CGFloat
    public let thumbnailSize: CGSize
    public let fallbackIconSize: CGSize
    public let headerIconSize: CGSize
    public let titleFontSize: CGFloat
    public let symbolFontSize: CGFloat
    public let closeButtonSize: CGFloat
    public let closeButtonHitTargetSize: CGSize
    public let gridSpacing: CGFloat
    public let gridPadding: CGFloat
    public let panelPadding: CGFloat

    // Base geometry at scale 1. Every other size is derived from these so the
    // slider stays continuous instead of snapping to hand-tuned presets.
    private static let baseWindowThumbnailSize = CGSize(width: 160, height: 110)
    private static let baseWindowHeaderIconExtent: CGFloat = 18
    private static let baseWindowTileContentPadding: CGFloat = 4
    private static let baseWindowTileContentSpacing: CGFloat = 6
    private static let baseWindowTileVerticalChrome: CGFloat = 30
    private static let baseWindowTitleFontSize: CGFloat = 13
    private static let baseWindowGridSpacing: CGFloat = 14
    private static let baseWindowGridPadding: CGFloat = 28
    private static let baseApplicationTileSize = CGSize(width: 120, height: 128)
    private static let baseApplicationVisualSize = CGSize(width: 108, height: 96)
    private static let baseApplicationIconExtent: CGFloat = 96
    private static let baseApplicationTileContentPadding: CGFloat = 4
    private static let baseApplicationTileContentSpacing: CGFloat = 4
    private static let baseApplicationTitleFontSize: CGFloat = 12
    private static let baseApplicationGridSpacing: CGFloat = 8
    private static let baseApplicationGridPadding: CGFloat = 16
    private static let baseCloseButtonSize: CGFloat = 16
    private static let fallbackIconThumbnailRatio: CGFloat = 0.92

    public static func metrics(
        for scale: OverlaySizeScale,
        mode: SwitcherMode = .currentAppWindowSwitching
    ) -> SwitcherOverlayLayoutMetrics {
        switch mode {
        case .currentAppWindowSwitching:
            windowMetrics(for: scale)
        case .applicationSwitching:
            applicationMetrics(for: scale)
        }
    }

    private static func windowMetrics(for scale: OverlaySizeScale) -> SwitcherOverlayLayoutMetrics {
        let factor = CGFloat(scale.value)
        let thumbnailWidth = scaled(baseWindowThumbnailSize.width, by: factor)
        let thumbnailHeight = scaled(baseWindowThumbnailSize.height, by: factor)
        let headerIconExtent = scaled(baseWindowHeaderIconExtent, by: factor)
        let tileContentPadding = scaled(baseWindowTileContentPadding, by: factor)
        let fallbackIconExtent = (thumbnailHeight * fallbackIconThumbnailRatio).rounded()
        let closeButtonSize = scaled(baseCloseButtonSize, by: factor)
        let closeButtonHitTargetExtent = max(24, closeButtonSize + 8)
        let gridPadding = scaled(baseWindowGridPadding, by: factor)

        return SwitcherOverlayLayoutMetrics(
            tileSize: CGSize(
                width: thumbnailWidth + (tileContentPadding * 2),
                height: thumbnailHeight + headerIconExtent + scaled(baseWindowTileVerticalChrome, by: factor)
            ),
            tileContentPadding: tileContentPadding,
            tileContentSpacing: baseWindowTileContentSpacing,
            thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
            fallbackIconSize: CGSize(width: fallbackIconExtent, height: fallbackIconExtent),
            headerIconSize: CGSize(width: headerIconExtent, height: headerIconExtent),
            titleFontSize: scaled(baseWindowTitleFontSize, by: factor),
            symbolFontSize: (fallbackIconExtent * 0.62).rounded(),
            closeButtonSize: closeButtonSize,
            closeButtonHitTargetSize: CGSize(
                width: closeButtonHitTargetExtent,
                height: closeButtonHitTargetExtent
            ),
            gridSpacing: scaled(baseWindowGridSpacing, by: factor),
            gridPadding: gridPadding,
            panelPadding: gridPadding / 2
        )
    }

    private static func applicationMetrics(for scale: OverlaySizeScale) -> SwitcherOverlayLayoutMetrics {
        let factor = CGFloat(scale.value)
        let iconExtent = scaled(baseApplicationIconExtent, by: factor)
        let closeButtonSize = scaled(baseCloseButtonSize, by: factor)
        let closeButtonHitTargetExtent = max(24, closeButtonSize + 8)
        let gridPadding = scaled(baseApplicationGridPadding, by: factor)

        return SwitcherOverlayLayoutMetrics(
            tileSize: CGSize(
                width: scaled(baseApplicationTileSize.width, by: factor),
                height: scaled(baseApplicationTileSize.height, by: factor)
            ),
            tileContentPadding: scaled(baseApplicationTileContentPadding, by: factor),
            tileContentSpacing: scaled(baseApplicationTileContentSpacing, by: factor),
            thumbnailSize: CGSize(
                width: scaled(baseApplicationVisualSize.width, by: factor),
                height: scaled(baseApplicationVisualSize.height, by: factor)
            ),
            fallbackIconSize: CGSize(width: iconExtent, height: iconExtent),
            headerIconSize: .zero,
            titleFontSize: scaled(baseApplicationTitleFontSize, by: factor),
            symbolFontSize: (iconExtent * 0.62).rounded(),
            closeButtonSize: closeButtonSize,
            closeButtonHitTargetSize: CGSize(
                width: closeButtonHitTargetExtent,
                height: closeButtonHitTargetExtent
            ),
            gridSpacing: scaled(baseApplicationGridSpacing, by: factor),
            gridPadding: gridPadding,
            panelPadding: gridPadding / 2
        )
    }

    private static func scaled(_ value: CGFloat, by factor: CGFloat) -> CGFloat {
        max(1, (value * factor).rounded())
    }
}

public enum SwitcherOverlayLayoutPolicy {
    public static let defaultSize = CGSize(width: 560, height: 420)

    private static let maximumVisibleIconGridRows = 3
    private static let screenHorizontalMargin: CGFloat = 96

    public static func presentationLayout(
        itemCount: Int,
        screenSize: CGSize,
        mode: SwitcherMode = .currentAppWindowSwitching,
        scale: OverlaySizeScale = .default
    ) -> SwitcherOverlayPresentationLayout {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: scale, mode: mode)
        guard itemCount > 2 else {
            let columnCount = itemCount == 2 ? 2 : 1
            return SwitcherOverlayPresentationLayout(
                size: smallItemLayoutSize(columnCount: columnCount, screenSize: screenSize, metrics: metrics),
                gridColumnCount: columnCount,
                requiresSelectionScrolling: false,
                metrics: metrics
            )
        }

        let gridLayout = iconGridLayout(itemCount: itemCount, screenSize: screenSize, metrics: metrics)
        return SwitcherOverlayPresentationLayout(
            size: presentationSize(gridLayout: gridLayout, screenSize: screenSize, metrics: metrics),
            gridColumnCount: gridLayout.columnCount,
            requiresSelectionScrolling: gridLayout.logicalRowCount > gridLayout.visibleRowCount,
            metrics: metrics
        )
    }

    private static func presentationSize(
        gridLayout: SwitcherIconGridLayout,
        screenSize: CGSize,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGSize {
        let availableWidth = max(180, screenSize.width - screenHorizontalMargin)
        let contentWidth = iconGridContentWidth(columnCount: gridLayout.columnCount, metrics: metrics)
        let contentHeight = iconGridContentHeight(rowCount: gridLayout.visibleRowCount, metrics: metrics)
        let width = min(contentWidth, availableWidth)

        return CGSize(width: width.rounded(.up), height: contentHeight.rounded(.up))
    }

    private static func iconGridLayout(
        itemCount: Int,
        screenSize: CGSize,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> SwitcherIconGridLayout {
        guard itemCount > 1 else {
            return SwitcherIconGridLayout(columnCount: 1, visibleRowCount: 1, logicalRowCount: 1)
        }

        if itemCount == 2 {
            return SwitcherIconGridLayout(columnCount: 2, visibleRowCount: 1, logicalRowCount: 1)
        }

        let availableWidth = max(iconGridContentWidth(columnCount: 1, metrics: metrics), screenSize.width - screenHorizontalMargin)
        let maxColumns = max(1, iconGridColumnCount(forOverlayWidth: availableWidth, metrics: metrics))
        let rowsAtMaxWidth = ceilDivision(itemCount, by: maxColumns)
        let visibleRowCount = min(maximumVisibleIconGridRows, max(1, rowsAtMaxWidth))
        let balancedColumns = ceilDivision(itemCount, by: visibleRowCount)
        let columnCount = min(maxColumns, max(1, balancedColumns))
        let logicalRowCount = ceilDivision(itemCount, by: columnCount)

        return SwitcherIconGridLayout(
            columnCount: columnCount,
            visibleRowCount: visibleRowCount,
            logicalRowCount: logicalRowCount
        )
    }

    private static func iconGridColumnCount(
        forOverlayWidth width: CGFloat,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> Int {
        let contentWidth = max(1, width - metrics.gridPadding)
        return max(1, Int(((contentWidth + metrics.gridSpacing) / (metrics.tileSize.width + metrics.gridSpacing)).rounded(.down)))
    }

    private static func iconGridContentWidth(
        columnCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGFloat {
        CGFloat(columnCount) * metrics.tileSize.width
            + CGFloat(max(columnCount - 1, 0)) * metrics.gridSpacing
            + metrics.gridPadding
    }

    private static func iconGridContentHeight(
        rowCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGFloat {
        CGFloat(rowCount) * metrics.tileSize.height
            + CGFloat(max(rowCount - 1, 0)) * metrics.gridSpacing
            + metrics.gridPadding
    }

    private static func smallItemLayoutSize(
        columnCount: Int,
        screenSize: CGSize,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGSize {
        let availableWidth = max(180, screenSize.width - screenHorizontalMargin)
        let width = min(iconGridContentWidth(columnCount: columnCount, metrics: metrics), availableWidth)
        let height = iconGridContentHeight(rowCount: 1, metrics: metrics)
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    private static func ceilDivision(_ numerator: Int, by denominator: Int) -> Int {
        (numerator + denominator - 1) / denominator
    }
}
