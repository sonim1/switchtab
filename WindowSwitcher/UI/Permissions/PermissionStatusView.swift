import SwiftUI

public struct PermissionStatusView: View {
    public let items: [PermissionStatusItem]
    public let onOpenSettings: (PermissionSettingsDestination) -> Void

    public init(
        items: [PermissionStatusItem],
        onOpenSettings: @escaping (PermissionSettingsDestination) -> Void = { _ in }
    ) {
        self.items = items
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.permissionName) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.isGranted ? .green : .yellow)
                        .accessibilityHidden(true)

                    Text(item.permissionName)
                        .font(.headline)

                    Spacer(minLength: 12)

                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(item.detailText)
                        .accessibilityLabel(Text("\(item.permissionName) details"))

                    if !item.isGranted {
                        Button {
                            onOpenSettings(item.settingsDestination)
                        } label: {
                            Label(item.recoveryActionTitle, systemImage: "lock.open.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Open \(item.permissionName) Settings")
                        .accessibilityLabel(Text("Open \(item.permissionName) Settings"))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
