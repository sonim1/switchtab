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

                    VStack(alignment: .leading, spacing: 14) {
                        Text("SwitchTab")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(content.versionLine)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            if let buildLine = content.buildLine {
                                Text(buildLine)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.52))
                            }
                        }
                        Text("A keyboard-first macOS switcher for jumping between current-app windows with quick visual previews.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("SwitchTab runs locally and keeps its usage dashboard limited to shortcut counts on this Mac.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .background(Color(nsColor: NSColor(red: 0.16, green: 0.18, blue: 0.18, alpha: 1)))
    }

    private var usageDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.todaySummaryLine)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 14) {
                ForEach(content.usageDashboard.rows, id: \.title) { row in
                    usageTile(row)
                }
            }
        }
    }

    private func usageTile(_ row: UsageDashboardRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 0)
                Text(row.shortcutLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Text("\(row.count)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .background(Color.white.opacity(0.06))
    }
}
