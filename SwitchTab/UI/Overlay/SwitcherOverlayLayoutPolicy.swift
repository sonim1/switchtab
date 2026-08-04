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
    public let selectionContainerSize: CGSize
    public let selectionCornerRadius: CGFloat
    public let captionHeight: CGFloat
    public let captionMaxWidth: CGFloat
    public let headerIconSize: CGSize
    public let titleFontSize: CGFloat
    public let symbolFontSize: CGFloat
    public let closeButtonSize: CGFloat
    public let closeButtonHitTargetSize: CGSize
    public let gridSpacing: CGFloat
    public let panelHorizontalPadding: CGFloat
    public let panelTopPadding: CGFloat
    public let panelBottomPadding: CGFloat

    // Base geometry at scale 1. Every other size is derived from these so the
    // slider stays continuous instead of snapping to hand-tuned presets.
    private static let baseWindowThumbnailSize = CGSize(width: 160, height: 110)
    private static let baseWindowHeaderIconExtent: CGFloat = 18
    private static let baseWindowTileContentPadding: CGFloat = 4
    private static let baseWindowTileContentSpacing: CGFloat = 6
    private static let baseWindowTitleFontSize: CGFloat = 13
    private static let baseWindowGridSpacing: CGFloat = 14
    private static let baseWindowPanelHorizontalPadding: CGFloat = 10
    private static let baseWindowPanelTopPadding: CGFloat = 8
    private static let baseWindowPanelBottomPadding: CGFloat = 8
    private static let baseApplicationSelectionExtent: CGFloat = 100
    private static let baseApplicationIconExtent: CGFloat = 96
    private static let baseApplicationCaptionHeight: CGFloat = 14
    private static let baseApplicationCaptionMaxWidth: CGFloat = 240
    private static let baseApplicationTileContentSpacing: CGFloat = 1
    private static let baseApplicationSelectionCornerRadius: CGFloat = 26
    private static let baseApplicationTitleFontSize: CGFloat = 12
    private static let baseApplicationGridSpacing: CGFloat = 4
    private static let baseApplicationPanelHorizontalPadding: CGFloat = 10
    private static let baseApplicationPanelTopPadding: CGFloat = 8
    private static let baseApplicationPanelBottomPadding: CGFloat = 0
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
        let tileSize = CGSize(
            width: thumbnailWidth + (tileContentPadding * 2),
            height: thumbnailHeight + headerIconExtent + baseWindowTileContentSpacing
        )

        return SwitcherOverlayLayoutMetrics(
            tileSize: tileSize,
            tileContentPadding: tileContentPadding,
            tileContentSpacing: baseWindowTileContentSpacing,
            thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
            fallbackIconSize: CGSize(width: fallbackIconExtent, height: fallbackIconExtent),
            selectionContainerSize: tileSize,
            selectionCornerRadius: 7,
            captionHeight: 0,
            captionMaxWidth: 0,
            headerIconSize: CGSize(width: headerIconExtent, height: headerIconExtent),
            titleFontSize: scaled(baseWindowTitleFontSize, by: factor),
            symbolFontSize: (fallbackIconExtent * 0.62).rounded(),
            closeButtonSize: closeButtonSize,
            closeButtonHitTargetSize: CGSize(
                width: closeButtonHitTargetExtent,
                height: closeButtonHitTargetExtent
            ),
            gridSpacing: scaled(baseWindowGridSpacing, by: factor),
            panelHorizontalPadding: scaled(baseWindowPanelHorizontalPadding, by: factor),
            panelTopPadding: scaled(baseWindowPanelTopPadding, by: factor),
            panelBottomPadding: scaled(baseWindowPanelBottomPadding, by: factor)
        )
    }

    private static func applicationMetrics(for scale: OverlaySizeScale) -> SwitcherOverlayLayoutMetrics {
        let factor = CGFloat(scale.value)
        let iconExtent = scaled(baseApplicationIconExtent, by: factor)
        let selectionExtent = scaled(baseApplicationSelectionExtent, by: factor)
        let captionHeight = scaled(baseApplicationCaptionHeight, by: factor)
        let contentSpacing = scaled(baseApplicationTileContentSpacing, by: factor)
        let closeButtonSize = scaled(baseCloseButtonSize, by: factor)
        let closeButtonHitTargetExtent = max(24, closeButtonSize + 8)
        return SwitcherOverlayLayoutMetrics(
            tileSize: CGSize(
                width: selectionExtent,
                height: selectionExtent + contentSpacing + captionHeight
            ),
            tileContentPadding: 0,
            tileContentSpacing: contentSpacing,
            thumbnailSize: CGSize(width: iconExtent, height: iconExtent),
            fallbackIconSize: CGSize(width: iconExtent, height: iconExtent),
            selectionContainerSize: CGSize(width: selectionExtent, height: selectionExtent),
            selectionCornerRadius: scaled(baseApplicationSelectionCornerRadius, by: factor),
            captionHeight: captionHeight,
            captionMaxWidth: scaled(baseApplicationCaptionMaxWidth, by: factor),
            headerIconSize: .zero,
            titleFontSize: scaled(baseApplicationTitleFontSize, by: factor),
            symbolFontSize: (iconExtent * 0.62).rounded(),
            closeButtonSize: closeButtonSize,
            closeButtonHitTargetSize: CGSize(
                width: closeButtonHitTargetExtent,
                height: closeButtonHitTargetExtent
            ),
            gridSpacing: scaled(baseApplicationGridSpacing, by: factor),
            panelHorizontalPadding: scaled(baseApplicationPanelHorizontalPadding, by: factor),
            panelTopPadding: scaled(baseApplicationPanelTopPadding, by: factor),
            panelBottomPadding: baseApplicationPanelBottomPadding
        )
    }

    private static func scaled(_ value: CGFloat, by factor: CGFloat) -> CGFloat {
        max(1, (value * factor).rounded())
    }
}

public enum ApplicationSwitcherCaptionAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

public enum ApplicationSwitcherCaptionLayoutPolicy {
    public static func width(
        columnCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGFloat {
        guard columnCount > 1 else {
            return metrics.captionMaxWidth
        }

        let gridSpan = CGFloat(columnCount) * metrics.tileSize.width
            + CGFloat(columnCount - 1) * metrics.gridSpacing
        return min(metrics.captionMaxWidth, gridSpan)
    }

    public static func alignment(
        index: Int,
        columnCount: Int
    ) -> ApplicationSwitcherCaptionAlignment {
        guard columnCount > 1 else {
            return .center
        }

        switch index % columnCount {
        case 0:
            return .leading
        case columnCount - 1:
            return .trailing
        default:
            return .center
        }
    }
}

public enum SwitcherOverlayLayoutPolicy {
    public static let defaultSize = CGSize(width: 560, height: 420)

    private static let maximumVisibleIconGridRows = 3
    private static let screenHorizontalMargin: CGFloat = 96
    private static let screenVerticalMargin: CGFloat = 48

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
        let height = min(contentHeight, availableScreenHeight(screenSize: screenSize))

        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
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
        let visibleRowCount = min(
            maximumVisibleIconGridRows,
            maximumRowsThatFit(screenSize: screenSize, metrics: metrics),
            max(1, rowsAtMaxWidth)
        )
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
        let contentWidth = max(1, width - metrics.panelHorizontalPadding * 2)
        return max(1, Int(((contentWidth + metrics.gridSpacing) / (metrics.tileSize.width + metrics.gridSpacing)).rounded(.down)))
    }

    private static func iconGridContentWidth(
        columnCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGFloat {
        CGFloat(columnCount) * metrics.tileSize.width
            + CGFloat(max(columnCount - 1, 0)) * metrics.gridSpacing
            + metrics.panelHorizontalPadding * 2
    }

    private static func iconGridContentHeight(
        rowCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGFloat {
        CGFloat(rowCount) * metrics.tileSize.height
            + CGFloat(max(rowCount - 1, 0)) * metrics.gridSpacing
            + metrics.panelTopPadding
            + metrics.panelBottomPadding
    }

    private static func maximumRowsThatFit(
        screenSize: CGSize,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> Int {
        let availableHeight = availableScreenHeight(screenSize: screenSize)
        let rowBudget = max(
            0,
            availableHeight - metrics.panelTopPadding - metrics.panelBottomPadding
        )
        return max(
            1,
            Int(((rowBudget + metrics.gridSpacing) / (metrics.tileSize.height + metrics.gridSpacing)).rounded(.down))
        )
    }

    private static func availableScreenHeight(screenSize: CGSize) -> CGFloat {
        max(1, screenSize.height - screenVerticalMargin)
    }

    private static func smallItemLayoutSize(
        columnCount: Int,
        screenSize: CGSize,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> CGSize {
        let availableWidth = max(180, screenSize.width - screenHorizontalMargin)
        let gridWidth = iconGridContentWidth(columnCount: columnCount, metrics: metrics)
        let captionSafeWidth = metrics.captionMaxWidth + metrics.panelHorizontalPadding * 2
        let desiredWidth = columnCount == 1 && metrics.captionHeight > 0
            ? max(gridWidth, captionSafeWidth)
            : gridWidth
        let width = min(desiredWidth, availableWidth)
        let height = min(
            iconGridContentHeight(rowCount: 1, metrics: metrics),
            availableScreenHeight(screenSize: screenSize)
        )
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    private static func ceilDivision(_ numerator: Int, by denominator: Int) -> Int {
        (numerator + denominator - 1) / denominator
    }
}
