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

                    if let errorMessage = applicationSettingsViewModel.errorMessage {
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
            ShortcutSettingsPanel(viewModel: viewModel)
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

            if summary.showsStatusPill {
                SettingsStatusPill(summary: summary)
                    .layoutPriority(1)
            }
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
    @StateObject private var recordingCoordinator = ShortcutRecordingCoordinator()

    var body: some View {
        SettingsSection(
            title: "Shortcuts",
            subtitle: "Configure window and application switching shortcuts.",
            symbolName: "keyboard"
        ) {
            ForEach(SwitcherMode.allCases, id: \.rawValue) { mode in
                ShortcutRecorderRow(
                    configuration: viewModel.configuration(for: mode),
                    errorMessage: viewModel.errorMessage(for: mode),
                    registrationMessage: viewModel.registrationMessage(for: mode),
                    recordingCoordinator: recordingCoordinator,
                    onEnabledChanged: { enabled in
                        viewModel.setEnabled(enabled, for: mode)
                    },
                    onRecord: { capture in
                        _ = viewModel.record(capture: capture, for: mode)
                    },
                    onReset: {
                        _ = viewModel.resetToDefault(for: mode)
                    }
                )

                if mode != .applicationSwitching {
                    SettingsDivider()
                }
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

struct ShortcutSettingsRowLayout: Equatable, Sendable {
    static let standard = ShortcutSettingsRowLayout(
        keycapWidth: 184,
        keycapHorizontalPadding: 8,
        titleMinWidth: 126,
        titleSpacerMinLength: 8,
        statusWidth: 54,
        toggleWidth: 54,
        resetWidth: 20,
        rowContentWidth: 544,
        rowIconWidth: 28,
        rowHorizontalSpacing: 10,
        rightControlClusterSpacing: 6,
        minimumScaleFactor: 0.55,
        keycapLineLimit: 1,
        titleLineLimit: 1,
        rightControlClusterIsFixed: true
    )

    let keycapWidth: CGFloat
    let keycapHorizontalPadding: CGFloat
    let titleMinWidth: CGFloat
    let titleSpacerMinLength: CGFloat
    let statusWidth: CGFloat
    let toggleWidth: CGFloat
    let resetWidth: CGFloat
    let rowContentWidth: CGFloat
    let rowIconWidth: CGFloat
    let rowHorizontalSpacing: CGFloat
    let rightControlClusterSpacing: CGFloat
    let minimumScaleFactor: CGFloat
    let keycapLineLimit: Int
    let titleLineLimit: Int
    let rightControlClusterIsFixed: Bool

    var availableTitleWidth: CGFloat {
        rowContentWidth
            - rowIconWidth
            - (3 * rowHorizontalSpacing)
            - titleSpacerMinLength
            - statusWidth
            - toggleWidth
            - keycapWidth
            - resetWidth
            - (3 * rightControlClusterSpacing)
    }
}

struct ShortcutSettingsRowPresentation: Equatable, Sendable {
    let layout: ShortcutSettingsRowLayout
    let title: String
    let statusText: String
    let toggleAccessibilityLabel: String
    let shortcutAccessibilityLabel: String
    let resetAccessibilityLabel: String
    let resetAccessibilityHint: String

    init(mode: SwitcherMode, isEnabled: Bool) {
        let title: String
        switch mode {
        case .currentAppWindowSwitching:
            title = "Current App Windows"
        case .applicationSwitching:
            title = "Application Switching"
        }

        self.layout = .standard
        self.title = title
        self.statusText = isEnabled ? "Enabled" : "Disabled"
        self.toggleAccessibilityLabel = "Enable \(title)"
        self.shortcutAccessibilityLabel = "\(title) shortcut"
        self.resetAccessibilityLabel = "Restore \(title) default shortcut"
        self.resetAccessibilityHint = "Restore \(title) default shortcut."
    }
}

@MainActor
public final class ShortcutRecordingCoordinator: ObservableObject {
    @Published public private(set) var activeMode: SwitcherMode?

    private var stopActiveRecording: (() -> Void)?

    public init() {}

    public func begin(mode: SwitcherMode, onStop: @escaping () -> Void) {
        let previousStop = stopActiveRecording
        stopActiveRecording = nil
        activeMode = nil
        previousStop?()

        activeMode = mode
        stopActiveRecording = onStop
    }

    public func end(mode: SwitcherMode) {
        guard activeMode == mode else {
            return
        }

        stopActiveRecording = nil
        activeMode = nil
    }
}

private struct ShortcutRecorderRow: View {
    let configuration: SwitcherShortcutConfiguration
    let errorMessage: String?
    let registrationMessage: String?
    @ObservedObject var recordingCoordinator: ShortcutRecordingCoordinator
    let onEnabledChanged: (Bool) -> Void
    let onRecord: (ShortcutCapture) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    init(
        configuration: SwitcherShortcutConfiguration,
        errorMessage: String?,
        registrationMessage: String?,
        recordingCoordinator: ShortcutRecordingCoordinator,
        onEnabledChanged: @escaping (Bool) -> Void,
        onRecord: @escaping (ShortcutCapture) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.errorMessage = errorMessage
        self.registrationMessage = registrationMessage
        self.recordingCoordinator = recordingCoordinator
        self.onEnabledChanged = onEnabledChanged
        self.onRecord = onRecord
        self.onReset = onReset
    }

    var body: some View {
        let setting = configuration.shortcut
        let displayedShortcutText: String? = isRecording ? nil : setting.displayText
        let presentation = ShortcutSettingsRowPresentation(
            mode: configuration.mode,
            isEnabled: configuration.isEnabled
        )
        let layout = presentation.layout
        let isDefault = setting == SwitcherShortcutConfiguration.defaultValue(for: configuration.mode).shortcut

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: layout.rowHorizontalSpacing) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.rowIconWidth, height: layout.rowIconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.body.weight(.medium))
                        .lineLimit(layout.titleLineLimit)
                    Text(isRecording ? "Press shortcut now" : "Click the keycap to record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(layout.titleLineLimit)
                        .truncationMode(.tail)
                }
                .frame(minWidth: layout.titleMinWidth, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: layout.titleSpacerMinLength)

                HStack(spacing: layout.rightControlClusterSpacing) {
                    Text(presentation.statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(configuration.isEnabled ? .primary : .secondary)
                        .frame(width: layout.statusWidth, alignment: .trailing)
                        .accessibilityLabel(Text("\(presentation.title) status"))
                        .accessibilityValue(Text(presentation.statusText))

                    Toggle(
                        presentation.toggleAccessibilityLabel,
                        isOn: Binding(
                            get: { configuration.isEnabled },
                            set: { newValue in
                                onEnabledChanged(newValue)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .frame(width: layout.toggleWidth)

                    Button {
                        beginRecording()
                    } label: {
                        Text(displayedShortcutText ?? "Recording...")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .lineLimit(layout.keycapLineLimit)
                            .minimumScaleFactor(layout.minimumScaleFactor)
                            .padding(.horizontal, layout.keycapHorizontalPadding)
                            .padding(.vertical, 7)
                            .frame(width: layout.keycapWidth)
                            .background(Color.accentColor.opacity(isRecording ? 0.22 : 0.13))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(isRecording ? 0.38 : 0.18))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isRecording)
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(presentation.shortcutAccessibilityLabel))
                    .accessibilityValue(Text(displayedShortcutText ?? "Recording"))
                    .accessibilityHint(Text("Click, then press the shortcut keys to save."))

                    Button {
                        onReset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .frame(width: layout.resetWidth)
                    .disabled(isRecording || isDefault)
                    .buttonStyle(.borderless)
                    .help("Restore the default shortcut")
                    .accessibilityLabel(Text(presentation.resetAccessibilityLabel))
                    .accessibilityHint(Text(presentation.resetAccessibilityHint))
                }
                .fixedSize(horizontal: layout.rightControlClusterIsFixed, vertical: false)
            }
            .frame(minHeight: 44)
            .frame(maxWidth: layout.rowContentWidth, alignment: .leading)

            if let message = errorMessage ?? registrationMessage {
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

        recordingCoordinator.begin(mode: configuration.mode) {
            finishRecording()
        }
        isRecording = true
        installKeyMonitor()
        NotificationCenter.default.post(name: .shortcutRecordingDidBegin, object: nil)
    }

    private func finishRecording() {
        let wasRecording = isRecording
        isRecording = false
        removeKeyMonitor()
        recordingCoordinator.end(mode: configuration.mode)

        guard wasRecording else {
            return
        }

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
