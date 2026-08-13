import AppKit
import CoreGraphics
import os
import SwiftUI

@MainActor
final class SwitcherOverlayController {
    private static let hoverActivationDistance: CGFloat = 3

    private var state = SwitcherOverlayState()
    private let presentationModel = SwitcherOverlayPresentationModel()
    private var panel: SwitcherOverlayPanel?
    private var hostingController: NSHostingController<SwitcherOverlayRootView>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var eventTapOwner: SwitcherOverlayEventTapOwner?
    private var activationObserver: NSObjectProtocol?
    private var onConfirm: ((SwitcherListItem, Int) -> Void)?
    private var onClose: ((SwitcherListItem, UInt64) -> Void)?
    private var onQuit: ((SwitcherListItem, Int) -> Void)?
    private var onModeSwitch: ((Bool) -> Void)?
    private var onThumbnailDemand: ((SwitcherListItem, WindowThumbnailRequestPriority) -> Void)?
    private var presentationID: UInt64 = 0
    private var triggerShortcut: ShortcutSetting?
    private var triggerReleaseModifiers: SwitcherShortcutModifiers?
    private var alternateModeKeyCode: UInt16?
    var onDismiss: (() -> Void)?
    private var presentationLayoutSize = SwitcherOverlayLayoutPolicy.defaultSize
    private var presentationLayoutMetrics = SwitcherOverlayLayoutMetrics.metrics(
        for: .default,
        mode: .currentAppWindowSwitching
    )
    private var presentationRequiresSelectionScrolling = false
    private var presentationGridColumns: [GridItem] = []
    private var presentationPointerLocation: CGPoint = .zero
    private let thumbnailStore: WindowThumbnailStore
    private let applicationIconStore: ApplicationIconStore
    private let applicationSettingsStore: ApplicationSettingsStore
    private let eventTapBackend: any SwitcherOverlayEventTapBackend
    private let eventSink: any SwitcherOverlayEventRecording

    init(
        thumbnailStore: WindowThumbnailStore,
        applicationIconStore: ApplicationIconStore? = nil,
        applicationSettingsStore: ApplicationSettingsStore = ApplicationSettingsStore(),
        eventTapBackend: (any SwitcherOverlayEventTapBackend)? = nil,
        eventSink: (any SwitcherOverlayEventRecording)? = nil
    ) {
        self.thumbnailStore = thumbnailStore
        self.applicationIconStore = applicationIconStore ?? ApplicationIconStore()
        self.applicationSettingsStore = applicationSettingsStore
        self.eventTapBackend = eventTapBackend ?? SystemSwitcherOverlayEventTapBackend()
        self.eventSink = eventSink ?? DefaultSwitcherOverlayEventSink()
    }

    var isPresented: Bool {
        state.isPresented
    }

    var activeMode: SwitcherMode? {
        state.session?.mode
    }

    var selectedItem: SwitcherListItem? {
        state.session?.selectedItem
    }

    var presentationScrollToken: Int {
        presentationModel.scrollToken
    }

