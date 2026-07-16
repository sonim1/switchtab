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
    public let thumbnailSize: CGSize
    public let fallbackIconSize: CGSize
    public let headerIconSize: CGSize
    public let gridSpacing: CGFloat
    public let gridPadding: CGFloat

    public static func metrics(for overlaySize: OverlaySizePreference) -> SwitcherOverlayLayoutMetrics {
        switch overlaySize {
        case .compact:
            return SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 112, height: 112),
                thumbnailSize: CGSize(width: 104, height: 72),
                fallbackIconSize: CGSize(width: 76, height: 76),
                headerIconSize: CGSize(width: 14, height: 14),
                gridSpacing: 10,
                gridPadding: 20
            )
        case .standard:
            return SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 128, height: 124),
                thumbnailSize: CGSize(width: 120, height: 84),
                fallbackIconSize: CGSize(width: 88, height: 88),
                headerIconSize: CGSize(width: 16, height: 16),
                gridSpacing: 12,
                gridPadding: 24
            )
        case .large:
            return SwitcherOverlayLayoutMetrics(
                tileSize: CGSize(width: 152, height: 148),
                thumbnailSize: CGSize(width: 144, height: 100),
                fallbackIconSize: CGSize(width: 104, height: 104),
                headerIconSize: CGSize(width: 18, height: 18),
                gridSpacing: 14,
                gridPadding: 28
            )
        }
    }
}

public enum SwitcherOverlayLayoutPolicy {
    public static let defaultSize = CGSize(width: 560, height: 420)

    private static let maximumVisibleIconGridRows = 3
    private static let screenHorizontalMargin: CGFloat = 96

    public static func presentationLayout(
        itemCount: Int,
        screenSize: CGSize,
        overlaySize: OverlaySizePreference = .standard
    ) -> SwitcherOverlayPresentationLayout {
        let metrics = SwitcherOverlayLayoutMetrics.metrics(for: overlaySize)
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
