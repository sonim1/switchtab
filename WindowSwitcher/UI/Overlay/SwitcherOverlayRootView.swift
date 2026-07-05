import AppKit
import SwiftUI

struct SwitcherOverlayRootView: View {
    private let state: SwitcherOverlayState
    private let layoutSize: CGSize
    private let layoutMetrics: SwitcherOverlayLayoutMetrics
    private let onItemClicked: (SwitcherListItem, Int) -> Void
    private let gridColumns: [GridItem]
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore

    init(
        state: SwitcherOverlayState,
        layoutSize: CGSize,
        layoutMetrics: SwitcherOverlayLayoutMetrics,
        gridColumns: [GridItem],
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore,
        onItemClicked: @escaping (SwitcherListItem, Int) -> Void
    ) {
        self.state = state
        self.layoutSize = layoutSize
        self.layoutMetrics = layoutMetrics
        self.gridColumns = gridColumns
        self.onItemClicked = onItemClicked
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rows
        }
        .padding(SwitcherOverlayChromePolicy.panelPadding)
        .frame(width: layoutSize.width, height: layoutSize.height, alignment: .center)
        .background {
            if SwitcherOverlayChromePolicy.usesNativeBlurBackground {
                SwitcherOverlayBlurBackground()
            } else {
                Color.black.opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var rows: some View {
        if let session = state.session {
            SwitcherIconStripView(
                items: session.items,
                selectedIndex: session.selectedIndex,
                gridColumns: gridColumns,
                layoutMetrics: layoutMetrics,
                showsThumbnails: SwitcherOverlayThumbnailPolicy.showsThumbnails(for: session.mode),
                thumbnailStore: thumbnailStore,
                applicationIconStore: applicationIconStore,
                onConfirm: onItemClicked
            )
        }
    }
}

private struct SwitcherOverlayBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
    }
}