    @discardableResult
    func present(
        mode: SwitcherMode,
        items: [SwitcherListItem],
        selectedIndex: Int = 0,
        triggerShortcut: ShortcutSetting? = nil,
        alternateModeKeyCode: UInt16? = nil,
        retainingSession: Bool = false,
        onClose: ((SwitcherListItem, UInt64) -> Void)? = nil,
        onQuit: ((SwitcherListItem, Int) -> Void)? = nil,
        onConfirm: ((SwitcherListItem, Int) -> Void)? = nil,
        onModeSwitch: ((Bool) -> Void)? = nil,
        onThumbnailDemand: ((SwitcherListItem, WindowThumbnailRequestPriority) -> Void)? = nil
    ) -> UInt64? {
        guard !items.isEmpty else {
            // A mode switch that finds nothing to show leaves the live session
            // alone instead of tearing it down under the held modifier.
            if !retainingSession {
                dismiss()
            }
            return nil
        }

        // Retaining keeps the panel, the event tap and the modifiers that
        // started the session, so switching modes cannot drop the hold that
        // still has to commit the choice.
        let retainsSession = retainingSession && state.isPresented
        presentationID &+= 1
        applicationIconStore.retainOnlyCachedIcons(for: items)
        // The overlay often opens under a resting pointer; hovering only takes
        // over the selection after the pointer actually moves.
        presentationModel.setHoverSelectionEnabled(false)
        presentationPointerLocation = NSEvent.mouseLocation
        // Advancing the token re-scrolls to the selection when a reused hosting
        // view is presented again and `onAppear` no longer fires.
        presentationModel.advanceScrollToken()
        state.present(
            mode: mode,
            items: items,
            selectedIndex: selectedIndex
        )
        self.onConfirm = onConfirm
        self.onClose = onClose
        self.onQuit = onQuit
        self.onModeSwitch = onModeSwitch
        self.onThumbnailDemand = onThumbnailDemand
        requestSelectedThumbnail()
        self.triggerShortcut = triggerShortcut
        self.alternateModeKeyCode = alternateModeKeyCode
        if !retainsSession {
            if let triggerShortcut {
                self.triggerReleaseModifiers = SwitcherShortcutModifiers.releaseRelevantModifiers(triggerShortcut)
            } else {
                self.triggerReleaseModifiers = nil
            }
        }

        if retainsSession, let panel, let session = state.session {
            eventTapOwner?.updateTrigger(
                shortcut: triggerShortcut,
                alternateModeKeyCode: alternateModeKeyCode
            )
            updatePresentationLayout(session: session, panel: panel)
        } else {
            showPanel()
        }
        return presentationID
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
        handle(command, recordsDiagnostic: false)
    }

