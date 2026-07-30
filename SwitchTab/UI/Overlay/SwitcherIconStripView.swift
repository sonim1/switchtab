import AppKit
import SwiftUI

struct SwitcherIconStripView: View {
    private let items: [SwitcherListItem]
    private let selectedIndex: Int
    private let mode: SwitcherMode
    private let showsCloseControl: Bool
    private let switchAccessibilityHint: String
    private let onConfirm: (SwitcherListItem, Int) -> Void
    private let onClose: (SwitcherListItem, Int) -> Void
    private let onHover: (Int) -> Void
    private let hoverEnabled: Bool
    private let scrollToken: Int
    private let requiresSelectionScrolling: Bool
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore
    private let gridColumns: [GridItem]
    private let layoutMetrics: SwitcherOverlayLayoutMetrics

    init(
        items: [SwitcherListItem],
        selectedIndex: Int,
        gridColumns: [GridItem],
        layoutMetrics: SwitcherOverlayLayoutMetrics,
        mode: SwitcherMode,
        showsCloseControl: Bool = true,
        switchAccessibilityHint: String = "Switch to this window.",
        hoverEnabled: Bool,
        scrollToken: Int,
        requiresSelectionScrolling: Bool = true,
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore,
        onConfirm: @escaping (SwitcherListItem, Int) -> Void,
        onClose: @escaping (SwitcherListItem, Int) -> Void,
        onHover: @escaping (Int) -> Void
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.gridColumns = gridColumns
        self.layoutMetrics = layoutMetrics
        self.mode = mode
        self.showsCloseControl = showsCloseControl
        self.switchAccessibilityHint = switchAccessibilityHint
        self.hoverEnabled = hoverEnabled
        self.scrollToken = scrollToken
        self.requiresSelectionScrolling = requiresSelectionScrolling
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore
        self.onConfirm = onConfirm
        self.onClose = onClose
        self.onHover = onHover
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: layoutMetrics.gridSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { indexedItem in
                            let index = indexedItem.offset
                            let item = indexedItem.element
                            SwitcherWindowTile(
                                item: item,
                                index: index,
                                isSelected: index == selectedIndex,
                                mode: mode,
                                showsCloseControl: showsCloseControl,
                                switchAccessibilityHint: switchAccessibilityHint,
                                hoverEnabled: hoverEnabled,
                                layoutMetrics: layoutMetrics,
                                thumbnailStore: thumbnailStore,
                                applicationIconStore: applicationIconStore,
                                onConfirm: onConfirm,
                                onClose: onClose,
                                onHover: onHover
                            )
                            .id(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    scrollToSelected(using: proxy)
                }
                .onChange(of: scrollToken) {
                    scrollToSelected(using: proxy)
                }
            }
        }
    }

    static func gridColumns(
        columnCount: Int,
        metrics: SwitcherOverlayLayoutMetrics
    ) -> [GridItem] {
        guard columnCount > 0 else {
            return []
        }

        return Array(
            repeating: GridItem(.fixed(metrics.tileSize.width), spacing: metrics.gridSpacing),
            count: columnCount
        )
    }

    private func scrollToSelected(using proxy: ScrollViewProxy) {
        guard requiresSelectionScrolling, items.count > 1 else {
            return
        }

        guard selectedIndex >= 0 && selectedIndex < items.count else {
            return
        }

        proxy.scrollTo(items[selectedIndex].id, anchor: .center)
    }
}

private struct SwitcherWindowTile: View {
    let item: SwitcherListItem
    let index: Int
    let isSelected: Bool
    let mode: SwitcherMode
    let showsCloseControl: Bool
    let switchAccessibilityHint: String
    let hoverEnabled: Bool
    let layoutMetrics: SwitcherOverlayLayoutMetrics
    let thumbnailStore: WindowThumbnailStore
    let applicationIconStore: ApplicationIconStore
    let onConfirm: (SwitcherListItem, Int) -> Void
    let onClose: (SwitcherListItem, Int) -> Void
    let onHover: (Int) -> Void

