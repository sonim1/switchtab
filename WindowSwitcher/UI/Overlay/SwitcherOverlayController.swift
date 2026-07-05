import AppKit
import SwiftUI

@MainActor
final class SwitcherOverlayController {
    private var state = SwitcherOverlayState()
    private var panel: SwitcherOverlayPanel?
    private var hostingController: NSHostingController<SwitcherOverlayRootView>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var onConfirm: ((SwitcherListItem, Int) -> Void)?
    private var triggerReleaseModifiers: SwitcherShortcutModifiers?
    var onDismiss: (() -> Void)?
    private var presentationLayoutSize = SwitcherOverlayLayoutPolicy.defaultSize
    private var presentationLayoutMetrics = SwitcherOverlayLayoutMetrics.metrics(for: .standard)
    private var presentationGridColumns: [GridItem] = []
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore
    private let applicationSettingsStore: ApplicationSettingsStore

    init(
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore? = nil,
        applicationSettingsStore: ApplicationSettingsStore = ApplicationSettingsStore()
    ) {
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore ?? ApplicationIconStore()
        self.applicationSettingsStore = applicationSettingsStore
    }

    var isPresented: Bool {
        state.isPresented
    }

    var activeMode: SwitcherMode? {
        state.session?.mode
    }

    func present(
        mode: SwitcherMode,
        items: [SwitcherListItem],
        selectedIndex: Int = 0,
        triggerShortcut: ShortcutSetting? = nil,
        onConfirm: ((SwitcherListItem, Int) -> Void)? = nil
    ) {
        guard !items.isEmpty else {
            dismiss()
            return
        }

        applicationIconStore.retainOnlyCachedIcons(for: items)
        state.present(
            mode: mode,
            items: items,
            selectedIndex: selectedIndex
        )
        self.onConfirm = onConfirm
        if let triggerShortcut {
            self.triggerReleaseModifiers = SwitcherShortcutModifiers.releaseRelevantModifiers(triggerShortcut)
        } else {
            self.triggerReleaseModifiers = nil
        }
        showPanel()
    }

    func dismiss() {
        guard state.isPresented else {
            return
        }

        state.dismiss()
        endPresentation()
        clearPresentationCallbacks()
    }

    func handle(_ command: SwitcherCommand) -> SwitcherInteractionResult {
        let result = state.handle(command)
        switch result {
        case .updated:
            render()
        case .confirmed, .cancelled:
            apply(result)
        case .none:
            break
        }
        return result
    }

