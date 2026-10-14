import AppKit
import SwiftUI

struct SwitcherAccessibleTileButton: NSViewRepresentable {
    let identifier: String
    let label: String
    let hint: String
    let value: String
    let isSelected: Bool
    let focusRequest: SwitcherOverlayAccessibilityFocusRequest?
    let content: AnyView
    let onPress: () -> Void

    init<Content: View>(
        identifier: String,
        label: String,
        hint: String,
        value: String,
        isSelected: Bool,
        focusRequest: SwitcherOverlayAccessibilityFocusRequest?,
        onPress: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.identifier = identifier
        self.label = label
        self.hint = hint
        self.value = value
        self.isSelected = isSelected
        self.focusRequest = focusRequest
        self.content = AnyView(content())
        self.onPress = onPress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress)
    }

    func makeNSView(context: Context) -> AccessibleTileButton {
        let button = AccessibleTileButton(content: content)
        button.target = context.coordinator
        button.action = #selector(Coordinator.press)
        return button
    }

    func updateNSView(_ button: AccessibleTileButton, context: Context) {
        context.coordinator.onPress = onPress
        button.update(
            identifier: identifier,
            label: label,
            hint: hint,
            value: value,
            isSelected: isSelected,
            focusRequest: focusRequest,
            content: content
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPress: () -> Void

        init(onPress: @escaping () -> Void) {
            self.onPress = onPress
        }

        @objc func press() {
            onPress()
        }
    }
}

@MainActor
final class AccessibleTileButton: NSButton {
    private let contentView: TileContentHostingView
    private var focusedGeneration: UInt64?
    private var pendingFocusGeneration: UInt64?
    private var needsFocusAfterLayout = false
    private var keyWindowObserver: NSObjectProtocol?

    init(content: AnyView) {
        contentView = TileContentHostingView(rootView: content)
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        guard let window else {
            return
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.requestFocusAfterLayout()
            }
        }
    }

    func update(
        identifier: String,
        label: String,
        hint: String,
        value: String,
        isSelected: Bool,
        focusRequest: SwitcherOverlayAccessibilityFocusRequest?,
        content: AnyView
    ) {
        contentView.rootView = content
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
        setAccessibilityHelp(hint)
        setAccessibilityValue(value)
        setAccessibilitySelected(isSelected)

        if isSelected, focusRequest?.itemID == identifier {
            pendingFocusGeneration = focusRequest?.generation
            requestFocusAfterLayout()
        } else {
            pendingFocusGeneration = nil
            needsFocusAfterLayout = false
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func layout() {
        super.layout()
        guard needsFocusAfterLayout else {
            return
        }
        needsFocusAfterLayout = false
        focusSelectedTileIfPossible()
    }

    private func requestFocusAfterLayout() {
        needsFocusAfterLayout = true
        needsLayout = true
    }

    private func focusSelectedTileIfPossible() {
        guard let pendingFocusGeneration,
              focusedGeneration != pendingFocusGeneration,
              NSWorkspace.shared.isVoiceOverEnabled,
              let window,
              window.isKeyWindow,
              window.makeFirstResponder(self) else {
            return
        }

        setAccessibilityFocused(true)
        NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
        focusedGeneration = pendingFocusGeneration
        self.pendingFocusGeneration = nil
    }

    isolated deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }
}

private final class TileContentHostingView: NSHostingView<AnyView> {
    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