    private func handle(
        _ command: SwitcherCommand,
        recordsDiagnostic: Bool
    ) -> SwitcherInteractionResult {
        let beforeIndex = state.session?.selectedIndex ?? -1
        let result = state.handle(command)
        if recordsDiagnostic {
            let afterIndex = state.session?.selectedIndex ?? beforeIndex
            eventSink.record(.command(
                commandCode: command.diagnosticCode,
                beforeIndex: beforeIndex,
                afterIndex: afterIndex,
                resultCode: result.diagnosticCode
            ))
        }
        switch result {
        case .updated:
            presentationModel.advanceScrollToken()
            presentationModel.update(state)
            requestSelectedThumbnail()
        case .confirmed, .cancelled:
            apply(result)
        case .closeRequested(let item, let index):
            closeItem(item, at: index)
        case .quitRequested(let item, let index):
            quitItem(item, at: index)
        case .modeSwitchRequested(let reverse):
            onModeSwitch?(reverse)
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
        updatePresentationLayout(session: session, panel: panel)
        panel.makeKeyAndOrderFront(nil)
        let tapInstalled = installEventTap()
        installEventMonitor()
        eventSink.record(.presented(
            itemCount: session.items.count,
            selectedIndex: session.selectedIndex,
            tapInstalled: tapInstalled
        ))
    }

    private func updatePresentationLayout(session: SwitcherSession, panel: NSPanel) {
        let screenFrame = activeScreenVisibleFrame()
        let presentationLayout = currentPresentationLayout(session: session, screenSize: screenFrame?.size)
        presentationLayoutSize = presentationLayout.size
        presentationLayoutMetrics = presentationLayout.metrics
        presentationRequiresSelectionScrolling = presentationLayout.requiresSelectionScrolling
        presentationGridColumns = SwitcherIconStripView.gridColumns(
            columnCount: presentationLayout.gridColumnCount,
            metrics: presentationLayout.metrics
        )
        render()
        center(panel: panel, screenFrame: screenFrame)
    }

    // Closing keeps the overlay up so the user can keep cycling; the grid is
    // re-laid out because one fewer window can change rows and columns.
    private func closeItem(_ item: SwitcherListItem, at _: Int) {
        guard let onClose else {
            return
        }

        onClose(item, presentationID)
    }

    private func quitItem(_ item: SwitcherListItem, at index: Int) {
        onQuit?(item, index)
    }

    func confirmWindowDisappeared(id: String, presentationID: UInt64) {
        guard presentationID == self.presentationID, state.isPresented else {
            return
        }

        switch state.removeItem(withID: id) {
        case .updated:
            guard let session = state.session, let panel else {
                return
            }

            presentationModel.setHoverSelectionEnabled(false)
            presentationPointerLocation = NSEvent.mouseLocation
            presentationModel.advanceScrollToken()
            updatePresentationLayout(session: session, panel: panel)
        case .cancelled:
            apply(.cancelled)
        case .none, .confirmed, .closeRequested, .quitRequested, .modeSwitchRequested:
            break
        }
    }

    func confirmApplicationTerminated(id: String, processIdentifier: Int) {
        guard state.isPresented,
              let session = state.session,
              session.mode == .applicationSwitching,
              session.items.contains(where: {
                  $0.id == id && $0.appIconProcessIdentifier == processIdentifier
              }) else {
            return
        }

        switch state.removeItem(withID: id) {
        case .updated:
            guard let session = state.session, let panel else {
                return
            }

            presentationModel.setHoverSelectionEnabled(false)
            presentationPointerLocation = NSEvent.mouseLocation
            presentationModel.advanceScrollToken()
            updatePresentationLayout(session: session, panel: panel)
        case .cancelled:
            apply(.cancelled)
        case .none, .confirmed, .closeRequested, .quitRequested, .modeSwitchRequested:
            break
        }
    }

    func updateApplicationItems(
        _ items: [SwitcherListItem],
        presentationID: UInt64
    ) {
        guard presentationID == self.presentationID,
              state.updateApplicationItems(items) == .updated else {
            return
        }

        presentationModel.update(state)
    }

    @discardableResult
    private func installEventTap() -> Bool {
        removeEventTap()
        let owner = SwitcherOverlayEventTapOwner(
            backend: eventTapBackend,
            eventSink: eventSink,
            triggerReleaseModifiers: triggerReleaseModifiers,
            triggerShortcut: triggerShortcut,
            alternateModeKeyCode: alternateModeKeyCode
        ) { @MainActor [weak self] command in
            guard let self else {
                return
            }
            _ = self.handle(command, recordsDiagnostic: true)
        }
        eventTapOwner = owner
        guard owner.install() else {
            eventTapOwner = nil
            return false
        }
        return true
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
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func render() {
        presentationModel.update(state)
        let layoutSize = presentationLayoutSize
        guard let panel else {
            return
        }

        if panel.contentViewController != nil,
           panel.frame.size != layoutSize {
            panel.setContentSize(layoutSize)
        }

        let rootView = SwitcherOverlayRootView(
            presentationModel: presentationModel,
            layoutSize: layoutSize,
            layoutMetrics: presentationLayoutMetrics,
            requiresSelectionScrolling: presentationRequiresSelectionScrolling,
            gridColumns: presentationGridColumns,
            thumbnailStore: thumbnailStore,
            applicationIconStore: applicationIconStore,
            onItemClicked: confirmClickedItem,
            onItemCloseClicked: closeItem,
            onItemHovered: hoverItem,
            onThumbnailDemand: { [weak self] item in
                self?.onThumbnailDemand?(item, .visible)
            }
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
            mode: session.mode,
            scale: applicationSettingsStore.overlaySizeScale
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
            guard event.type != .mouseMoved else {
                Self.onMainActor { [weak self] in
                    self?.enableHoverSelectionIfPointerMoved(to: NSEvent.mouseLocation)
                }
                return
            }

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
                guard let self,
                      let mode = self.state.session?.mode else {
                    return
                }

                let activeModifiers = ShortcutModifierResolver.shortcutModifiers(
                    from: CGEventSource.flagsState(.combinedSessionState)
                )
                let decision = SwitcherOverlayWorkspaceActivationPolicy.decision(
                    mode: mode,
                    triggerReleaseModifiers: self.triggerReleaseModifiers,
                    activeModifiers: activeModifiers
                )
                self.applyExternalDecision(decision)
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

    private func removeEventTap() {
        let owner = eventTapOwner
        eventTapOwner = nil
        owner?.remove()
    }

    private func handle(event: NSEvent) -> Bool {
        switch event.type {
        case .mouseMoved:
            enableHoverSelectionIfPointerMoved(to: NSEvent.mouseLocation)
            return false
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
            if let triggerCommand = SwitcherOverlayTriggerPolicy.command(
                keyCode: event.keyCode,
                modifiers: event.shortcutModifiers,
                triggerShortcut: triggerShortcut
            ) {
                _ = handle(triggerCommand)
                return true
            }

            if let modeSwitchCommand = SwitcherOverlayModeSwitchPolicy.command(
                keyCode: event.keyCode,
                modifiers: event.shortcutModifiers,
                alternateModeKeyCode: alternateModeKeyCode
            ) {
                _ = handle(modeSwitchCommand)
                return true
            }

            if let command = SwitcherCommand(keyCode: event.keyCode, modifiers: event.shortcutModifiers) {
                guard !(event.isARepeat && command.repeatsAreDestructive) else {
                    return true
                }

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

    nonisolated private static func onMainActor(_ work: @escaping @MainActor () -> Void) {
        guard !Thread.isMainThread else {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                work()
            }
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

    // Pointer hover moves the highlight without scrolling: the tile is already
    // under the pointer, so re-centring it would drag the grid out from under it.
    func hoverItem(at index: Int) {
        guard presentationModel.isHoverSelectionEnabled,
              state.selectItem(at: index) == .updated else {
            return
        }

        presentationModel.update(state)
    }

    func enableHoverSelectionIfPointerMoved(to pointerLocation: CGPoint) {
        guard state.isPresented, !presentationModel.isHoverSelectionEnabled else {
            return
        }

        let horizontalDelta = pointerLocation.x - presentationPointerLocation.x
        let verticalDelta = pointerLocation.y - presentationPointerLocation.y
        let squaredDistance = horizontalDelta * horizontalDelta + verticalDelta * verticalDelta
        guard squaredDistance > Self.hoverActivationDistance * Self.hoverActivationDistance else {
            return
        }

        presentationModel.setHoverSelectionEnabled(true)
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
        case .none, .updated, .closeRequested, .quitRequested, .modeSwitchRequested:
            break
        }
    }

    private func clearPresentationCallbacks() {
        onConfirm = nil
        onClose = nil
        onQuit = nil
        onModeSwitch = nil
        onThumbnailDemand = nil
        triggerShortcut = nil
        triggerReleaseModifiers = nil
        alternateModeKeyCode = nil
    }

    private func requestSelectedThumbnail() {
        guard let item = state.session?.selectedItem else {
            return
        }
        onThumbnailDemand?(item, .selected)
    }

    private func endPresentation() {
        presentationModel.update(state)
        panel?.orderOut(nil)
        removeEventTap()
        removeEventMonitor()
        onDismiss?()
    }

    isolated deinit {
        removeEventTap()
    }

}

struct SwitcherOverlayEventTapInput: Equatable, Sendable {
    let eventType: CGEventType
    let keyCode: UInt16
    let isAutorepeat: Bool
    let modifiers: SwitcherShortcutModifiers

    init(
        eventType: CGEventType,
        keyCode: UInt16,
        isAutorepeat: Bool,
        modifiers: SwitcherShortcutModifiers = []
    ) {
        self.eventType = eventType
        self.keyCode = keyCode
        self.isAutorepeat = isAutorepeat
        self.modifiers = modifiers
    }
}

@MainActor
protocol SwitcherOverlayEventTapConnection: AnyObject {
    func reenable()
    func invalidate()
}

@MainActor
protocol SwitcherOverlayEventTapBackend: AnyObject {
    func install(
        handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)?
}

enum SwitcherOverlayDiagnosticEvent: Equatable, Sendable {
    case presented(itemCount: Int, selectedIndex: Int, tapInstalled: Bool)
    case command(commandCode: Int, beforeIndex: Int, afterIndex: Int, resultCode: Int)
    case tapReenabled(reasonCode: Int)
    case tapRemoved
}

@MainActor
protocol SwitcherOverlayEventRecording: AnyObject {
    func record(_ event: SwitcherOverlayDiagnosticEvent)
}

@MainActor
final class SwitcherOverlayEventTapOwner {
    private final class Session {
        var isActive = true
    }

    private let backend: any SwitcherOverlayEventTapBackend
    private let eventSink: any SwitcherOverlayEventRecording
    private let triggerReleaseModifiers: SwitcherShortcutModifiers?
    private var triggerShortcut: ShortcutSetting?
    private var alternateModeKeyCode: UInt16?
    private let commandHandler: @MainActor (SwitcherCommand) -> Void
    private var connection: (any SwitcherOverlayEventTapConnection)?
    private var session: Session?

    init(
        backend: any SwitcherOverlayEventTapBackend,
        eventSink: any SwitcherOverlayEventRecording,
        triggerReleaseModifiers: SwitcherShortcutModifiers? = nil,
        triggerShortcut: ShortcutSetting? = nil,
        alternateModeKeyCode: UInt16? = nil,
        commandHandler: @escaping @MainActor (SwitcherCommand) -> Void
    ) {
        self.backend = backend
        self.eventSink = eventSink
        self.triggerReleaseModifiers = triggerReleaseModifiers
        self.triggerShortcut = triggerShortcut
        self.alternateModeKeyCode = alternateModeKeyCode
        self.commandHandler = commandHandler
    }

    /// Swaps which shortcuts the live tap answers to. The tap itself is left
    /// installed: a mode switch is handled from inside the tap callback, so
    /// tearing it down there would invalidate the port mid-dispatch.
    func updateTrigger(
        shortcut: ShortcutSetting?,
        alternateModeKeyCode: UInt16?
    ) {
        triggerShortcut = shortcut
        self.alternateModeKeyCode = alternateModeKeyCode
    }

    @discardableResult
    func install() -> Bool {
        remove()
        let session = Session()
        self.session = session
        guard let connection = backend.install(handler: { [weak self, session] input in
            guard session.isActive, let self else {
                return false
            }
            return self.handle(input)
        }) else {
            session.isActive = false
            self.session = nil
            return false
        }
        self.connection = connection
        return true
    }

    func remove() {
        guard connection != nil || session != nil else {
            return
        }
        let connection = connection
        self.connection = nil
        session?.isActive = false
        session = nil
        connection?.invalidate()
        eventSink.record(.tapRemoved)
    }

    private func handle(_ input: SwitcherOverlayEventTapInput) -> Bool {
        switch SwitcherOverlayEventTapPolicy.decision(
            eventType: input.eventType,
            keyCode: input.keyCode,
            isAutorepeat: input.isAutorepeat,
            modifiers: input.modifiers,
            triggerReleaseModifiers: triggerReleaseModifiers,
            triggerShortcut: triggerShortcut,
            alternateModeKeyCode: alternateModeKeyCode
        ) {
        case .passThrough:
            return false
        case .consume(let command):
            commandHandler(command)
            return true
        case .handleAndPassThrough(let command):
            commandHandler(command)
            return false
        case .consumeWithoutCommand:
            return true
        case .reenable:
            connection?.reenable()
            eventSink.record(.tapReenabled(reasonCode: input.eventType.diagnosticReasonCode))
            return false
        }
    }

    deinit {
        MainActor.assumeIsolated {
            remove()
        }
    }
}

@MainActor
final class SystemSwitcherOverlayEventTapBackend: SwitcherOverlayEventTapBackend {
    func install(
        handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool
    ) -> (any SwitcherOverlayEventTapConnection)? {
        let context = SystemSwitcherOverlayEventTapContext(handler: handler)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let unmanaged = Unmanaged<SystemSwitcherOverlayEventTapContext>.fromOpaque(userInfo)
            _ = unmanaged.retain()
            let context = unmanaged.takeUnretainedValue()
            defer { unmanaged.release() }

            let shouldConsume = MainActor.assumeIsolated {
                guard context.isActive, let handler = context.handler else {
                    return false
                }
                let input = SwitcherOverlayEventTapInput(
                    eventType: type,
                    keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                    isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    modifiers: ShortcutModifierResolver.shortcutModifiers(from: event.flags)
                )
                return handler(input)
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: SwitcherOverlayEventTapPolicy.eventMask,
            callback: callback,
            userInfo: contextPointer
        ) else {
            context.isActive = false
            context.handler = nil
            Unmanaged<SystemSwitcherOverlayEventTapContext>.fromOpaque(contextPointer).release()
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            context.isActive = false
            context.handler = nil
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            Unmanaged<SystemSwitcherOverlayEventTapContext>.fromOpaque(contextPointer).release()
            return nil
        }

        context.tap = tap
        context.source = source
        let connection = SystemSwitcherOverlayEventTapConnection(contextPointer: contextPointer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return connection
    }
}

private final class SystemSwitcherOverlayEventTapContext: @unchecked Sendable {
    var isActive = true
    var handler: (@MainActor (SwitcherOverlayEventTapInput) -> Bool)?
    var tap: CFMachPort?
    var source: CFRunLoopSource?

    init(handler: @escaping @MainActor (SwitcherOverlayEventTapInput) -> Bool) {
        self.handler = handler
    }
}

@MainActor
private final class SystemSwitcherOverlayEventTapConnection: SwitcherOverlayEventTapConnection {
    private var contextPointer: UnsafeMutableRawPointer?

    init(contextPointer: UnsafeMutableRawPointer) {
        self.contextPointer = contextPointer
    }

    func reenable() {
        guard let contextPointer else {
            return
        }
        let context = Unmanaged<SystemSwitcherOverlayEventTapContext>
            .fromOpaque(contextPointer)
            .takeUnretainedValue()
        if let tap = context.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func invalidate() {
        guard let contextPointer else {
            return
        }
        self.contextPointer = nil
        let unmanaged = Unmanaged<SystemSwitcherOverlayEventTapContext>.fromOpaque(contextPointer)
        let context = unmanaged.takeUnretainedValue()
        context.isActive = false
        context.handler = nil
        if let source = context.source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = context.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        context.source = nil
        context.tap = nil
        unmanaged.release()
    }

    deinit {
        MainActor.assumeIsolated {
            invalidate()
        }
    }
}

@MainActor
final class DefaultSwitcherOverlayEventSink: SwitcherOverlayEventRecording {
#if DEBUG
    private let logger = Logger(subsystem: "com.royjen.switchtab", category: "SwitcherKeyboard")
#endif

    func record(_ event: SwitcherOverlayDiagnosticEvent) {
#if DEBUG
        switch event {
        case .presented(let itemCount, let selectedIndex, let tapInstalled):
            logger.debug("presented itemCount=\(itemCount, privacy: .public) selectedIndex=\(selectedIndex, privacy: .public) tapInstalled=\(tapInstalled, privacy: .public)")
        case .command(let commandCode, let beforeIndex, let afterIndex, let resultCode):
            logger.debug("command commandCode=\(commandCode, privacy: .public) beforeIndex=\(beforeIndex, privacy: .public) afterIndex=\(afterIndex, privacy: .public) resultCode=\(resultCode, privacy: .public)")
        case .tapReenabled(let reasonCode):
            logger.debug("tapReenabled reasonCode=\(reasonCode, privacy: .public)")
        case .tapRemoved:
            logger.debug("tapRemoved")
        }
#endif
    }
}

private extension SwitcherCommand {
    var diagnosticCode: Int {
        switch self {
        case .moveUp: 1
        case .moveDown: 2
        case .confirm: 3
        case .releaseShortcut: 4
        case .cancel: 5
        case .closeSelected: 6
        case .quitSelectedApplication: 7
        case .switchMode: 8
        }
    }
}

private extension SwitcherInteractionResult {
    var diagnosticCode: Int {
        switch self {
        case .none: 0
        case .updated: 1
        case .confirmed: 2
        case .cancelled: 3
        case .closeRequested: 4
        case .quitRequested: 5
        case .modeSwitchRequested: 6
        }
    }
}

private extension CGEventType {
    var diagnosticReasonCode: Int {
        switch self {
        case .tapDisabledByTimeout: 1
        case .tapDisabledByUserInput: 2
        default: 0
        }
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
