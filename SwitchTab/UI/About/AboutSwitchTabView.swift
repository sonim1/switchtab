import AppKit
import SwiftUI

public struct AboutSwitchTabView: View {
    public let content: AboutSwitchTabContent
    public let onContactSupport: () -> Void
    public let onAcknowledgments: () -> Void
    private let applicationIconImage: NSImage

    public init(
        content: AboutSwitchTabContent,
        applicationIconImage: NSImage = NSApplication.shared.applicationIconImage,
        onContactSupport: @escaping () -> Void,
        onAcknowledgments: @escaping () -> Void
    ) {
        self.content = content
        self.applicationIconImage = applicationIconImage
        self.onContactSupport = onContactSupport
        self.onAcknowledgments = onAcknowledgments
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 28) {
                    Image(nsImage: applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 164, height: 164)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("SwitchTab")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.primary)
                            .accessibilityHeading(.h1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(content.versionLine)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if let buildLine = content.buildLine {
                                Text(buildLine)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Text("Keyboard shortcuts for switching applications and their windows, with quick visual previews.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The local dashboard counts window shortcut uses, including cancelled selections.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .contain)
                }

                Divider()

                usageDashboard
            }
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bottomBar
        }
        .frame(width: AboutWindowSizingPolicy.contentSize.width, height: AboutWindowSizingPolicy.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private var usageDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.todaySummaryLine)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHeading(.h2)

            HStack(spacing: 14) {
                ForEach(content.usageDashboard.rows, id: \.title) { row in
                    usageTile(row)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func usageTile(_ row: UsageDashboardRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(row.shortcutLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("\(row.count)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        HStack {
            Button("Contact Support", action: onContactSupport)
            Spacer()
            Button("Acknowledgments", action: onAcknowledgments)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 34)
        .frame(height: 76)
        .background(Color.primary.opacity(0.06))
    }
}