    @State private var isCloseButtonHovered = false
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onConfirm(item, index)
            } label: {
                tileContent(for: item)
                .padding(layoutMetrics.tileContentPadding)
                .frame(
                    width: layoutMetrics.tileSize.width,
                    height: layoutMetrics.tileSize.height
                )
                .background(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.95) : Color.clear,
                            lineWidth: 2
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(SwitcherOverlayAccessibilityPolicy.switchLabel(for: item, mode: mode))
            )
            .accessibilityHint(Text(switchAccessibilityHint))

            if showsCloseControl && (isSelected || isHovered) {
                closeButton
            }
        }
        .onHover { hovering in
            isHovered = hovering
            reportHoverIfActive(hovering)
        }
        .onChange(of: hoverEnabled) {
            // The overlay can appear under a stationary pointer; the tile only
            // claims the selection once hovering has been unlocked by a move.
            reportHoverIfActive(isHovered)
        }
    }

    private func reportHoverIfActive(_ hovering: Bool) {
        guard hoverEnabled, hovering else {
            return
        }

        onHover(index)
    }

    @ViewBuilder
    private func tileContent(for item: SwitcherListItem) -> some View {
        switch mode {
        case .currentAppWindowSwitching:
            windowContent(for: item)
        case .applicationSwitching:
            applicationContent(for: item)
        }
    }

    private func windowContent(for item: SwitcherListItem) -> some View {
        VStack(alignment: .leading, spacing: layoutMetrics.tileContentSpacing) {
            titleHeader(for: item)
            icon(for: item)
        }
    }

    private func applicationContent(for item: SwitcherListItem) -> some View {
        VStack(alignment: .center, spacing: layoutMetrics.tileContentSpacing) {
            icon(for: item)
            applicationMetadata(for: item)
        }
    }

    private func applicationMetadata(for item: SwitcherListItem) -> some View {
        return HStack(alignment: .center, spacing: 3) {
            Text(item.title)
                .font(.system(size: layoutMetrics.titleFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)

            if let windowCount = item.subtitle {
                HStack(alignment: .center, spacing: 2) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: max(8, layoutMetrics.titleFontSize * 0.75)))
                        .accessibilityHidden(true)
                    Text(windowCount)
                }
                .font(.system(size: layoutMetrics.titleFontSize * 0.85))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        }
        .frame(width: layoutMetrics.thumbnailSize.width)
    }

    private var closeButton: some View {
        Button {
            onClose(item, index)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: layoutMetrics.closeButtonSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Color.white.opacity(isCloseButtonHovered ? 1 : 0.85),
                    Color.black.opacity(isCloseButtonHovered ? 0.85 : 0.55)
                )
        }
        .buttonStyle(.plain)
        .frame(
            width: layoutMetrics.closeButtonHitTargetSize.width,
            height: layoutMetrics.closeButtonHitTargetSize.height
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isCloseButtonHovered = hovering
        }
        .accessibilityLabel(Text("Close window"))
        .accessibilityHint(Text("Close \(item.title)."))
    }

    private func titleHeader(for item: SwitcherListItem) -> some View {
        HStack(spacing: 5) {
            if let processIdentifier = item.appIconProcessIdentifier,
               let icon = applicationIconStore.icon(for: processIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: layoutMetrics.headerIconSize.width,
                        height: layoutMetrics.headerIconSize.height
                    )
            } else {
                Image(systemName: item.symbolName ?? "macwindow")
                    .font(.system(size: layoutMetrics.headerIconSize.height))
                    .frame(
                        width: layoutMetrics.headerIconSize.width,
                        height: layoutMetrics.headerIconSize.height
                    )
            }

            Text(item.title)
                .font(.system(size: layoutMetrics.titleFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(
                    .trailing,
                    showsCloseControl ? layoutMetrics.closeButtonHitTargetSize.width : 0
                )
        }
        .frame(width: layoutMetrics.thumbnailSize.width, alignment: .leading)
    }

    @ViewBuilder
    private func icon(for item: SwitcherListItem) -> some View {
        if SwitcherOverlayThumbnailPolicy.showsThumbnails(for: mode),
           let thumbnailKey = item.thumbnailKey {
            WindowThumbnailIconView(
                thumbnailKey: thumbnailKey,
                thumbnailStore: thumbnailStore,
                applicationIconStore: applicationIconStore,
                appIconProcessIdentifier: item.appIconProcessIdentifier,
                fallbackSymbolName: item.symbolName,
                layoutMetrics: layoutMetrics
            )
        } else if let processIdentifier = item.appIconProcessIdentifier,
           let icon = applicationIconStore.icon(for: processIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(
                    width: layoutMetrics.fallbackIconSize.width,
                    height: layoutMetrics.fallbackIconSize.height
                )
                .frame(
                    width: layoutMetrics.thumbnailSize.width,
                    height: layoutMetrics.thumbnailSize.height
                )
        } else {
            Image(systemName: item.symbolName ?? "app")
                .font(.system(size: layoutMetrics.symbolFontSize))
                .frame(
                    width: layoutMetrics.fallbackIconSize.width,
                    height: layoutMetrics.fallbackIconSize.height
                )
                .frame(
                    width: layoutMetrics.thumbnailSize.width,
                    height: layoutMetrics.thumbnailSize.height
                )
        }
    }
}

private struct WindowThumbnailIconView: View {
    let thumbnailKey: String
    let applicationIconStore: ApplicationIconStore
    let appIconProcessIdentifier: Int?
    let fallbackSymbolName: String?
    let layoutMetrics: SwitcherOverlayLayoutMetrics
    @ObservedObject var thumbnailStore: WindowThumbnailStore

    init(
        thumbnailKey: String,
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore,
        appIconProcessIdentifier: Int?,
        fallbackSymbolName: String?,
        layoutMetrics: SwitcherOverlayLayoutMetrics
    ) {
        self.thumbnailKey = thumbnailKey
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore
        self.appIconProcessIdentifier = appIconProcessIdentifier
        self.fallbackSymbolName = fallbackSymbolName
        self.layoutMetrics = layoutMetrics
    }

    var body: some View {
        if let image = thumbnailStore.image(for: thumbnailKey) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: layoutMetrics.thumbnailSize.width, height: layoutMetrics.thumbnailSize.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else if let appIconProcessIdentifier,
                  let fallbackIcon = applicationIconStore.icon(for: appIconProcessIdentifier) {
            Image(nsImage: fallbackIcon)
                .resizable()
                .scaledToFit()
                .frame(
                    width: layoutMetrics.fallbackIconSize.width,
                    height: layoutMetrics.fallbackIconSize.height
                )
                .frame(
                    width: layoutMetrics.thumbnailSize.width,
                    height: layoutMetrics.thumbnailSize.height
                )
        } else {
            Image(systemName: fallbackSymbolName ?? "macwindow")
                .font(.system(size: layoutMetrics.symbolFontSize))
                .frame(
                    width: layoutMetrics.fallbackIconSize.width,
                    height: layoutMetrics.fallbackIconSize.height
                )
                .frame(
                    width: layoutMetrics.thumbnailSize.width,
                    height: layoutMetrics.thumbnailSize.height
                )
        }
    }
}
