import SwiftUI

struct SwitchingGuideView: View {
    @ObservedObject var model: SwitchingPracticeModel
    let onBeginPractice: () -> Void
    let onSkip: () -> Void

    var body: some View {
        SettingsSection(
            title: "Try your first window switch",
            subtitle: "Use the shortcuts SwitchTab has actually registered.",
            symbolName: "keyboard"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                shortcutRow("Current App Windows", shortcut: model.windowShortcut)
                shortcutRow("Application Switching", shortcut: model.applicationShortcut)

                Text("Hold the shortcut's modifier keys and press its other key to select a window. Release the modifiers to confirm. Add Shift to go backward; press Esc to cancel.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if let windows = model.windowShortcut, let applications = model.applicationShortcut {
                    Text("While holding the application shortcut's modifiers, press \(windows.keyEquivalent) to see the selected app's windows. Press \(applications.keyEquivalent) to return to the app list and advance one app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Start Practice hides Settings and returns to your previous app. Use its window shortcut, then reopen How to Use to see the result. Screen Recording is optional; choosing a minimized window restores it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.permissionState.blocksFocusChanges {
                    Text("Allow Accessibility in Permissions before practicing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if model.windowShortcut == nil {
                    Text("Enable and register Current App Windows in Shortcut before practicing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(model.hasCompletedPractice ? "Practice Again" : "Start Practice", action: onBeginPractice)
                        .disabled(!model.canBegin)
                    if !model.hasDismissedGuide {
                        Button("Skip for Now", action: onSkip)
                    }
                }

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(model.state == .completed ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("switching-practice-status")
            }
            .padding(.vertical, 4)
        }
    }

    private func shortcutRow(_ title: String, shortcut: ShortcutSetting?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 12)
            Text(shortcut?.displayText ?? "Not registered")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var statusText: String {
        switch model.state {
        case .ready:
            "Practice completes after the exact selected window receives focus."
        case .waitingForSwitch:
            "Waiting for a window switch."
        case .verifying:
            "Checking the selected window's focus."
        case .completed:
            "Window switch verified. You're ready to use SwitchTab."
        case .cancelled:
            "Practice cancelled. You can try again."
        case .failed(let reason):
            switch reason {
            case .accessibilityRequired:
                "Accessibility is unavailable. Allow it in Permissions and try again."
            case .shortcutUnavailable:
                "The window shortcut is unavailable or changed. Check Shortcut and try again."
            case .applicationUnavailable:
                "Open another app with a window, then return here and start practice."
            case .noWindows:
                "The active app has no switchable windows. Try another app."
            case .focusNotConfirmed:
                "The selected window's focus could not be confirmed. Practice is not complete."
            }
        }
    }
}
