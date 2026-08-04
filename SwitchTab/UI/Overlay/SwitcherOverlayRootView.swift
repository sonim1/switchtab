import AppKit
import SwiftUI

struct SwitcherOverlayRootView: View {
    @ObservedObject private var presentationModel: SwitcherOverlayPresentationModel
    private let layoutSize: CGSize
    private let layoutMetrics: SwitcherOverlayLayoutMetrics
    private let requiresSelectionScrolling: Bool
    private let onItemClicked: (SwitcherListItem, Int) -> Void
    private let onItemCloseClicked: (SwitcherListItem, Int) -> Void
    private let onItemHovered: (Int) -> Void
    private let gridColumns: [GridItem]
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore

    init(
        presentationModel: SwitcherOverlayPresentationModel,
        layoutSize: CGSize,
        layoutMetrics: SwitcherOverlayLayoutMetrics,
        requiresSelectionScrolling: Bool,
        gridColumns: [GridItem],
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore,
        onItemClicked: @escaping (SwitcherListItem, Int) -> Void,
        onItemCloseClicked: @escaping (SwitcherListItem, Int) -> Void,
        onItemHovered: @escaping (Int) -> Void
    ) {
        self.presentationModel = presentationModel
        self.layoutSize = layoutSize
        self.layoutMetrics = layoutMetrics
        self.requiresSelectionScrolling = requiresSelectionScrolling
        self.gridColumns = gridColumns
        self.onItemClicked = onItemClicked
        self.onItemCloseClicked = onItemCloseClicked
        self.onItemHovered = onItemHovered
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rows
        }
        .padding(.horizontal, layoutMetrics.panelHorizontalPadding)
        .padding(.top, layoutMetrics.panelTopPadding)
        .padding(.bottom, layoutMetrics.panelBottomPadding)
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
        if let session = presentationModel.state.session {
            SwitcherIconStripView(
                items: session.items,
                selectedIndex: session.selectedIndex,
                gridColumns: gridColumns,
                layoutMetrics: layoutMetrics,
                mode: session.mode,
                showsCloseControl: SwitcherOverlayClosePolicy.allowsClose(for: session.mode),
                switchAccessibilityHint: SwitcherOverlayAccessibilityPolicy.switchHint(for: session.mode),
                hoverEnabled: presentationModel.isHoverSelectionEnabled,
                scrollToken: presentationModel.scrollToken,
                requiresSelectionScrolling: requiresSelectionScrolling,
                thumbnailStore: thumbnailStore,
                applicationIconStore: applicationIconStore,
                onConfirm: onItemClicked,
                onClose: onItemCloseClicked,
                onHover: onItemHovered
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
