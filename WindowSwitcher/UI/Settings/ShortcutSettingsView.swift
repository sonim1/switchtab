import AppKit
import SwiftUI

public struct ShortcutSettingsView: View {
    private static let appDidBecomeActivePublisher = NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
    )

    @StateObject private var viewModel: ShortcutSettingsViewModel
    @StateObject private var applicationSettingsViewModel: ApplicationSettingsViewModel
    @State private var hasAppeared = false

    @MainActor
    public init(
        viewModel: ShortcutSettingsViewModel = ShortcutSettingsViewModel(),
        applicationSettingsViewModel: ApplicationSettingsViewModel? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _applicationSettingsViewModel = StateObject(
            wrappedValue: applicationSettingsViewModel ?? ApplicationSettingsViewModel()
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("General")
                    .font(.title2.weight(.semibold))

                Toggle(
                    "Start at login",
                    isOn: Binding(
                        get: { applicationSettingsViewModel.startsAtLogin },
                        set: { applicationSettingsViewModel.setStartsAtLogin($0) }
                    )
                )

                Toggle(
                    "Menubar Icon",
                    isOn: Binding(
                        get: { applicationSettingsViewModel.menuBarIconVisible },
                        set: { applicationSettingsViewModel.setMenuBarIconVisible($0) }
                    )
                )

                Picker(
                    "Overlay size",
                    selection: Binding(
                        get: { applicationSettingsViewModel.overlaySize },
                        set: { applicationSettingsViewModel.setOverlaySize($0) }
                    )
                ) {
                    ForEach(OverlaySizePreference.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                if applicationSettingsViewModel.updateCheckingAvailable {
                    Divider()

                    Text("Updates")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(applicationSettingsViewModel.currentVersionDisplay)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        applicationSettingsViewModel.checkForUpdates()
                    } label: {
                        Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                    }

                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { applicationSettingsViewModel.automaticallyChecksForUpdates },
                            set: { applicationSettingsViewModel.setAutomaticallyChecksForUpdates($0) }
                        )
                    )
                }

                Divider()

                Text("Window Shortcut")
                    .font(.title2.weight(.semibold))

                ShortcutRecorderRow(
                    setting: viewModel.currentAppWindowShortcut,
                    message: viewModel.registrationMessage()
                ) { capture in
                    viewModel.record(
                        capture: capture,
                        isUsable: true
                    )
                } onReset: {
                    viewModel.resetToDefault()
                }

                Divider()

                Text("Permissions")
                    .font(.title3.weight(.semibold))

                PermissionStatusView(items: viewModel.permissionState.permissionStatusItems) { destination in
                    NSWorkspace.shared.open(destination.systemSettingsURL)
                }

                if let errorMessage = applicationSettingsViewModel.errorMessage ?? viewModel.errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(width: 520, alignment: .topLeading)
        }
        .frame(width: 560, height: 520)
        .onAppear(perform: refreshPermissionStateAfterFirstAppear)
        .onReceive(Self.appDidBecomeActivePublisher) { _ in
            viewModel.refreshPermissionState()
        }
    }

    private func refreshPermissionStateAfterFirstAppear() {
        guard hasAppeared else {
            hasAppeared = true
            return
        }

        viewModel.refreshPermissionState()
    }
}

private struct ShortcutRecorderRow: View {
    let setting: ShortcutSetting
    let message: String?
    let onRecord: (ShortcutCapture) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    init(
        setting: ShortcutSetting,
        message: String?,
        onRecord: @escaping (ShortcutCapture) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.setting = setting
        self.message = message
        self.onRecord = onRecord
        self.onReset = onReset
    }

    var body: some View {
        let displayedShortcutText: String? = isRecording ? nil : setting.displayText
        let shortcutDisplayName = setting.displayName

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    beginRecording()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcutDisplayName)
                                .font(.body.weight(.medium))
                            Text(isRecording ? "Press shortcut now" : "Click to record")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 16)

                        Text(displayedShortcutText ?? "Recording...")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(isRecording ? 0.18 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(shortcutDisplayName) shortcut"))
                .accessibilityValue(Text(displayedShortcutText ?? "Recording"))
                .accessibilityHint(Text("Click, then press the shortcut keys to save."))

                Button {
                    onReset()
                } label: {
                    Label("Default", systemImage: "arrow.counterclockwise")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(isRecording || setting.isDefault)
                .accessibilityHint(Text("Restore the default shortcut."))
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .onDisappear {
            finishRecording()
        }
    }

    private func beginRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true
        installKeyMonitor()
        NotificationCenter.default.post(name: .shortcutRecordingDidBegin, object: nil)
    }

    private func finishRecording() {
        guard isRecording else {
            removeKeyMonitor()
            return
        }

        isRecording = false
        removeKeyMonitor()
        NotificationCenter.default.post(name: .shortcutRecordingDidEnd, object: nil)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                finishRecording()
                return nil
            }

            guard let capture = ShortcutCapture(event: event) else {
                return nil
            }

            onRecord(capture)
            finishRecording()
            return nil
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private extension ShortcutCapture {
    init?(event: NSEvent) {
        let key = ShortcutKeyCodeResolver.keyEquivalent(for: event.keyCode)
            ?? event.charactersIgnoringModifiers

        guard let key,
              !key.isEmpty else {
            return nil
        }

        self.init(keyEquivalent: key, modifiers: event.shortcutModifierNames, keyCode: event.keyCode)
    }
}

private extension NSEvent {
    var shortcutModifierNames: [String] {
        ShortcutModifierResolver.modifierNames(from: modifierFlags)
    }
}
