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
                let primaryDetail = item.detailText.components(separatedBy: "\n").first ?? item.detailText

                HStack(spacing: 12) {
                    Image(systemName: item.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.isGranted ? .green : .yellow)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.permissionName)
                            .font(.body.weight(.semibold))

                        Text(primaryDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

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
                    } else {
                        Text("Enabled")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
