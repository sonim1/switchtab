import AppKit
import SwiftUI

public struct ShortcutSettingsView: View {
    private static let appDidBecomeActivePublisher = NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
    )

    @StateObject private var viewModel: ShortcutSettingsViewModel
    @StateObject private var applicationSettingsViewModel: ApplicationSettingsViewModel
    @State private var selectedPanel = SettingsPanel.general
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
        VStack(spacing: 0) {
            SettingsHeader(summary: SettingsPermissionSummary(permissionState: viewModel.permissionState))

            Picker("Settings section", selection: $selectedPanel) {
                ForEach(SettingsPanel.allCases) { panel in
                    Label(panel.title, systemImage: panel.symbolName)
                        .tag(panel)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
                .opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    selectedPanelView

                    if let errorMessage = applicationSettingsViewModel.errorMessage ?? viewModel.errorMessage {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 620, height: 500)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear(perform: refreshPermissionStateAfterFirstAppear)
        .onReceive(Self.appDidBecomeActivePublisher) { _ in
            viewModel.refreshPermissionState()
        }
    }

    @ViewBuilder
    private var selectedPanelView: some View {
        switch selectedPanel {
        case .general:
            GeneralSettingsPanel(viewModel: applicationSettingsViewModel)
        case .shortcut:
            ShortcutSettingsPanel(
                viewModel: viewModel,
                applicationSettingsViewModel: applicationSettingsViewModel
            )
        case .permissions:
            PermissionsSettingsPanel(viewModel: viewModel)
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

private enum SettingsPanel: String, CaseIterable, Identifiable {
    case general
    case shortcut
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .shortcut:
            "Shortcut"
        case .permissions:
            "Permissions"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "switch.2"
        case .shortcut:
            "keyboard"
        case .permissions:
            "lock.shield"
        }
    }
}

private struct SettingsHeader: View {
    let summary: SettingsPermissionSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("SwitchTab")
                    .font(.title2.weight(.semibold))

                Text("Window switching for the active app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            SettingsStatusPill(summary: summary)
                .layoutPriority(1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }
}

private struct SettingsStatusPill: View {
    let summary: SettingsPermissionSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: summary.symbolName)
                .foregroundStyle(summary.isReady ? .green : .yellow)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(.caption.weight(.semibold))

                Text(summary.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(minWidth: 228, alignment: .leading)
        .background((summary.isReady ? Color.green : Color.yellow).opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((summary.isReady ? Color.green : Color.yellow).opacity(0.22))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct GeneralSettingsPanel: View {
    @ObservedObject var viewModel: ApplicationSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(
                title: "General",
                subtitle: "Keep SwitchTab available without making it noisy.",
                symbolName: "switch.2"
            ) {
                SettingsRow(
                    symbolName: "power",
                    title: "Start at login",
                    detail: "Open SwitchTab automatically after signing in."
                ) {
                    Toggle(
                        "Start at login",
                        isOn: Binding(
                            get: { viewModel.startsAtLogin },
                            set: { viewModel.setStartsAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    symbolName: "menubar.rectangle",
                    title: "Menu bar icon",
                    detail: "Show quick access in the macOS menu bar."
                ) {
                    Toggle(
                        "Menu bar icon",
                        isOn: Binding(
                            get: { viewModel.menuBarIconVisible },
                            set: { viewModel.setMenuBarIconVisible($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    symbolName: "rectangle.resize",
                    title: "Overlay size",
                    detail: "Drag to resize the switcher thumbnails."
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { viewModel.overlaySizeScale.value },
                                set: { viewModel.setOverlaySizeScale(OverlaySizeScale($0)) }
                            ),
                            in: OverlaySizeScale.minimum...OverlaySizeScale.maximum,
                            step: OverlaySizeScale.step
                        )
                        .labelsHidden()
                        .frame(width: 180)
                        .accessibilityLabel(Text("Overlay size"))
                        .accessibilityValue(Text(viewModel.overlaySizeScale.percentageText))

                        Text(viewModel.overlaySizeScale.percentageText)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            if viewModel.updateCheckingAvailable {
                SettingsSection(
                    title: "Updates",
                    subtitle: "Keep direct-distribution builds current.",
                    symbolName: "arrow.triangle.2.circlepath"
                ) {
                    SettingsRow(
                        symbolName: "shippingbox",
                        title: "Version",
                        detail: viewModel.currentVersionDisplay
                    ) {
                        Button {
                            viewModel.checkForUpdates()
                        } label: {
                            Label("Check", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        symbolName: "sparkle.magnifyingglass",
                        title: "Automatic checks",
                        detail: "Look for updates in the background."
                    ) {
                        Toggle(
                            "Automatically check for updates",
                            isOn: Binding(
                                get: { viewModel.automaticallyChecksForUpdates },
                                set: { viewModel.setAutomaticallyChecksForUpdates($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            }
        }
    }
}

private struct ShortcutSettingsPanel: View {
    @ObservedObject var viewModel: ShortcutSettingsViewModel
    @ObservedObject var applicationSettingsViewModel: ApplicationSettingsViewModel

    var body: some View {
        SettingsSection(
            title: "Shortcuts",
            subtitle: "Configure window switching and optional Cmd-Tab replacement.",
            symbolName: "keyboard"
        ) {
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

            SettingsDivider()

            SettingsRow(
                symbolName: "command",
                title: "Replace macOS Cmd-Tab",
                detail: "Use SwitchTab to switch applications while it is running."
            ) {
                Toggle(
                    "Replace macOS Cmd-Tab",
                    isOn: Binding(
                        get: { applicationSettingsViewModel.replacesCommandTab },
                        set: { applicationSettingsViewModel.setReplacesCommandTab($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }
}

private struct PermissionsSettingsPanel: View {
    @ObservedObject var viewModel: ShortcutSettingsViewModel
    @State private var permissionRecoveryTask: Task<Void, Never>?

    var body: some View {
        SettingsSection(
            title: "Permissions",
            subtitle: "SwitchTab only asks for access needed to focus windows and show previews.",
            symbolName: "lock.shield"
        ) {
            PermissionStatusView(items: viewModel.permissionState.permissionStatusItems) { destination in
                permissionRecoveryTask?.cancel()
                permissionRecoveryTask = Task { @MainActor in
                    _ = try? await PermissionRecoveryCoordinator().recover(destination)
                }
            }
        }
        .onDisappear {
            permissionRecoveryTask?.cancel()
            permissionRecoveryTask = nil
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let symbolName: String
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            control
        }
        .frame(minHeight: 44)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 40)
            .opacity(0.55)
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
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcutDisplayName)
                        .font(.body.weight(.medium))
                    Text(isRecording ? "Press shortcut now" : "Click the keycap to record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button {
                    beginRecording()
                } label: {
                    Text(displayedShortcutText ?? "Recording...")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(isRecording ? 0.22 : 0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(isRecording ? 0.38 : 0.18))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(shortcutDisplayName) shortcut"))
                .accessibilityValue(Text(displayedShortcutText ?? "Recording"))
                .accessibilityHint(Text("Click, then press the shortcut keys to save."))

                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(isRecording || setting.isDefault)
                .buttonStyle(.borderless)
                .help("Restore the default shortcut")
                .accessibilityLabel(Text("Restore default shortcut"))
                .accessibilityHint(Text("Restore the default shortcut."))
            }
            .frame(minHeight: 44)

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
