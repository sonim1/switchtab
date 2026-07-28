import CoreGraphics

private struct SwitcherIconGridLayout: Equatable {
    let columnCount: Int
    let visibleRowCount: Int
}

public struct SwitcherOverlayPresentationLayout: Equatable {
    public let size: CGSize
    public let gridColumnCount: Int
    public let metrics: SwitcherOverlayLayoutMetrics
}

public struct SwitcherOverlayLayoutMetrics: Equatable {
    public let tileSize: CGSize
    public let tileContentPadding: CGFloat
    public let thumbnailSize: CGSize
    public let fallbackIconSize: CGSize
    public let headerIconSize: CGSize
    public let titleFontSize: CGFloat
    public let symbolFontSize: CGFloat
    public let closeButtonSize: CGFloat
    public let closeButtonHitTargetSize: CGSize
    public let gridSpacing: CGFloat
    public let gridPadding: CGFloat

    // Base geometry at scale 1. Every other size is derived from these so the
    // slider stays continuous instead of snapping to hand-tuned presets.
    private static let baseThumbnailSize = CGSize(width: 160, height: 110)
    private static let baseHeaderIconExtent: CGFloat = 18
    private static let baseTileContentPadding: CGFloat = 4
    private static let baseTileVerticalChrome: CGFloat = 30
    private static let baseTitleFontSize: CGFloat = 13
    private static let baseCloseButtonSize: CGFloat = 16
    private static let baseGridSpacing: CGFloat = 14
    private static let baseGridPadding: CGFloat = 28
    private static let fallbackIconThumbnailRatio: CGFloat = 0.92

    public static func metrics(for scale: OverlaySizeScale) -> SwitcherOverlayLayoutMetrics {
        let factor = CGFloat(scale.value)
        let thumbnailWidth = scaled(baseThumbnailSize.width, by: factor)
        let thumbnailHeight = scaled(baseThumbnailSize.height, by: factor)
        let headerIconExtent = scaled(baseHeaderIconExtent, by: factor)
        let tileContentPadding = scaled(baseTileContentPadding, by: factor)
        let fallbackIconExtent = (thumbnailHeight * fallbackIconThumbnailRatio).rounded()
        let closeButtonSize = scaled(baseCloseButtonSize, by: factor)
        let closeButtonHitTargetExtent = max(24, closeButtonSize + 8)

        return SwitcherOverlayLayoutMetrics(
            tileSize: CGSize(
                width: thumbnailWidth + (tileContentPadding * 2),
                height: thumbnailHeight + headerIconExtent + scaled(baseTileVerticalChrome, by: factor)
            ),
            tileContentPadding: tileContentPadding,
            thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
            fallbackIconSize: CGSize(width: fallbackIconExtent, height: fallbackIconExtent),
            headerIconSize: CGSize(width: headerIconExtent, height: headerIconExtent),
            titleFontSize: scaled(baseTitleFontSize, by: factor),
            symbolFontSize: (fallbackIconExtent * 0.62).rounded(),
            closeButtonSize: closeButtonSize,
            closeButtonHitTargetSize: CGSize(
                width: closeButtonHitTargetExtent,
                height: closeButtonHitTargetExtent
            ),
            gridSpacing: scaled(baseGridSpacing, by: factor),
            gridPadding: scaled(baseGridPadding, by: factor)
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
        scale: OverlaySizeScale = .default
    ) -> SwitcherOverlayPresentationLayout {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: scale)
        guard itemCount > 2 else {
            let columnCount = itemCount == 2 ? 2 : 1
            return SwitcherOverlayPresentationLayout(
                size: smallItemLayoutSize(columnCount: columnCount, screenSize: screenSize, metrics: metrics),
                gridColumnCount: columnCount,
                metrics: metrics
            )
        }

        let gridLayout = iconGridLayout(itemCount: itemCount, screenSize: screenSize, metrics: metrics)
        return SwitcherOverlayPresentationLayout(
            size: presentationSize(gridLayout: gridLayout, screenSize: screenSize, metrics: metrics),
            gridColumnCount: gridLayout.columnCount,
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
            return SwitcherIconGridLayout(columnCount: 1, visibleRowCount: 1)
        }

        if itemCount == 2 {
            return SwitcherIconGridLayout(columnCount: 2, visibleRowCount: 1)
        }

        let availableWidth = max(iconGridContentWidth(columnCount: 1, metrics: metrics), screenSize.width - screenHorizontalMargin)
        let maxColumns = max(1, iconGridColumnCount(forOverlayWidth: availableWidth, metrics: metrics))
        let rowsAtMaxWidth = ceilDivision(itemCount, by: maxColumns)
        let visibleRowCount = min(maximumVisibleIconGridRows, max(1, rowsAtMaxWidth))
        let balancedColumns = ceilDivision(itemCount, by: visibleRowCount)
        let columnCount = min(maxColumns, max(1, balancedColumns))

        return SwitcherIconGridLayout(
            columnCount: columnCount,
            visibleRowCount: visibleRowCount
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
