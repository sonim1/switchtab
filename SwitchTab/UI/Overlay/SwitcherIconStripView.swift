import AppKit
import SwiftUI

struct SwitcherIconStripView: View {
    private let items: [SwitcherListItem]
    private let selectedIndex: Int
    private let showsThumbnails: Bool
    private let onConfirm: (SwitcherListItem, Int) -> Void
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore
    private let gridColumns: [GridItem]
    private let layoutMetrics: SwitcherOverlayLayoutMetrics

    init(
        items: [SwitcherListItem],
        selectedIndex: Int,
        gridColumns: [GridItem],
        layoutMetrics: SwitcherOverlayLayoutMetrics,
        showsThumbnails: Bool,
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore,
        onConfirm: @escaping (SwitcherListItem, Int) -> Void
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.gridColumns = gridColumns
        self.layoutMetrics = layoutMetrics
        self.showsThumbnails = showsThumbnails
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: layoutMetrics.gridSpacing) {
                        ForEach(items.indices, id: \.self) { index in
                            let item = items[index]
                            iconButton(item: item, index: index, isSelected: index == selectedIndex)
                                .id(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    scrollToSelected(using: proxy)
                }
                .onChange(of: selectedIndex) {
                    scrollToSelected(using: proxy)
                }
            }
        }
    }

    private func iconButton(item: SwitcherListItem, index: Int, isSelected: Bool) -> some View {
        Button {
            onConfirm(item, index)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                titleHeader(for: item)
                icon(for: item)
            }
            .padding(4)
            .frame(
                width: layoutMetrics.tileSize.width,
                height: layoutMetrics.tileSize.height
            )
            .background(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.95) : Color.clear,
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityHint(Text("Switch to this window."))
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
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: layoutMetrics.thumbnailSize.width, alignment: .leading)
    }

    @ViewBuilder
    private func icon(for item: SwitcherListItem) -> some View {
        if showsThumbnails,
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
                .font(.system(size: 46))
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
        guard items.count > 1 else {
            return
        }

        guard selectedIndex >= 0 && selectedIndex < items.count else {
            return
        }

        proxy.scrollTo(items[selectedIndex].id, anchor: .center)
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
                .font(.system(size: 46))
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