    private func showPanel() {
        guard let session = state.session else {
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        let screenFrame = activeScreenVisibleFrame()
        let presentationLayout = currentPresentationLayout(session: session, screenSize: screenFrame?.size)
        presentationLayoutSize = presentationLayout.size
        presentationLayoutMetrics = presentationLayout.metrics
        presentationGridColumns = SwitcherIconStripView.gridColumns(
            columnCount: presentationLayout.gridColumnCount,
            metrics: presentationLayout.metrics
        )
        render()
        center(panel: panel, screenFrame: screenFrame)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitor()
    }

    // Present on the screen under the pointer: the frontmost app's windows are
    // most likely there, and NSScreen.main tracks our own key window instead.
    private func activeScreenVisibleFrame() -> CGRect? {
        let screens = NSScreen.screens
        let activeFrame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame),
            fallback: NSScreen.main?.frame
        )
        let activeScreen = screens.first { $0.frame == activeFrame } ?? NSScreen.main
        return activeScreen?.visibleFrame
    }

    private func makePanel() -> SwitcherOverlayPanel {
        let panel = SwitcherOverlayPanel(
            contentRect: NSRect(origin: .zero, size: SwitcherOverlayLayoutPolicy.defaultSize),
            styleMask: SwitcherOverlayPresentationPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.level = .floating
        return panel
    }

    private func render() {
        let layoutSize = presentationLayoutSize
        guard let panel else {
            return
        }

        if panel.contentViewController != nil,
           panel.frame.size != layoutSize {
            panel.setContentSize(layoutSize)
        }

        let rootView = SwitcherOverlayRootView(
            state: state,
            layoutSize: layoutSize,
            layoutMetrics: presentationLayoutMetrics,
            gridColumns: presentationGridColumns,
            thumbnailStore: thumbnailStore,
            applicationIconStore: applicationIconStore,
            onItemClicked: confirmClickedItem
        )

        if let hostingController {
            hostingController.rootView = rootView
            if hostingController.view.frame.size != layoutSize {
                hostingController.view.frame = NSRect(origin: .zero, size: layoutSize)
            }
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.frame = NSRect(origin: .zero, size: layoutSize)
            self.hostingController = hostingController
            panel.contentViewController = hostingController
            panel.setContentSize(layoutSize)
        }
    }

    private func currentPresentationLayout(
        session: SwitcherSession,
        screenSize: CGSize?
    ) -> SwitcherOverlayPresentationLayout {
        SwitcherOverlayLayoutPolicy.presentationLayout(
            itemCount: session.items.count,
            screenSize: screenSize ?? SwitcherOverlayLayoutPolicy.defaultSize,
            overlaySize: applicationSettingsStore.overlaySize
        )
    }

    private func center(panel: NSPanel, screenFrame: CGRect?) {
        guard let screenFrame else {
            return
        }

        let size = panel.frame.size
        let origin = SwitcherOverlayPresentationPolicy.panelOrigin(
            panelSize: size,
            screenFrame: screenFrame
        )
        guard panel.frame.origin != origin else {
            return
        }
        panel.setFrameOrigin(origin)
    }

    private func installEventMonitor() {
        guard localEventMonitor == nil || globalEventMonitor == nil || activationObserver == nil else {
            return
        }

        removeEventMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: SwitcherOverlayEventMonitorPolicy.localMask) { [weak self] event in
            guard let self, self.state.isPresented else {
                return event
            }

            return self.handle(event: event) ? nil : event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: SwitcherOverlayEventMonitorPolicy.globalMask
        ) { [weak self] event in
            guard let externalEvent = Self.externalEvent(from: event) else {
                return
            }

            guard !Thread.isMainThread else {
                MainActor.assumeIsolated {
                    self?.handleExternal(event: externalEvent)
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.handleExternal(event: externalEvent)
                }
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyExternalDecision(.cancel)
            }
        }
    }

    private func removeEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func handle(event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            guard state.session != nil else {
                return false
            }

            guard SwitcherOverlayExternalEventPolicy.decision(
                for: .flagsChanged(activeModifiers: event.shortcutModifiers),
                triggerReleaseModifiers: triggerReleaseModifiers
            ) == .releaseShortcut else {
                return false
            }

            _ = handle(.releaseShortcut)
            return true
        case .keyDown:
            if let command = SwitcherCommand(keyCode: event.keyCode) {
                _ = handle(command)
                return true
            }

            guard !event.hasShortcutModifiers else {
                return false
            }

            return event.charactersIgnoringModifiers?.isEmpty == false
        default:
            return false
        }
    }

    nonisolated private static func externalEvent(from event: NSEvent) -> SwitcherOverlayExternalEvent? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            .mouseDown
        case .flagsChanged:
            .flagsChanged(activeModifiers: event.shortcutModifiers)
        default:
            nil
        }
    }

    private func handleExternal(event externalEvent: SwitcherOverlayExternalEvent) {
        guard state.session != nil else {
            return
        }

        let decision = SwitcherOverlayExternalEventPolicy.decision(
            for: externalEvent,
            triggerReleaseModifiers: triggerReleaseModifiers
        )
        applyExternalDecision(decision)
    }

    private func applyExternalDecision(_ decision: SwitcherOverlayExternalEventDecision) {
        guard state.isPresented else {
            return
        }

        switch decision {
        case .none:
            break
        case .cancel:
            _ = handle(.cancel)
        case .releaseShortcut:
            _ = handle(.releaseShortcut)
        }
    }

    private func confirmClickedItem(_ item: SwitcherListItem, index: Int) {
        state.dismiss()
        apply(.confirmed(item: item, index: index))
    }

    private func apply(_ result: SwitcherInteractionResult) {
        switch result {
        case .confirmed(let item, let index):
            let confirm = onConfirm
            endPresentation()
            clearPresentationCallbacks()
            confirm?(item, index)
        case .cancelled:
            endPresentation()
            clearPresentationCallbacks()
        case .none, .updated:
            break
        }
    }

    private func clearPresentationCallbacks() {
        onConfirm = nil
        triggerReleaseModifiers = nil
    }

    private func endPresentation() {
        panel?.orderOut(nil)
        removeEventMonitor()
        onDismiss?()
    }

}

private final class SwitcherOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        SwitcherOverlayPresentationPolicy.canBecomeKey
    }

    override var canBecomeMain: Bool {
        SwitcherOverlayPresentationPolicy.canBecomeMain
    }
}

private extension NSEvent {
    private static let shortcutBlockingModifierFlags: NSEvent.ModifierFlags = [.command, .control, .option]

    var shortcutModifiers: SwitcherShortcutModifiers {
        ShortcutModifierResolver.shortcutModifiers(from: modifierFlags)
    }

    var hasShortcutModifiers: Bool {
        modifierFlags.rawValue & Self.shortcutBlockingModifierFlags.rawValue != 0
    }
}
