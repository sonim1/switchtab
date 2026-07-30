#if DIRECT_DISTRIBUTION && canImport(Sparkle)
import AppKit

@MainActor
public enum UpdateErrorAlertAction: Equatable {
    case retry
    case downloadManually
    case cancel
}

@MainActor
public final class SparkleUpdateErrorPresenter: NSObject {
    private var diagnostic: UpdateDiagnostic?

    public func present(error: NSError) -> UpdateErrorAlertAction {
        let diagnostic = UpdateDiagnostic.make(error: error)
        self.diagnostic = diagnostic

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = diagnostic.descriptor.category.title
        alert.informativeText = diagnostic.descriptor.category.explanation
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Download Manually")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = makeAccessoryView(for: diagnostic)

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .downloadManually
        default: return .cancel
        }
    }

    private func makeAccessoryView(for diagnostic: UpdateDiagnostic) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let summary = NSTextField(labelWithString: diagnostic.descriptor.technicalSummary)
        summary.font = .monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        summary.textColor = .secondaryLabelColor

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 14
        actions.addArrangedSubview(
            linkButton("Copy Diagnostics", action: #selector(copyDiagnostics))
        )
        actions.addArrangedSubview(
            linkButton("Report Issue ↗", action: #selector(reportIssue))
        )

        stack.addArrangedSubview(summary)
        stack.addArrangedSubview(actions)
        return stack
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        return button
    }

    @objc private func copyDiagnostics() {
        guard let diagnostic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic.report, forType: .string)
    }

    @objc private func reportIssue() {
        guard let diagnostic,
              let url = UpdateSupportLinks.reportIssue(for: diagnostic) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
