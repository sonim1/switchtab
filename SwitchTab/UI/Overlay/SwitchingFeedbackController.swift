import AppKit

@MainActor
final class SwitchingFeedbackController {
    enum Notice: Equatable {
        case noWindows, practiceCompleted

        var message: String {
            switch self {
            case .noWindows: "No windows to switch to. Open a window and try again."
            case .practiceCompleted: "Practice complete. You switched to the selected window."
            }
        }
    }

    private(set) var notice: Notice?
    private(set) var generation = 0
    private var dismissalTask: Task<Void, Never>?
    private let announce: (String) -> Void
    let label = NSTextField(wrappingLabelWithString: "")
    lazy var panel: NSPanel = {
        let panel = SwitchingFeedbackPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.ignoresMouseEvents = true
        panel.setAccessibilitySubrole(.floatingWindow)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.setAccessibilityIdentifier("switching-feedback")
        label.setAccessibilityElement(true)
        label.setAccessibilityRole(.staticText)
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])
        panel.contentView = background
        return panel
    }()

    init(announce: @escaping (String) -> Void = { message in
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }) {
        self.announce = announce
    }

    func show(_ notice: Notice, above overlayFrame: CGRect? = nil) {
        guard self.notice != notice else { return }
        dismissalTask?.cancel()
        generation += 1
        let generation = generation
        self.notice = notice
        label.stringValue = notice.message
        label.setAccessibilityValue(notice.message)
        let screens = NSScreen.screens
        let activeFrame = SwitcherOverlayPresentationPolicy.activeScreenFrame(
            pointerLocation: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame),
            fallback: NSScreen.main?.frame
        )
        if let screen = screens.first(where: { $0.frame == activeFrame }) ?? NSScreen.main {
            panel.setFrame(Self.frame(in: screen.visibleFrame, above: overlayFrame), display: true)
        }
        panel.orderFrontRegardless()
        announce(notice.message)
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.dismiss(generation: generation)
        }
    }

    func dismiss(generation: Int) {
        guard generation == self.generation else { return }
        dismiss()
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        generation += 1
        notice = nil
        panel.orderOut(nil)
    }

    static func frame(in screen: CGRect, above overlay: CGRect?) -> CGRect {
        let size = CGSize(width: min(420, screen.width), height: min(76, screen.height))
        var desiredY = overlay.map { $0.maxY + 16 } ?? (screen.midY + 120)
        if let overlay, desiredY + size.height > screen.maxY,
           overlay.minY - 16 - size.height >= screen.minY {
            desiredY = overlay.minY - 16 - size.height
        }
        return CGRect(
            x: screen.midX - size.width / 2,
            y: min(max(desiredY, screen.minY), screen.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}

private final class SwitchingFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
